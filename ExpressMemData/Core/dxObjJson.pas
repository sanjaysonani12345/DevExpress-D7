{*******************************************************************}
{                                                                   }
{       dxObjJson - object to JSON serializer                       }
{                                                                   }
{       Converts any object to JSON: scalar properties become JSON  }
{       values, child objects become nested JSON objects, lists and }
{       arrays become JSON arrays.                                  }
{                                                                   }
{       Self-contained - RTL only. Requires extended RTTI           }
{       (Delphi 2010 and later).                                     }
{                                                                   }
{*******************************************************************}

unit dxObjJson;

interface

uses
  System.Classes, System.SysUtils, System.Types, System.Variants,
  System.StrUtils, System.Rtti, System.TypInfo;

type
  TdxJsonOption = (
    jsoIndent,          // pretty print instead of a single line
    jsoIncludeFields    // also emit the fields, not just the properties
  );
  TdxJsonOptions = set of TdxJsonOption;

const
  dxJsonDefaultOptions = [jsoIndent];

// Serializes AObject. nil yields 'null'.
function dxObjectToJson(AObject: TObject;
  AOptions: TdxJsonOptions = dxJsonDefaultOptions): string;

// Serializes any RTTI value - useful for records, arrays and TValue results.
function dxValueToJson(const AValue: TValue;
  AOptions: TdxJsonOptions = dxJsonDefaultOptions): string;

function dxJsonEscape(const AText: string): string;

implementation

const
  // backstop for very deep graphs; cycles are caught separately
  MaxNestingLevel = 64;

var
  FInvSettings: TFormatSettings;

function dxJsonEscape(const AText: string): string;
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

type
  TdxJsonObjectWriter = class
  private
    FSB: TStringBuilder;
    FContext: TRttiContext;
    FOptions: TdxJsonOptions;
    FStack: TList; // objects on the current path - catches circular references
    FLevel: Integer;
    procedure LineBreak;
    procedure WriteName(const AName: string);
    procedure WriteRaw(const AText: string);
    procedure WriteString(const AText: string);
    procedure WriteFloat(const AValue: TValue);
    procedure WriteSet(const AValue: TValue);
    procedure WriteVariant(const AValue: Variant);
    procedure WriteArray(const AValue: TValue);
    procedure WriteRecord(const AValue: TValue);
    procedure WriteStrings(AStrings: TStrings);
    procedure WriteCollection(ACollection: TCollection);
    procedure WriteMembers(AObject: TObject);
    function TryGetValue(AMember: TRttiMember; AObject: TObject;
      out AValue: TValue): Boolean;
  public
    constructor Create(AOptions: TdxJsonOptions);
    destructor Destroy; override;
    procedure WriteObject(AObject: TObject);
    procedure WriteValue(const AValue: TValue);
    function Text: string;
  end;

constructor TdxJsonObjectWriter.Create(AOptions: TdxJsonOptions);
begin
  inherited Create;
  FOptions := AOptions;
  FSB := TStringBuilder.Create;
  FStack := TList.Create;
  FContext := TRttiContext.Create;
end;

destructor TdxJsonObjectWriter.Destroy;
begin
  FContext.Free;
  FStack.Free;
  FSB.Free;
  inherited Destroy;
end;

function TdxJsonObjectWriter.Text: string;
begin
  Result := FSB.ToString;
end;

procedure TdxJsonObjectWriter.LineBreak;
begin
  if jsoIndent in FOptions then
  begin
    FSB.AppendLine;
    FSB.Append(' ', FLevel * 2);
  end;
end;

procedure TdxJsonObjectWriter.WriteRaw(const AText: string);
begin
  FSB.Append(AText);
end;

procedure TdxJsonObjectWriter.WriteString(const AText: string);
begin
  FSB.Append('"').Append(dxJsonEscape(AText)).Append('"');
end;

procedure TdxJsonObjectWriter.WriteName(const AName: string);
begin
  WriteString(AName);
  FSB.Append(':');
  if jsoIndent in FOptions then
    FSB.Append(' ');
end;

procedure TdxJsonObjectWriter.WriteFloat(const AValue: TValue);
var
  ADateTime: TDateTime;
begin
  if AValue.TypeInfo = System.TypeInfo(TDateTime) then
  begin
    ADateTime := AValue.AsExtended;
    WriteString(FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss"."zzz', ADateTime));
  end
  else if AValue.TypeInfo = System.TypeInfo(TDate) then
    WriteString(FormatDateTime('yyyy"-"mm"-"dd', AValue.AsExtended))
  else if AValue.TypeInfo = System.TypeInfo(TTime) then
    WriteString(FormatDateTime('hh":"nn":"ss"."zzz', AValue.AsExtended))
  else if GetTypeData(AValue.TypeInfo)^.FloatType = ftCurr then
    WriteRaw(CurrToStr(AValue.AsCurrency, FInvSettings))
  else
    WriteRaw(FloatToStr(AValue.AsExtended, FInvSettings));
end;

// A set becomes an array of its element names.
procedure TdxJsonObjectWriter.WriteSet(const AValue: TValue);
var
  AElements: TStringDynArray;
  I: Integer;
begin
  AElements := SplitString(SetToString(AValue.TypeInfo,
    AValue.GetReferenceToRawData, False), ',');
  FSB.Append('[');
  Inc(FLevel);
  for I := 0 to High(AElements) do
  begin
    if Trim(AElements[I]) = '' then
      Continue;
    if I > 0 then
      FSB.Append(',');
    LineBreak;
    WriteString(Trim(AElements[I]));
  end;
  Dec(FLevel);
  if Length(AElements) > 0 then
    LineBreak;
  FSB.Append(']');
end;

procedure TdxJsonObjectWriter.WriteVariant(const AValue: Variant);
begin
  if VarIsNull(AValue) or VarIsEmpty(AValue) then
    WriteRaw('null')
  else
    case VarType(AValue) and varTypeMask of
      varSmallint, varInteger, varShortInt, varByte, varWord, varLongWord,
      varInt64, varUInt64:
        WriteRaw(VarToStr(AValue));
      varSingle, varDouble, varCurrency:
        WriteRaw(FloatToStr(Double(AValue), FInvSettings));
      varBoolean:
        if AValue then
          WriteRaw('true')
        else
          WriteRaw('false');
      varDate:
        WriteString(FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss"."zzz',
          VarToDateTime(AValue)));
    else
      WriteString(VarToStr(AValue));
    end;
end;

procedure TdxJsonObjectWriter.WriteArray(const AValue: TValue);
var
  I, ACount: Integer;
begin
  ACount := AValue.GetArrayLength;
  FSB.Append('[');
  Inc(FLevel);
  for I := 0 to ACount - 1 do
  begin
    if I > 0 then
      FSB.Append(',');
    LineBreak;
    WriteValue(AValue.GetArrayElement(I));
  end;
  Dec(FLevel);
  if ACount > 0 then
    LineBreak;
  FSB.Append(']');
end;

procedure TdxJsonObjectWriter.WriteRecord(const AValue: TValue);
var
  AType: TRttiType;
  AField: TRttiField;
  AFirst: Boolean;
begin
  FSB.Append('{');
  Inc(FLevel);
  AFirst := True;
  AType := FContext.GetType(AValue.TypeInfo);
  if AType <> nil then
    for AField in AType.GetFields do
    begin
      if (AField.FieldType = nil) or (AField.Visibility <> mvPublic) then
        Continue;
      if not AFirst then
        FSB.Append(',');
      AFirst := False;
      LineBreak;
      WriteName(AField.Name);
      WriteValue(AField.GetValue(AValue.GetReferenceToRawData));
    end;
  Dec(FLevel);
  if not AFirst then
    LineBreak;
  FSB.Append('}');
end;

procedure TdxJsonObjectWriter.WriteStrings(AStrings: TStrings);
var
  I: Integer;
begin
  FSB.Append('[');
  Inc(FLevel);
  for I := 0 to AStrings.Count - 1 do
  begin
    if I > 0 then
      FSB.Append(',');
    LineBreak;
    WriteString(AStrings[I]);
  end;
  Dec(FLevel);
  if AStrings.Count > 0 then
    LineBreak;
  FSB.Append(']');
end;

procedure TdxJsonObjectWriter.WriteCollection(ACollection: TCollection);
var
  I: Integer;
begin
  FSB.Append('[');
  Inc(FLevel);
  for I := 0 to ACollection.Count - 1 do
  begin
    if I > 0 then
      FSB.Append(',');
    LineBreak;
    WriteObject(ACollection.Items[I]);
  end;
  Dec(FLevel);
  if ACollection.Count > 0 then
    LineBreak;
  FSB.Append(']');
end;

// A property getter may raise when the object is not fully configured, which
// must not abort the whole document.
function TdxJsonObjectWriter.TryGetValue(AMember: TRttiMember; AObject: TObject;
  out AValue: TValue): Boolean;
begin
  Result := True;
  try
    if AMember is TRttiProperty then
      AValue := TRttiProperty(AMember).GetValue(AObject)
    else
      AValue := TRttiField(AMember).GetValue(AObject);
  except
    on E: Exception do
    begin
      AValue := TValue.Empty;
      Result := False;
    end;
  end;
end;

procedure TdxJsonObjectWriter.WriteMembers(AObject: TObject);
var
  AType: TRttiType;
  AProp: TRttiProperty;
  AField: TRttiField;
  AValue: TValue;
  AFirst: Boolean;

  procedure WriteMember(const AName: string; const AValue: TValue; AReadOk: Boolean);
  begin
    if not AFirst then
      FSB.Append(',');
    AFirst := False;
    LineBreak;
    WriteName(AName);
    if AReadOk then
      WriteValue(AValue)
    else
      WriteRaw('null');
  end;

begin
  FSB.Append('{');
  Inc(FLevel);
  AFirst := True;
  AType := FContext.GetType(AObject.ClassInfo);
  if AType <> nil then
  begin
    for AProp in AType.GetProperties do
    begin
      if not AProp.IsReadable or (AProp.PropertyType = nil) or
        not (AProp.Visibility in [mvPublic, mvPublished]) then
        Continue;
      WriteMember(AProp.Name, AValue, TryGetValue(AProp, AObject, AValue));
    end;
    if jsoIncludeFields in FOptions then
      for AField in AType.GetFields do
      begin
        if AField.FieldType = nil then
          Continue;
        WriteMember(AField.Name, AValue, TryGetValue(AField, AObject, AValue));
      end;
  end;
  Dec(FLevel);
  if not AFirst then
    LineBreak;
  FSB.Append('}');
end;

procedure TdxJsonObjectWriter.WriteObject(AObject: TObject);
begin
  if AObject = nil then
  begin
    WriteRaw('null');
    Exit;
  end;
  if FStack.IndexOf(AObject) >= 0 then
  begin
    WriteRaw('{"$circular": "' + dxJsonEscape(AObject.ClassName) + '"}');
    Exit;
  end;
  if FStack.Count >= MaxNestingLevel then
  begin
    WriteRaw('{"$maxDepth": "' + dxJsonEscape(AObject.ClassName) + '"}');
    Exit;
  end;

  FStack.Add(AObject);
  try
    if AObject is TStrings then
      WriteStrings(TStrings(AObject))
    else if AObject is TCollection then
      WriteCollection(TCollection(AObject))
    else
      WriteMembers(AObject);
  finally
    FStack.Delete(FStack.Count - 1);
  end;
end;

procedure TdxJsonObjectWriter.WriteValue(const AValue: TValue);
begin
  if AValue.IsEmpty then
  begin
    WriteRaw('null');
    Exit;
  end;
  case AValue.Kind of
    tkInteger:
      WriteRaw(IntToStr(AValue.AsOrdinal));
    tkInt64:
      if AValue.TypeInfo = System.TypeInfo(UInt64) then
        WriteRaw(UIntToStr(AValue.AsUInt64))
      else
        WriteRaw(IntToStr(AValue.AsInt64));
    tkEnumeration:
      if AValue.TypeInfo = System.TypeInfo(Boolean) then
        if AValue.AsBoolean then
          WriteRaw('true')
        else
          WriteRaw('false')
      else
        WriteString(GetEnumName(AValue.TypeInfo, AValue.AsOrdinal));
    tkFloat:
      WriteFloat(AValue);
    tkSet:
      WriteSet(AValue);
    tkChar, tkWChar, tkString, tkLString, tkWString, tkUString:
      WriteString(AValue.AsString);
    tkClass:
      WriteObject(AValue.AsObject);
    tkVariant:
      WriteVariant(AValue.AsVariant);
    tkArray, tkDynArray:
      WriteArray(AValue);
    tkRecord{$IF Declared(tkMRecord)}, tkMRecord{$IFEND}:
      WriteRecord(AValue);
  else
    // interfaces, methods, pointers, class references
    WriteRaw('null');
  end;
end;

function dxObjectToJson(AObject: TObject; AOptions: TdxJsonOptions): string;
var
  AWriter: TdxJsonObjectWriter;
begin
  AWriter := TdxJsonObjectWriter.Create(AOptions);
  try
    AWriter.WriteObject(AObject);
    Result := AWriter.Text;
  finally
    AWriter.Free;
  end;
end;

function dxValueToJson(const AValue: TValue; AOptions: TdxJsonOptions): string;
var
  AWriter: TdxJsonObjectWriter;
begin
  AWriter := TdxJsonObjectWriter.Create(AOptions);
  try
    AWriter.WriteValue(AValue);
    Result := AWriter.Text;
  finally
    AWriter.Free;
  end;
end;

initialization
  FInvSettings := TFormatSettings.Create;
  FInvSettings.DecimalSeparator := '.';
  FInvSettings.ThousandSeparator := #0;

end.
