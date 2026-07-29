{*******************************************************************}
{                                                                   }
{       ExpressMemData - format converters                          }
{                                                                   }
{       Converts a TdxCustomMemData (TdxMemData) to and from XML,    }
{       JSON and delimited text (RFC 4180 CSV / TSV).                }
{                                                                   }
{       The unit is self-contained: it only uses the RTL and the     }
{       public API of dxmdaset, so it can simply be added to a       }
{       project next to dxmdaset.pas.                                }
{                                                                   }
{*******************************************************************}

unit dxmdConvert;

interface

{$I cxVer.inc}

uses
  System.Classes, System.SysUtils, Data.DB, dxmdaset;

type
  TdxMemDataFormat = (mdfXml, mdfJson, mdfText);

  EdxMemDataConvertError = class(Exception);

const
  dxMemDataDefaultDelimiter = ',';

{ Conversion to/from a string }

function dxMemDataToXml(AMemData: TdxCustomMemData): string;
function dxMemDataToJson(AMemData: TdxCustomMemData): string;
function dxMemDataToText(AMemData: TdxCustomMemData;
  ADelimiter: Char = dxMemDataDefaultDelimiter): string;

procedure dxMemDataFromXml(AMemData: TdxCustomMemData; const AText: string;
  ACreateFields: Boolean = True);
procedure dxMemDataFromJson(AMemData: TdxCustomMemData; const AText: string;
  ACreateFields: Boolean = True);
procedure dxMemDataFromText(AMemData: TdxCustomMemData; const AText: string;
  ADelimiter: Char = dxMemDataDefaultDelimiter; ACreateFields: Boolean = True);

{ Generic entry points. ADelimiter is used by mdfText only. }

function dxMemDataToString(AMemData: TdxCustomMemData; AFormat: TdxMemDataFormat;
  ADelimiter: Char = dxMemDataDefaultDelimiter): string;
procedure dxMemDataFromString(AMemData: TdxCustomMemData; const AText: string;
  AFormat: TdxMemDataFormat; ACreateFields: Boolean = True;
  ADelimiter: Char = dxMemDataDefaultDelimiter);

procedure dxMemDataSaveToStream(AMemData: TdxCustomMemData; AStream: TStream;
  AFormat: TdxMemDataFormat; ADelimiter: Char = dxMemDataDefaultDelimiter);
procedure dxMemDataLoadFromStream(AMemData: TdxCustomMemData; AStream: TStream;
  AFormat: TdxMemDataFormat; ACreateFields: Boolean = True;
  ADelimiter: Char = dxMemDataDefaultDelimiter);

procedure dxMemDataSaveToFile(AMemData: TdxCustomMemData; const AFileName: string;
  AFormat: TdxMemDataFormat; ADelimiter: Char = dxMemDataDefaultDelimiter);
procedure dxMemDataLoadFromFile(AMemData: TdxCustomMemData; const AFileName: string;
  AFormat: TdxMemDataFormat; ACreateFields: Boolean = True;
  ADelimiter: Char = dxMemDataDefaultDelimiter);

implementation

uses
  System.TypInfo, System.Variants;

resourcestring
  sdxNotActive = 'Cannot export %s: the dataset is not active';
  sdxNoFields = 'Cannot import into %s: the dataset has no fields and the ' +
    'source contains no field schema';
  sdxMalformed = 'Malformed %s at position %d';

type
  TdxFieldSchema = record
    Name: string;
    DataType: TFieldType;
    Size: Integer;
    Required: Boolean;
  end;
  TdxFieldSchemas = array of TdxFieldSchema;

var
  FInvSettings: TFormatSettings;

{ ---------------------------------------------------------------------------
  Base64
  --------------------------------------------------------------------------- }

const
  Base64Alphabet: string =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function Base64Encode(const ABytes: TBytes): string;
var
  I, ACount, ATriple: Integer;
  ASB: TStringBuilder;
begin
  ACount := Length(ABytes);
  if ACount = 0 then
  begin
    Result := '';
    Exit;
  end;
  ASB := TStringBuilder.Create(((ACount + 2) div 3) * 4);
  try
    I := 0;
    while I + 2 < ACount do
    begin
      ATriple := (ABytes[I] shl 16) or (ABytes[I + 1] shl 8) or ABytes[I + 2];
      ASB.Append(Base64Alphabet[(ATriple shr 18) + 1]);
      ASB.Append(Base64Alphabet[((ATriple shr 12) and $3F) + 1]);
      ASB.Append(Base64Alphabet[((ATriple shr 6) and $3F) + 1]);
      ASB.Append(Base64Alphabet[(ATriple and $3F) + 1]);
      Inc(I, 3);
    end;
    case ACount - I of
      1:
        begin
          ATriple := ABytes[I] shl 16;
          ASB.Append(Base64Alphabet[(ATriple shr 18) + 1]);
          ASB.Append(Base64Alphabet[((ATriple shr 12) and $3F) + 1]);
          ASB.Append('==');
        end;
      2:
        begin
          ATriple := (ABytes[I] shl 16) or (ABytes[I + 1] shl 8);
          ASB.Append(Base64Alphabet[(ATriple shr 18) + 1]);
          ASB.Append(Base64Alphabet[((ATriple shr 12) and $3F) + 1]);
          ASB.Append(Base64Alphabet[((ATriple shr 6) and $3F) + 1]);
          ASB.Append('=');
        end;
    end;
    Result := ASB.ToString;
  finally
    ASB.Free;
  end;
end;

function Base64Decode(const AText: string): TBytes;
var
  ADecodeTable: array[0..127] of ShortInt;
  I, J, ALen, ABits, ABitCount, AValue: Integer;
  ACh: Char;
begin
  for I := 0 to 127 do
    ADecodeTable[I] := -1;
  for I := 1 to Length(Base64Alphabet) do
    ADecodeTable[Ord(Base64Alphabet[I])] := I - 1;

  ALen := Length(AText);
  SetLength(Result, (ALen div 4) * 3 + 3);
  J := 0;
  ABits := 0;
  ABitCount := 0;
  for I := 1 to ALen do
  begin
    ACh := AText[I];
    if (ACh = '=') then
      Break;
    if Ord(ACh) > 127 then
      Continue;
    AValue := ADecodeTable[Ord(ACh)];
    if AValue < 0 then // white space and any other noise
      Continue;
    ABits := (ABits shl 6) or AValue;
    Inc(ABitCount, 6);
    if ABitCount >= 8 then
    begin
      Dec(ABitCount, 8);
      Result[J] := Byte((ABits shr ABitCount) and $FF);
      Inc(J);
    end;
  end;
  SetLength(Result, J);
end;

{ ---------------------------------------------------------------------------
  Locale independent scalar conversion
  --------------------------------------------------------------------------- }

function TryParseISODateTime(const AText: string; out AValue: TDateTime): Boolean;

  function Num(AStart, ALength: Integer): Integer;
  begin
    Result := StrToIntDef(Copy(AText, AStart, ALength), -1);
  end;

var
  AYear, AMonth, ADay, AHour, AMin, ASec, AMSec, ATimePos: Integer;
  ADatePart, ATimePart: TDateTime;
  S: string;
begin
  Result := False;
  AValue := 0;
  S := Trim(AText);
  if S = '' then
    Exit;

  ADatePart := 0;
  ATimePart := 0;
  ATimePos := 1;

  // date part - yyyy-mm-dd
  if (Length(S) >= 10) and (S[5] = '-') and (S[8] = '-') then
  begin
    AYear := Num(1, 4);
    AMonth := Num(6, 2);
    ADay := Num(9, 2);
    if (AYear < 0) or (AMonth < 0) or (ADay < 0) then
      Exit;
    if not TryEncodeDate(AYear, AMonth, ADay, ADatePart) then
      Exit;
    ATimePos := 11;
    if (Length(S) >= ATimePos) and CharInSet(S[ATimePos], ['T', 't', ' ']) then
      Inc(ATimePos)
    else
      if Length(S) >= ATimePos then
        Exit;
  end;

  // time part - hh:nn:ss[.zzz]
  if Length(S) >= ATimePos + 4 then
  begin
    if (S[ATimePos + 2] <> ':') then
      Exit;
    AHour := Num(ATimePos, 2);
    AMin := Num(ATimePos + 3, 2);
    ASec := 0;
    AMSec := 0;
    if (Length(S) >= ATimePos + 7) and (S[ATimePos + 5] = ':') then
      ASec := Num(ATimePos + 6, 2);
    if (Length(S) >= ATimePos + 11) and (S[ATimePos + 8] = '.') then
      AMSec := Num(ATimePos + 9, 3);
    if (AHour < 0) or (AMin < 0) or (ASec < 0) or (AMSec < 0) then
      Exit;
    if not TryEncodeTime(AHour, AMin, ASec, AMSec, ATimePart) then
      Exit;
  end;

  if ADatePart < 0 then
    AValue := ADatePart - ATimePart
  else
    AValue := ADatePart + ATimePart;
  Result := True;
end;

function IsBinaryField(AField: TField): Boolean;
begin
  Result := AField.DataType in [ftBlob, ftGraphic, ftParadoxOle, ftDBaseOle,
    ftTypedBinary];
end;

function BlobToBytes(AField: TField): TBytes;
var
  AStream: TMemoryStream;
begin
  AStream := TMemoryStream.Create;
  try
    TBlobField(AField).SaveToStream(AStream);
    SetLength(Result, AStream.Size);
    if AStream.Size > 0 then
      Move(AStream.Memory^, Result[0], AStream.Size);
  finally
    AStream.Free;
  end;
end;

procedure BytesToBlob(AField: TField; const ABytes: TBytes);
var
  AStream: TMemoryStream;
begin
  AStream := TMemoryStream.Create;
  try
    if Length(ABytes) > 0 then
      AStream.WriteBuffer(ABytes[0], Length(ABytes));
    AStream.Position := 0;
    TBlobField(AField).LoadFromStream(AStream);
  finally
    AStream.Free;
  end;
end;

// Textual, locale independent representation of the current field value.
function FieldToText(AField: TField): string;
begin
  case AField.DataType of
    ftBoolean:
      if AField.AsBoolean then
        Result := 'true'
      else
        Result := 'false';
    ftDate:
      Result := FormatDateTime('yyyy"-"mm"-"dd', AField.AsDateTime);
    ftTime:
      Result := FormatDateTime('hh":"nn":"ss"."zzz', AField.AsDateTime);
    ftDateTime, ftTimeStamp:
      Result := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss"."zzz', AField.AsDateTime);
    ftCurrency:
      Result := CurrToStr(AField.AsCurrency, FInvSettings);
    ftFloat, ftBCD, ftFMTBcd, Data.DB.ftExtended:
      Result := FloatToStr(AField.AsFloat, FInvSettings);
    ftBlob, ftGraphic, ftParadoxOle, ftDBaseOle, ftTypedBinary:
      Result := Base64Encode(BlobToBytes(AField));
  else
    Result := AField.AsString;
  end;
end;

// Reverse of FieldToText. The field must be in edit/insert state.
procedure TextToField(AField: TField; const AText: string);
var
  ADateTime: TDateTime;
begin
  case AField.DataType of
    ftBoolean:
      AField.AsBoolean := SameText(AText, 'true') or (AText = '1') or
        SameText(AText, 'yes');
    ftDate, ftTime, ftDateTime, ftTimeStamp:
      begin
        if not TryParseISODateTime(AText, ADateTime) then
          ADateTime := StrToDateTimeDef(AText, 0); // tolerate a localized source
        AField.AsDateTime := ADateTime;
      end;
    ftCurrency:
      AField.AsCurrency := StrToCurr(AText, FInvSettings);
    ftFloat, ftBCD, ftFMTBcd, Data.DB.ftExtended:
      AField.AsFloat := StrToFloat(AText, FInvSettings);
    ftBlob, ftGraphic, ftParadoxOle, ftDBaseOle, ftTypedBinary:
      BytesToBlob(AField, Base64Decode(AText));
  else
    AField.AsString := AText;
  end;
end;

function FieldTypeToName(AType: TFieldType): string;
begin
  Result := GetEnumName(TypeInfo(TFieldType), Ord(AType));
end;

function NameToFieldType(const AName: string): TFieldType;
var
  AValue: Integer;
begin
  AValue := GetEnumValue(TypeInfo(TFieldType), AName);
  if AValue < 0 then
    Result := ftString
  else
    Result := TFieldType(AValue);
end;

{ ---------------------------------------------------------------------------
  Shared helpers for the dataset side
  --------------------------------------------------------------------------- }

// The fields that take part in export/import: no calculated, lookup or
// unsupported fields (RecId is calculated, so it drops out here as well).
procedure GetExportFields(AMemData: TdxCustomMemData; AList: TList);
var
  I: Integer;
  AField: TField;
begin
  AList.Clear;
  for I := 0 to AMemData.FieldCount - 1 do
  begin
    AField := AMemData.Fields[I];
    if not AField.Calculated and not AField.Lookup and
      AMemData.SupportedFieldType(AField.DataType) then
      AList.Add(AField);
  end;
end;

procedure CheckActive(AMemData: TdxCustomMemData);
begin
  if not AMemData.Active then
    raise EdxMemDataConvertError.CreateFmt(sdxNotActive, [AMemData.Name]);
end;

type
  // Feeds rows into the dataset. Shared by the XML, JSON and text readers.
  TdxMemDataLoader = class
  private
    FMemData: TdxCustomMemData;
    FFields: TList;
    FReadOnly: array of Boolean;
    FSortedField: string;
    FInRow: Boolean;
    FPrepared: Boolean;
  public
    constructor Create(AMemData: TdxCustomMemData);
    destructor Destroy; override;
    procedure Prepare(const ASchema: TdxFieldSchemas; ACreateFields: Boolean);
    procedure BeginRow;
    procedure SetValue(const AFieldName, AText: string);
    procedure EndRow;
  end;

constructor TdxMemDataLoader.Create(AMemData: TdxCustomMemData);
begin
  inherited Create;
  FMemData := AMemData;
  FFields := TList.Create;
end;

destructor TdxMemDataLoader.Destroy;
var
  I: Integer;
begin
  if FPrepared then
  begin
    if FInRow then
      FMemData.Cancel;
    FMemData.IsLoading := False;
    for I := 0 to FFields.Count - 1 do
      TField(FFields[I]).ReadOnly := FReadOnly[I];
    // SetSortedField ignores an unchanged value, so bounce it to re-sort
    if FSortedField <> '' then
    begin
      FMemData.SortedField := '';
      FMemData.SortedField := FSortedField;
    end;
    if FMemData.Active then
      FMemData.First;
    FMemData.EnableControls;
  end;
  FFields.Free;
  inherited Destroy;
end;

procedure TdxMemDataLoader.Prepare(const ASchema: TdxFieldSchemas;
  ACreateFields: Boolean);
var
  I: Integer;
  AField: TField;
  AFieldClass: TFieldClass;
begin
  if FPrepared then
    Exit;

  FMemData.DisableControls;
  try
    if ACreateFields and (Length(ASchema) > 0) then
    begin
      FMemData.Close;
      for I := FMemData.FieldCount - 1 downto 0 do
        if FMemData.Fields[I] <> FMemData.RecIdField then
          FMemData.Fields[I].Free;
      for I := 0 to High(ASchema) do
      begin
        if not FMemData.SupportedFieldType(ASchema[I].DataType) then
          Continue;
        AFieldClass := DefaultFieldClasses[ASchema[I].DataType];
        if AFieldClass = nil then
          Continue;
        AField := AFieldClass.Create(FMemData);
        AField.FieldName := ASchema[I].Name;
        if (AField is TStringField) or (AField is TBlobField) then
          AField.Size := ASchema[I].Size;
        AField.Required := ASchema[I].Required;
        AField.DataSet := FMemData;
      end;
    end;

    if not FMemData.Active then
      FMemData.Open;

    GetExportFields(FMemData, FFields);
    if FFields.Count = 0 then
      raise EdxMemDataConvertError.CreateFmt(sdxNoFields, [FMemData.Name]);

    // ftAutoInc fields are read-only by default; clear that so the stored
    // values survive the round trip
    SetLength(FReadOnly, FFields.Count);
    for I := 0 to FFields.Count - 1 do
    begin
      FReadOnly[I] := TField(FFields[I]).ReadOnly;
      TField(FFields[I]).ReadOnly := False;
    end;

    FSortedField := FMemData.SortedField;
    // suppresses events, sorting and auto-increment generation, exactly like
    // the binary loader does
    FMemData.IsLoading := True;
    FPrepared := True;
  except
    FMemData.EnableControls;
    raise;
  end;
end;

procedure TdxMemDataLoader.BeginRow;
begin
  FMemData.Append;
  FInRow := True;
end;

procedure TdxMemDataLoader.SetValue(const AFieldName, AText: string);
var
  AField: TField;
begin
  if not FInRow then
    Exit;
  AField := FMemData.FindField(AFieldName);
  if (AField = nil) or AField.Calculated or AField.Lookup or
    (FFields.IndexOf(AField) < 0) then
    Exit;
  TextToField(AField, AText);
end;

procedure TdxMemDataLoader.EndRow;
begin
  if FInRow then
  begin
    FInRow := False;
    FMemData.Post;
  end;
end;

{ ---------------------------------------------------------------------------
  XML
  --------------------------------------------------------------------------- }

function XmlEscape(const AText: string): string;
var
  I: Integer;
  ACh: Char;
  ASB: TStringBuilder;
begin
  ASB := TStringBuilder.Create(Length(AText) + 16);
  try
    for I := 1 to Length(AText) do
    begin
      ACh := AText[I];
      case ACh of
        '&': ASB.Append('&amp;');
        '<': ASB.Append('&lt;');
        '>': ASB.Append('&gt;');
        '"': ASB.Append('&quot;');
        '''': ASB.Append('&apos;');
      else
        // character references keep CR/LF/TAB intact through the whitespace
        // normalisation any conforming XML reader performs
        if ACh < ' ' then
          ASB.Append('&#').Append(Ord(ACh)).Append(';')
        else
          ASB.Append(ACh);
      end;
    end;
    Result := ASB.ToString;
  finally
    ASB.Free;
  end;
end;

function XmlDecode(const AText: string): string;
var
  I, AEnd, ACode: Integer;
  AEntity: string;
  ASB: TStringBuilder;
begin
  if Pos('&', AText) = 0 then
  begin
    Result := AText;
    Exit;
  end;
  ASB := TStringBuilder.Create(Length(AText));
  try
    I := 1;
    while I <= Length(AText) do
    begin
      if AText[I] = '&' then
      begin
        AEnd := I + 1;
        while (AEnd <= Length(AText)) and (AText[AEnd] <> ';') and
          (AEnd - I <= 10) do
          Inc(AEnd);
        if (AEnd <= Length(AText)) and (AText[AEnd] = ';') then
        begin
          AEntity := Copy(AText, I + 1, AEnd - I - 1);
          if AEntity = 'amp' then
            ASB.Append('&')
          else if AEntity = 'lt' then
            ASB.Append('<')
          else if AEntity = 'gt' then
            ASB.Append('>')
          else if AEntity = 'quot' then
            ASB.Append('"')
          else if AEntity = 'apos' then
            ASB.Append('''')
          else if (Length(AEntity) > 1) and (AEntity[1] = '#') then
          begin
            if CharInSet(AEntity[2], ['x', 'X']) then
              ACode := StrToIntDef('$' + Copy(AEntity, 3, MaxInt), -1)
            else
              ACode := StrToIntDef(Copy(AEntity, 2, MaxInt), -1);
            if ACode >= 0 then
              ASB.Append(Char(ACode))
            else
              ASB.Append('&').Append(AEntity).Append(';');
          end
          else
            ASB.Append('&').Append(AEntity).Append(';');
          I := AEnd + 1;
          Continue;
        end;
      end;
      ASB.Append(AText[I]);
      Inc(I);
    end;
    Result := ASB.ToString;
  finally
    ASB.Free;
  end;
end;

// Field names may contain characters that are illegal in an XML element name
// (spaces, '#', ...). Such names are sanitised and the original is kept in the
// "n" attribute.
function XmlElementName(const AFieldName: string; out AChanged: Boolean): string;
var
  I: Integer;
begin
  Result := AFieldName;
  AChanged := False;
  for I := 1 to Length(Result) do
    if not (CharInSet(Result[I], ['A'..'Z', 'a'..'z', '0'..'9', '_']) or
      ((I > 1) and CharInSet(Result[I], ['-', '.']))) then
    begin
      Result[I] := '_';
      AChanged := True;
    end;
  if (Result = '') or CharInSet(Result[1], ['0'..'9', '-', '.']) then
  begin
    Result := '_' + Result;
    AChanged := True;
  end;
end;

function dxMemDataToXml(AMemData: TdxCustomMemData): string;
var
  ASB: TStringBuilder;
  AFields: TList;
  ABookmark: TBookmark;
  I: Integer;
  AField: TField;
  AName: string;
  AChanged: Boolean;
begin
  CheckActive(AMemData);
  ASB := TStringBuilder.Create;
  AFields := TList.Create;
  try
    GetExportFields(AMemData, AFields);
    ASB.AppendLine('<?xml version="1.0" encoding="UTF-8"?>');
    ASB.AppendLine('<dxmemdata version="1.0">');

    ASB.AppendLine('  <fields>');
    for I := 0 to AFields.Count - 1 do
    begin
      AField := TField(AFields[I]);
      ASB.Append('    <field name="').Append(XmlEscape(AField.FieldName));
      ASB.Append('" type="').Append(FieldTypeToName(AField.DataType));
      ASB.Append('" size="').Append(AField.Size);
      if AField.Required then
        ASB.Append('" required="true');
      ASB.AppendLine('"/>');
    end;
    ASB.AppendLine('  </fields>');

    ASB.AppendLine('  <rows>');
    AMemData.DisableControls;
    ABookmark := AMemData.GetBookmark;
    try
      AMemData.First;
      while not AMemData.Eof do
      begin
        ASB.AppendLine('    <row>');
        for I := 0 to AFields.Count - 1 do
        begin
          AField := TField(AFields[I]);
          if AField.IsNull then // an absent element means NULL
            Continue;
          AName := XmlElementName(AField.FieldName, AChanged);
          ASB.Append('      <').Append(AName);
          if AChanged then
            ASB.Append(' n="').Append(XmlEscape(AField.FieldName)).Append('"');
          if IsBinaryField(AField) then
            ASB.Append(' encoding="base64"');
          ASB.Append('>').Append(XmlEscape(FieldToText(AField)));
          ASB.Append('</').Append(AName).AppendLine('>');
        end;
        ASB.AppendLine('    </row>');
        AMemData.Next;
      end;
      if AMemData.BookmarkValid(ABookmark) then
        AMemData.GotoBookmark(ABookmark);
    finally
      AMemData.FreeBookmark(ABookmark);
      AMemData.EnableControls;
    end;
    ASB.AppendLine('  </rows>');
    ASB.AppendLine('</dxmemdata>');
    Result := ASB.ToString;
  finally
    AFields.Free;
    ASB.Free;
  end;
end;

type
  TdxXmlNodeKind = (xnEof, xnStart, xnEnd, xnText);

  // Minimal pull parser: enough for the documents written above and for any
  // reasonably simple hand written or third party XML.
  TdxXmlReader = class
  private
    FText: string;
    FPos: Integer;
    FKind: TdxXmlNodeKind;
    FName: string;
    FValue: string;
    FSelfClosing: Boolean;
    FAttrs: TStringList;
    function ReadName: string;
    procedure ReadAttrs;
    procedure SkipSpaces;
  public
    constructor Create(const AText: string);
    destructor Destroy; override;
    function Next: Boolean;
    function AttrByName(const AName: string): string;
    property Kind: TdxXmlNodeKind read FKind;
    property Name: string read FName;
    property Value: string read FValue;
    property SelfClosing: Boolean read FSelfClosing;
  end;

constructor TdxXmlReader.Create(const AText: string);
begin
  inherited Create;
  FText := AText;
  FPos := 1;
  FAttrs := TStringList.Create;
  FAttrs.CaseSensitive := False;
end;

destructor TdxXmlReader.Destroy;
begin
  FAttrs.Free;
  inherited Destroy;
end;

procedure TdxXmlReader.SkipSpaces;
begin
  while (FPos <= Length(FText)) and CharInSet(FText[FPos], [#9, #10, #13, ' ']) do
    Inc(FPos);
end;

function TdxXmlReader.ReadName: string;
var
  AStart: Integer;
begin
  AStart := FPos;
  while (FPos <= Length(FText)) and not CharInSet(FText[FPos],
    [#9, #10, #13, ' ', '/', '>', '=']) do
    Inc(FPos);
  Result := Copy(FText, AStart, FPos - AStart);
end;

procedure TdxXmlReader.ReadAttrs;
var
  AName, AValue: string;
  AQuote: Char;
  AStart: Integer;
begin
  FAttrs.Clear;
  while True do
  begin
    SkipSpaces;
    if (FPos > Length(FText)) or CharInSet(FText[FPos], ['/', '>']) then
      Break;
    AName := ReadName;
    if AName = '' then
    begin
      Inc(FPos); // do not spin on unexpected input
      Continue;
    end;
    SkipSpaces;
    AValue := '';
    if (FPos <= Length(FText)) and (FText[FPos] = '=') then
    begin
      Inc(FPos);
      SkipSpaces;
      if (FPos <= Length(FText)) and CharInSet(FText[FPos], ['"', '''']) then
      begin
        AQuote := FText[FPos];
        Inc(FPos);
        AStart := FPos;
        while (FPos <= Length(FText)) and (FText[FPos] <> AQuote) do
          Inc(FPos);
        AValue := XmlDecode(Copy(FText, AStart, FPos - AStart));
        Inc(FPos);
      end
      else
        AValue := XmlDecode(ReadName);
    end;
    FAttrs.Add(AName + '=' + AValue);
  end;
end;

function TdxXmlReader.AttrByName(const AName: string): string;
begin
  Result := FAttrs.Values[AName];
end;

function TdxXmlReader.Next: Boolean;
var
  AStart, AStop: Integer;
begin
  FSelfClosing := False;
  FName := '';
  FValue := '';
  while True do
  begin
    if FPos > Length(FText) then
    begin
      FKind := xnEof;
      Result := False;
      Exit;
    end;

    if FText[FPos] <> '<' then
    begin
      AStart := FPos;
      while (FPos <= Length(FText)) and (FText[FPos] <> '<') do
        Inc(FPos);
      FKind := xnText;
      FValue := XmlDecode(Copy(FText, AStart, FPos - AStart));
      Result := True;
      Exit;
    end;

    if Copy(FText, FPos, 4) = '<!--' then
    begin
      AStop := Pos('-->', FText, FPos + 4);
      if AStop = 0 then
        FPos := Length(FText) + 1
      else
        FPos := AStop + 3;
      Continue;
    end;

    if Copy(FText, FPos, 9) = '<![CDATA[' then
    begin
      AStop := Pos(']]>', FText, FPos + 9);
      if AStop = 0 then
        AStop := Length(FText) + 1;
      FKind := xnText;
      FValue := Copy(FText, FPos + 9, AStop - FPos - 9);
      FPos := AStop + 3;
      Result := True;
      Exit;
    end;

    if (FPos < Length(FText)) and CharInSet(FText[FPos + 1], ['?', '!']) then
    begin
      AStop := Pos('>', FText, FPos);
      if AStop = 0 then
        FPos := Length(FText) + 1
      else
        FPos := AStop + 1;
      Continue;
    end;

    if (FPos < Length(FText)) and (FText[FPos + 1] = '/') then
    begin
      Inc(FPos, 2);
      FName := ReadName;
      AStop := Pos('>', FText, FPos);
      if AStop = 0 then
        FPos := Length(FText) + 1
      else
        FPos := AStop + 1;
      FKind := xnEnd;
      Result := True;
      Exit;
    end;

    Inc(FPos);
    FName := ReadName;
    ReadAttrs;
    if (FPos <= Length(FText)) and (FText[FPos] = '/') then
    begin
      FSelfClosing := True;
      Inc(FPos);
    end;
    if (FPos <= Length(FText)) and (FText[FPos] = '>') then
      Inc(FPos);
    FKind := xnStart;
    Result := True;
    Exit;
  end;
end;

procedure dxMemDataFromXml(AMemData: TdxCustomMemData; const AText: string;
  ACreateFields: Boolean);
var
  AReader: TdxXmlReader;
  ALoader: TdxMemDataLoader;
  ASchema: TdxFieldSchemas;
  ACount: Integer;
  AInRow, AInValue: Boolean;
  ACurName, ACurText: string;

  procedure FlushValue;
  begin
    if AInValue then
    begin
      ALoader.SetValue(ACurName, ACurText);
      AInValue := False;
    end;
  end;

begin
  AReader := TdxXmlReader.Create(AText);
  ALoader := TdxMemDataLoader.Create(AMemData);
  try
    ACount := 0;
    AInRow := False;
    AInValue := False;
    while AReader.Next do
      case AReader.Kind of
        xnStart:
          if SameText(AReader.Name, 'field') and not AInRow then
          begin
            SetLength(ASchema, ACount + 1);
            ASchema[ACount].Name := AReader.AttrByName('name');
            ASchema[ACount].DataType := NameToFieldType(AReader.AttrByName('type'));
            ASchema[ACount].Size := StrToIntDef(AReader.AttrByName('size'), 0);
            ASchema[ACount].Required := SameText(AReader.AttrByName('required'), 'true');
            Inc(ACount);
          end
          else if SameText(AReader.Name, 'row') then
          begin
            ALoader.Prepare(ASchema, ACreateFields);
            ALoader.BeginRow;
            AInRow := True;
            if AReader.SelfClosing then
            begin
              ALoader.EndRow;
              AInRow := False;
            end;
          end
          else if AInRow then
          begin
            ACurName := AReader.AttrByName('n');
            if ACurName = '' then
              ACurName := AReader.Name;
            ACurText := '';
            AInValue := True;
            if AReader.SelfClosing then
              FlushValue;
          end;
        xnText:
          if AInValue then
            ACurText := ACurText + AReader.Value;
        xnEnd:
          if SameText(AReader.Name, 'row') then
          begin
            FlushValue;
            ALoader.EndRow;
            AInRow := False;
          end
          else
            FlushValue;
      end;
  finally
    ALoader.Free;
    AReader.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  JSON
  --------------------------------------------------------------------------- }

function JsonEscape(const AText: string): string;
var
  I: Integer;
  ACh: Char;
  ASB: TStringBuilder;
begin
  ASB := TStringBuilder.Create(Length(AText) + 16);
  try
    for I := 1 to Length(AText) do
    begin
      ACh := AText[I];
      case ACh of
        '"': ASB.Append('\"');
        '\': ASB.Append('\\');
        #8: ASB.Append('\b');
        #9: ASB.Append('\t');
        #10: ASB.Append('\n');
        #12: ASB.Append('\f');
        #13: ASB.Append('\r');
      else
        if ACh < ' ' then
          ASB.Append('\u').Append(IntToHex(Ord(ACh), 4))
        else
          ASB.Append(ACh);
      end;
    end;
    Result := ASB.ToString;
  finally
    ASB.Free;
  end;
end;

// True when the textual value can be written as a bare JSON literal.
function IsJsonLiteralField(AField: TField): Boolean;
begin
  Result := AField.DataType in [ftBoolean, ftSmallint, ftInteger, ftWord,
    ftAutoInc, ftLargeint, ftShortint, ftByte, ftFloat, ftCurrency, ftBCD,
    ftFMTBcd, Data.DB.ftExtended];
end;

function dxMemDataToJson(AMemData: TdxCustomMemData): string;
var
  ASB: TStringBuilder;
  AFields: TList;
  ABookmark: TBookmark;
  I: Integer;
  AField: TField;
  AFirstRow, AFirstValue: Boolean;
begin
  CheckActive(AMemData);
  ASB := TStringBuilder.Create;
  AFields := TList.Create;
  try
    GetExportFields(AMemData, AFields);
    ASB.AppendLine('{');
    ASB.AppendLine('  "fields": [');
    for I := 0 to AFields.Count - 1 do
    begin
      AField := TField(AFields[I]);
      ASB.Append('    {"name": "').Append(JsonEscape(AField.FieldName));
      ASB.Append('", "type": "').Append(FieldTypeToName(AField.DataType));
      ASB.Append('", "size": ').Append(AField.Size);
      if AField.Required then
        ASB.Append(', "required": true');
      ASB.Append('}');
      if I < AFields.Count - 1 then
        ASB.Append(',');
      ASB.AppendLine;
    end;
    ASB.AppendLine('  ],');
    ASB.AppendLine('  "rows": [');

    AMemData.DisableControls;
    ABookmark := AMemData.GetBookmark;
    try
      AFirstRow := True;
      AMemData.First;
      while not AMemData.Eof do
      begin
        if not AFirstRow then
          ASB.AppendLine(',');
        AFirstRow := False;
        ASB.Append('    {');
        AFirstValue := True;
        for I := 0 to AFields.Count - 1 do
        begin
          AField := TField(AFields[I]);
          if not AFirstValue then
            ASB.Append(', ');
          AFirstValue := False;
          ASB.Append('"').Append(JsonEscape(AField.FieldName)).Append('": ');
          if AField.IsNull then
            ASB.Append('null')
          else if IsJsonLiteralField(AField) then
            ASB.Append(FieldToText(AField))
          else
            ASB.Append('"').Append(JsonEscape(FieldToText(AField))).Append('"');
        end;
        ASB.Append('}');
        AMemData.Next;
      end;
      if not AFirstRow then
        ASB.AppendLine;
      if AMemData.BookmarkValid(ABookmark) then
        AMemData.GotoBookmark(ABookmark);
    finally
      AMemData.FreeBookmark(ABookmark);
      AMemData.EnableControls;
    end;

    ASB.AppendLine('  ]');
    ASB.AppendLine('}');
    Result := ASB.ToString;
  finally
    AFields.Free;
    ASB.Free;
  end;
end;

type
  // Minimal JSON scanner. Only the shapes produced by dxMemDataToJson are
  // interpreted; anything else is skipped over.
  TdxJsonReader = class
  private
    FText: string;
    FPos: Integer;
    procedure Error;
  public
    constructor Create(const AText: string);
    procedure SkipSpaces;
    function Eof: Boolean;
    function Peek: Char;
    procedure Expect(ACh: Char);
    function TryTake(ACh: Char): Boolean;
    function ReadString: string;
    // reads any value; returns its textual form, AIsNull for JSON null
    function ReadValue(out AIsNull: Boolean): string;
    procedure SkipValue;
  end;

constructor TdxJsonReader.Create(const AText: string);
begin
  inherited Create;
  FText := AText;
  FPos := 1;
end;

procedure TdxJsonReader.Error;
begin
  raise EdxMemDataConvertError.CreateFmt(sdxMalformed, ['JSON', FPos]);
end;

procedure TdxJsonReader.SkipSpaces;
begin
  while (FPos <= Length(FText)) and CharInSet(FText[FPos], [#9, #10, #13, ' ']) do
    Inc(FPos);
end;

function TdxJsonReader.Eof: Boolean;
begin
  SkipSpaces;
  Result := FPos > Length(FText);
end;

function TdxJsonReader.Peek: Char;
begin
  SkipSpaces;
  if FPos > Length(FText) then
    Result := #0
  else
    Result := FText[FPos];
end;

procedure TdxJsonReader.Expect(ACh: Char);
begin
  if Peek <> ACh then
    Error;
  Inc(FPos);
end;

function TdxJsonReader.TryTake(ACh: Char): Boolean;
begin
  Result := Peek = ACh;
  if Result then
    Inc(FPos);
end;

function TdxJsonReader.ReadString: string;
var
  ASB: TStringBuilder;
  ACh: Char;
  ACode: Integer;
begin
  Expect('"');
  ASB := TStringBuilder.Create;
  try
    while True do
    begin
      if FPos > Length(FText) then
        Error;
      ACh := FText[FPos];
      Inc(FPos);
      if ACh = '"' then
        Break;
      if ACh <> '\' then
      begin
        ASB.Append(ACh);
        Continue;
      end;
      if FPos > Length(FText) then
        Error;
      ACh := FText[FPos];
      Inc(FPos);
      case ACh of
        'b': ASB.Append(#8);
        't': ASB.Append(#9);
        'n': ASB.Append(#10);
        'f': ASB.Append(#12);
        'r': ASB.Append(#13);
        'u':
          begin
            ACode := StrToIntDef('$' + Copy(FText, FPos, 4), -1);
            if ACode < 0 then
              Error;
            ASB.Append(Char(ACode));
            Inc(FPos, 4);
          end;
      else
        ASB.Append(ACh); // covers " \ / and anything unexpected
      end;
    end;
    Result := ASB.ToString;
  finally
    ASB.Free;
  end;
end;

function TdxJsonReader.ReadValue(out AIsNull: Boolean): string;
var
  AStart: Integer;
begin
  AIsNull := False;
  Result := '';
  case Peek of
    '"':
      Result := ReadString;
    '{', '[':
      SkipValue; // not expected in a row - ignore it
  else
    AStart := FPos;
    while (FPos <= Length(FText)) and not CharInSet(FText[FPos],
      [',', '}', ']', #9, #10, #13, ' ']) do
      Inc(FPos);
    Result := Copy(FText, AStart, FPos - AStart);
    if SameText(Result, 'null') then
    begin
      AIsNull := True;
      Result := '';
    end;
  end;
end;

procedure TdxJsonReader.SkipValue;
var
  ADepth: Integer;
  ACh: Char;
begin
  ADepth := 0;
  repeat
    if Eof then
      Exit;
    ACh := FText[FPos];
    if ACh = '"' then
    begin
      ReadString;
      Continue;
    end;
    Inc(FPos);
    if CharInSet(ACh, ['{', '[']) then
      Inc(ADepth)
    else if CharInSet(ACh, ['}', ']']) then
      Dec(ADepth);
  until ADepth <= 0;
end;

procedure dxMemDataFromJson(AMemData: TdxCustomMemData; const AText: string;
  ACreateFields: Boolean);
var
  AReader: TdxJsonReader;
  ALoader: TdxMemDataLoader;
  ASchema: TdxFieldSchemas;
  ACount: Integer;
  AKey, AValue: string;
  AIsNull: Boolean;
begin
  AReader := TdxJsonReader.Create(AText);
  ALoader := TdxMemDataLoader.Create(AMemData);
  try
    ACount := 0;
    AReader.Expect('{');
    while not AReader.Eof do
    begin
      if AReader.TryTake('}') then
        Break;
      AKey := AReader.ReadString;
      AReader.Expect(':');

      if SameText(AKey, 'fields') then
      begin
        AReader.Expect('[');
        while not AReader.TryTake(']') do
        begin
          AReader.Expect('{');
          SetLength(ASchema, ACount + 1);
          ASchema[ACount].DataType := ftString;
          while not AReader.TryTake('}') do
          begin
            AKey := AReader.ReadString;
            AReader.Expect(':');
            AValue := AReader.ReadValue(AIsNull);
            if SameText(AKey, 'name') then
              ASchema[ACount].Name := AValue
            else if SameText(AKey, 'type') then
              ASchema[ACount].DataType := NameToFieldType(AValue)
            else if SameText(AKey, 'size') then
              ASchema[ACount].Size := StrToIntDef(AValue, 0)
            else if SameText(AKey, 'required') then
              ASchema[ACount].Required := SameText(AValue, 'true');
            AReader.TryTake(',');
          end;
          Inc(ACount);
          AReader.TryTake(',');
        end;
      end
      else if SameText(AKey, 'rows') then
      begin
        ALoader.Prepare(ASchema, ACreateFields);
        AReader.Expect('[');
        while not AReader.TryTake(']') do
        begin
          AReader.Expect('{');
          ALoader.BeginRow;
          while not AReader.TryTake('}') do
          begin
            AKey := AReader.ReadString;
            AReader.Expect(':');
            AValue := AReader.ReadValue(AIsNull);
            if not AIsNull then
              ALoader.SetValue(AKey, AValue);
            AReader.TryTake(',');
          end;
          ALoader.EndRow;
          AReader.TryTake(',');
        end;
      end
      else
        AReader.SkipValue;

      AReader.TryTake(',');
    end;
  finally
    ALoader.Free;
    AReader.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  Delimited text (RFC 4180)
  --------------------------------------------------------------------------- }

// NULL is written as an empty unquoted cell, an empty string as "" - that is
// what makes the text round trip.
function TextEscape(const AText: string; ADelimiter: Char): string;
var
  I: Integer;
  ANeedsQuotes: Boolean;
begin
  ANeedsQuotes := AText = '';
  for I := 1 to Length(AText) do
    if (AText[I] = ADelimiter) or CharInSet(AText[I], ['"', #10, #13]) then
    begin
      ANeedsQuotes := True;
      Break;
    end;
  if ANeedsQuotes then
    Result := '"' + StringReplace(AText, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := AText;
end;

function dxMemDataToText(AMemData: TdxCustomMemData; ADelimiter: Char): string;
var
  ASB: TStringBuilder;
  AFields: TList;
  ABookmark: TBookmark;
  I: Integer;
  AField: TField;
begin
  CheckActive(AMemData);
  ASB := TStringBuilder.Create;
  AFields := TList.Create;
  try
    GetExportFields(AMemData, AFields);
    for I := 0 to AFields.Count - 1 do
    begin
      if I > 0 then
        ASB.Append(ADelimiter);
      ASB.Append(TextEscape(TField(AFields[I]).FieldName, ADelimiter));
    end;
    ASB.AppendLine;

    AMemData.DisableControls;
    ABookmark := AMemData.GetBookmark;
    try
      AMemData.First;
      while not AMemData.Eof do
      begin
        for I := 0 to AFields.Count - 1 do
        begin
          AField := TField(AFields[I]);
          if I > 0 then
            ASB.Append(ADelimiter);
          if not AField.IsNull then
            ASB.Append(TextEscape(FieldToText(AField), ADelimiter));
        end;
        ASB.AppendLine;
        AMemData.Next;
      end;
      if AMemData.BookmarkValid(ABookmark) then
        AMemData.GotoBookmark(ABookmark);
    finally
      AMemData.FreeBookmark(ABookmark);
      AMemData.EnableControls;
    end;
    Result := ASB.ToString;
  finally
    AFields.Free;
    ASB.Free;
  end;
end;

// Reads one record. AQuoted[I] tells NULL (False, empty) from '' (True).
// Returns False at the end of the text.
function ReadTextRow(const AText: string; var APos: Integer; ADelimiter: Char;
  AValues, AQuoted: TStringList): Boolean;
var
  ASB: TStringBuilder;
  AWasQuoted: Boolean;
begin
  AValues.Clear;
  AQuoted.Clear;
  Result := APos <= Length(AText);
  if not Result then
    Exit;
  ASB := TStringBuilder.Create;
  try
    AWasQuoted := False;
    while APos <= Length(AText) do
    begin
      if AText[APos] = '"' then
      begin
        AWasQuoted := True;
        Inc(APos);
        while APos <= Length(AText) do
        begin
          if AText[APos] = '"' then
          begin
            if (APos < Length(AText)) and (AText[APos + 1] = '"') then
            begin
              ASB.Append('"');
              Inc(APos, 2);
            end
            else
            begin
              Inc(APos);
              Break;
            end;
          end
          else
          begin
            ASB.Append(AText[APos]);
            Inc(APos);
          end;
        end;
      end
      else if AText[APos] = ADelimiter then
      begin
        AValues.Add(ASB.ToString);
        AQuoted.Add(BoolToStr(AWasQuoted));
        ASB.Clear;
        AWasQuoted := False;
        Inc(APos);
      end
      else if CharInSet(AText[APos], [#10, #13]) then
      begin
        if (AText[APos] = #13) and (APos < Length(AText)) and
          (AText[APos + 1] = #10) then
          Inc(APos);
        Inc(APos);
        Break;
      end
      else
      begin
        ASB.Append(AText[APos]);
        Inc(APos);
      end;
    end;
    AValues.Add(ASB.ToString);
    AQuoted.Add(BoolToStr(AWasQuoted));
  finally
    ASB.Free;
  end;
  // a trailing line break must not produce an extra empty record
  if (AValues.Count = 1) and (AValues[0] = '') and (AQuoted[0] = BoolToStr(False)) then
    Result := APos <= Length(AText);
end;

procedure dxMemDataFromText(AMemData: TdxCustomMemData; const AText: string;
  ADelimiter: Char; ACreateFields: Boolean);
var
  ALoader: TdxMemDataLoader;
  ASchema: TdxFieldSchemas;
  AHeader, AValues, AQuoted: TStringList;
  AExisting: TList;
  APos, I: Integer;
begin
  AHeader := TStringList.Create;
  AValues := TStringList.Create;
  AQuoted := TStringList.Create;
  AExisting := TList.Create;
  ALoader := TdxMemDataLoader.Create(AMemData);
  try
    APos := 1;
    if not ReadTextRow(AText, APos, ADelimiter, AHeader, AQuoted) then
      Exit;

    // delimited text carries no types, so fields are only created when the
    // dataset has none - as plain strings
    SetLength(ASchema, 0);
    GetExportFields(AMemData, AExisting);
    if ACreateFields and (AExisting.Count = 0) then
    begin
      SetLength(ASchema, AHeader.Count);
      for I := 0 to AHeader.Count - 1 do
      begin
        ASchema[I].Name := AHeader[I];
        ASchema[I].DataType := ftString;
        ASchema[I].Size := 255;
      end;
    end;
    ALoader.Prepare(ASchema, Length(ASchema) > 0);

    while ReadTextRow(AText, APos, ADelimiter, AValues, AQuoted) do
    begin
      ALoader.BeginRow;
      for I := 0 to AValues.Count - 1 do
        if I < AHeader.Count then
          if (AValues[I] <> '') or (AQuoted[I] = BoolToStr(True)) then
            ALoader.SetValue(AHeader[I], AValues[I]);
      ALoader.EndRow;
    end;
  finally
    ALoader.Free;
    AExisting.Free;
    AQuoted.Free;
    AValues.Free;
    AHeader.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  Generic entry points
  --------------------------------------------------------------------------- }

function dxMemDataToString(AMemData: TdxCustomMemData; AFormat: TdxMemDataFormat;
  ADelimiter: Char): string;
begin
  case AFormat of
    mdfXml: Result := dxMemDataToXml(AMemData);
    mdfJson: Result := dxMemDataToJson(AMemData);
  else
    Result := dxMemDataToText(AMemData, ADelimiter);
  end;
end;

procedure dxMemDataFromString(AMemData: TdxCustomMemData; const AText: string;
  AFormat: TdxMemDataFormat; ACreateFields: Boolean; ADelimiter: Char);
begin
  case AFormat of
    mdfXml: dxMemDataFromXml(AMemData, AText, ACreateFields);
    mdfJson: dxMemDataFromJson(AMemData, AText, ACreateFields);
  else
    dxMemDataFromText(AMemData, AText, ADelimiter, ACreateFields);
  end;
end;

procedure dxMemDataSaveToStream(AMemData: TdxCustomMemData; AStream: TStream;
  AFormat: TdxMemDataFormat; ADelimiter: Char);
var
  ABytes, APreamble: TBytes;
begin
  ABytes := TEncoding.UTF8.GetBytes(dxMemDataToString(AMemData, AFormat, ADelimiter));
  // spreadsheets need the BOM to recognise UTF-8 text; strict JSON parsers
  // choke on it, and XML carries its encoding in the declaration
  if AFormat = mdfText then
  begin
    APreamble := TEncoding.UTF8.GetPreamble;
    AStream.WriteBuffer(APreamble[0], Length(APreamble));
  end;
  if Length(ABytes) > 0 then
    AStream.WriteBuffer(ABytes[0], Length(ABytes));
end;

procedure dxMemDataLoadFromStream(AMemData: TdxCustomMemData; AStream: TStream;
  AFormat: TdxMemDataFormat; ACreateFields: Boolean; ADelimiter: Char);
var
  ABytes: TBytes;
  ASize, AOffset: Integer;
  AEncoding: TEncoding;
begin
  ASize := AStream.Size - AStream.Position;
  SetLength(ABytes, ASize);
  if ASize > 0 then
    AStream.ReadBuffer(ABytes[0], ASize);
  AEncoding := nil;
  AOffset := TEncoding.GetBufferEncoding(ABytes, AEncoding, TEncoding.UTF8);
  dxMemDataFromString(AMemData,
    AEncoding.GetString(ABytes, AOffset, Length(ABytes) - AOffset),
    AFormat, ACreateFields, ADelimiter);
end;

procedure dxMemDataSaveToFile(AMemData: TdxCustomMemData; const AFileName: string;
  AFormat: TdxMemDataFormat; ADelimiter: Char);
var
  AStream: TFileStream;
begin
  AStream := TFileStream.Create(AFileName, fmCreate);
  try
    dxMemDataSaveToStream(AMemData, AStream, AFormat, ADelimiter);
  finally
    AStream.Free;
  end;
end;

procedure dxMemDataLoadFromFile(AMemData: TdxCustomMemData; const AFileName: string;
  AFormat: TdxMemDataFormat; ACreateFields: Boolean; ADelimiter: Char);
var
  AStream: TFileStream;
begin
  AStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    dxMemDataLoadFromStream(AMemData, AStream, AFormat, ACreateFields, ADelimiter);
  finally
    AStream.Free;
  end;
end;

initialization
  FInvSettings := TFormatSettings.Create;
  FInvSettings.DecimalSeparator := '.';
  FInvSettings.ThousandSeparator := #0;

end.
