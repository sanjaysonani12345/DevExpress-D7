

unit dxObjJsonMarshal;

interface

uses
  System.Classes, System.SysUtils, System.JSON;


function dxObjectToJsonMarshal(AObject: TObject; APretty: Boolean = True): string;


function dxObjectToJsonRest(AObject: TObject; APretty: Boolean = True): string;

implementation

uses
  System.Rtti, System.TypInfo, System.Generics.Collections,
  Data.DBXJSONReflect, REST.Json;


procedure CollectContainerClasses(AObject: TObject; AVisited: TList<TObject>;
  AClasses, AItemClasses: TList<TClass>);
var
  AContext: TRttiContext;
  AType: TRttiType;
  AField: TRttiField;
  AValue: TValue;
  AChild: TObject;
begin
  if (AObject = nil) or (AVisited.IndexOf(AObject) >= 0) or
    (AVisited.Count > 512) then
    Exit;
  AVisited.Add(AObject);

  if (AObject is TStrings) or (AObject is TCollection) then
  begin
    if AClasses.IndexOf(AObject.ClassType) < 0 then
      AClasses.Add(AObject.ClassType);
    if AObject is TCollection then
    begin
   
      if AItemClasses.IndexOf(TCollection(AObject).ItemClass) < 0 then
        AItemClasses.Add(TCollection(AObject).ItemClass);
    end;
    Exit;
  end;

  AContext := TRttiContext.Create;
  try
    AType := AContext.GetType(AObject.ClassInfo);
    if AType = nil then
      Exit;
    for AField in AType.GetFields do
    begin
      if (AField.FieldType = nil) or (AField.FieldType.TypeKind <> tkClass) then
        Continue;
      try
        AValue := AField.GetValue(AObject);
      except
        Continue;
      end;
      AChild := AValue.AsObject;
      if AChild <> nil then
        CollectContainerClasses(AChild, AVisited, AClasses, AItemClasses);
    end;
  finally
    AContext.Free;
  end;
end;

procedure RegisterContainerConverters(AMarshal: TJSONMarshal; AObject: TObject);
var
  AVisited: TList<TObject>;
  AClasses, AItemClasses: TList<TClass>;
  AClass: TClass;
  AStringsConverter: TTypeStringsConverter;
  AObjectsConverter: TTypeObjectsConverter;
begin
  AStringsConverter :=
    function(Data: TObject): TListOfStrings
    var
      I: Integer;
    begin
      SetLength(Result, TStrings(Data).Count);
      for I := 0 to TStrings(Data).Count - 1 do
        Result[I] := TStrings(Data)[I];
    end;

  AObjectsConverter :=
    function(Data: TObject): TListOfObjects
    var
      I: Integer;
    begin
      SetLength(Result, TCollection(Data).Count);
      for I := 0 to TCollection(Data).Count - 1 do
        Result[I] := TCollection(Data).Items[I];
    end;

  AVisited := TList<TObject>.Create;
  AClasses := TList<TClass>.Create;
  AItemClasses := TList<TClass>.Create;
  try
    CollectContainerClasses(AObject, AVisited, AClasses, AItemClasses);
    for AClass in AClasses do
      if AClass.InheritsFrom(TStrings) then
        AMarshal.RegisterConverter(AClass, AStringsConverter)
      else
        AMarshal.RegisterConverter(AClass, AObjectsConverter);

    for AClass in AItemClasses do
      AMarshal.RegisterJSONMarshalled(AClass, 'FCollection', False);
  finally
    AItemClasses.Free;
    AClasses.Free;
    AVisited.Free;
  end;
end;

function dxObjectToJsonMarshal(AObject: TObject; APretty: Boolean): string;
var
  AMarshal: TJSONMarshal;
  AValue: TJSONValue;
begin
  if AObject = nil then
  begin
    Result := 'null';
    Exit;
  end;
  AMarshal := TJSONMarshal.Create(TJSONConverter.Create);
  try
    RegisterContainerConverters(AMarshal, AObject);
    AValue := AMarshal.Marshal(AObject);
    try
      if APretty then
        Result := TJson.Format(AValue)
      else
        Result := AValue.ToJSON;
    finally
      AValue.Free;
    end;
  finally
    AMarshal.Free;
  end;
end;

function dxObjectToJsonRest(AObject: TObject; APretty: Boolean): string;
var
  AValue: TJSONObject;
begin
  if AObject = nil then
  begin
    Result := 'null';
    Exit;
  end;
  if not APretty then
  begin
    Result := TJson.ObjectToJsonString(AObject);
    Exit;
  end;
  AValue := TJson.ObjectToJsonObject(AObject);
  try
    Result := TJson.Format(AValue);
  finally
    AValue.Free;
  end;
end;

end.
