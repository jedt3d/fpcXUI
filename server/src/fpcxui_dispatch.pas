unit fpcxui_dispatch;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, jsonparser, Fpcx_Text;

type
  TLspLifecycleState = (
    lsPreInitialize,
    lsAwaitingInitialized,
    lsRunning,
    lsShutdown,
    lsExited
  );

  { URI-keyed owner for versioned UTF-8 text documents. }
  TDocumentStore = class
  private
    FItems: TStringList;
    FOpenCount: Integer;
    FChangeCount: Integer;
    FCloseCount: Integer;
    FLastUri: UTF8String;
    FLastVersion: Int64;
    FLastText: UTF8String;
    FLastContentChangeCount: Integer;
    function FindIndex(const Uri: RawByteString): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure DidOpen(const Uri: RawByteString; Version: Int64;
      const Text: RawByteString);
    procedure DidChange(const Uri: RawByteString; Version: Int64;
      const Changes: array of TTextChange);
    procedure DidClose(const Uri: RawByteString);
    function FindDocument(const Uri: RawByteString): TFpcTextDocument;
    function DocumentCount: Integer;
    property OpenCount: Integer read FOpenCount;
    property ChangeCount: Integer read FChangeCount;
    property CloseCount: Integer read FCloseCount;
    property LastUri: UTF8String read FLastUri;
    property LastVersion: Int64 read FLastVersion;
    property LastText: UTF8String read FLastText;
    property LastContentChangeCount: Integer read FLastContentChangeCount;
  end;

  TLspDispatcher = class
  private
    FCancelledCount: Integer;
    FDocuments: TDocumentStore;
    FExitCode: Integer;
    FLastCancelledId: RawByteString;
    FShouldExit: Boolean;
    FState: TLspLifecycleState;
    function ErrorResponse(Id: TJSONData; Code: Integer;
      const MessageText: UTF8String): RawByteString;
    function ResultResponse(Id: TJSONData;
      const ResultJson: RawByteString): RawByteString;
    function HandleRequest(const AMethod: UTF8String; Id,
      Params: TJSONData; out Response: RawByteString): Boolean;
    procedure HandleNotification(const AMethod: UTF8String;
      Params: TJSONData);
    procedure HandleDidOpen(Params: TJSONData);
    procedure HandleDidChange(Params: TJSONData);
    procedure HandleDidClose(Params: TJSONData);
    procedure HandleCancellation(Params: TJSONData);
    procedure Log(const MessageText: UTF8String);
  public
    constructor Create;
    destructor Destroy; override;
    function HandleMessage(const Payload: RawByteString;
      out Response: RawByteString): Boolean;
    property CancelledCount: Integer read FCancelledCount;
    property Documents: TDocumentStore read FDocuments;
    property ExitCode: Integer read FExitCode;
    property LastCancelledId: RawByteString read FLastCancelledId;
    property ShouldExit: Boolean read FShouldExit;
    property State: TLspLifecycleState read FState;
  end;

implementation

const
  JSONRPC_PARSE_ERROR = -32700;
  JSONRPC_INVALID_REQUEST = -32600;
  JSONRPC_METHOD_NOT_FOUND = -32601;
  JSONRPC_INVALID_PARAMS = -32602;
  LSP_SERVER_NOT_INITIALIZED = -32002;

type
  ELspInvalidParams = class(Exception);

function JsonQuote(const Value: UTF8String): RawByteString;
var
  JsonString: TJSONString;
begin
  JsonString := TJSONString.Create(Value);
  try
    Result := JsonString.AsJSON;
  finally
    JsonString.Free;
  end;
end;

function JsonId(Id: TJSONData): RawByteString;
begin
  if Id = nil then
    Result := 'null'
  else
    Result := Id.AsJSON;
end;

function RequireObject(Value: TJSONData; const Context: UTF8String): TJSONObject;
begin
  if (Value = nil) or (Value.JSONType <> jtObject) then
    raise ELspInvalidParams.Create(Context + ' must be an object');
  Result := TJSONObject(Value);
end;

function RequireField(Obj: TJSONObject; const Name: UTF8String): TJSONData;
begin
  Result := Obj.Find(Name);
  if Result = nil then
    raise ELspInvalidParams.Create('Missing field: ' + Name);
end;

function RequireObjectField(Obj: TJSONObject;
  const Name: UTF8String): TJSONObject;
begin
  Result := RequireObject(RequireField(Obj, Name), Name);
end;

function RequireStringField(Obj: TJSONObject;
  const Name: UTF8String): RawByteString;
var
  Value: TJSONData;
begin
  Value := RequireField(Obj, Name);
  if Value.JSONType <> jtString then
    raise ELspInvalidParams.Create(Name + ' must be a string');
  Result := RawByteString(Value.AsString);
  SetCodePage(Result, CP_NONE, False);
end;

function RequireIntegerField(Obj: TJSONObject;
  const Name: UTF8String): Int64;
var
  Value: TJSONData;
begin
  Value := RequireField(Obj, Name);
  if (Value.JSONType <> jtNumber) or
     (TJSONNumber(Value).NumberType <> ntInteger) then
    raise ELspInvalidParams.Create(Name + ' must be an integer');
  try
    Result := Value.AsInt64;
  except
    on E: Exception do
      raise ELspInvalidParams.Create(Name + ' must be an integer');
  end;
end;

function RequireNonNegativeSizeIntField(Obj: TJSONObject;
  const Name: UTF8String): SizeInt;
var
  Value: Int64;
begin
  Value := RequireIntegerField(Obj, Name);
  if Value < 0 then
    raise ELspInvalidParams.Create(Name + ' must be nonnegative');
  if QWord(Value) > QWord(High(SizeInt)) then
    raise ELspInvalidParams.Create(Name + ' is outside the supported range');
  Result := SizeInt(Value);
end;

function RequirePositionField(Obj: TJSONObject;
  const Name: UTF8String): TTextPosition;
var
  PositionObject: TJSONObject;
begin
  PositionObject := RequireObjectField(Obj, Name);
  Result := TextPosition(
    RequireNonNegativeSizeIntField(PositionObject, 'line'),
    RequireNonNegativeSizeIntField(PositionObject, 'character'));
end;

function RequireTextRange(Value: TJSONData): TTextRange;
var
  RangeObject: TJSONObject;
begin
  RangeObject := RequireObject(Value, 'range');
  Result.StartPos := RequirePositionField(RangeObject, 'start');
  Result.EndPos := RequirePositionField(RangeObject, 'end');
end;

constructor TDocumentStore.Create;
begin
  inherited Create;
  FItems := TStringList.Create;
  FItems.Sorted := True;
  FItems.Duplicates := dupError;
  FItems.CaseSensitive := True;
end;

destructor TDocumentStore.Destroy;
var
  I: Integer;
begin
  for I := 0 to FItems.Count - 1 do
    FItems.Objects[I].Free;
  FItems.Free;
  inherited Destroy;
end;

function TDocumentStore.FindIndex(const Uri: RawByteString): Integer;
begin
  Result := FItems.IndexOf(String(Uri));
end;

function TDocumentStore.FindDocument(
  const Uri: RawByteString): TFpcTextDocument;
var
  Index: Integer;
begin
  Index := FindIndex(Uri);
  if Index < 0 then
    Result := nil
  else
    Result := TFpcTextDocument(FItems.Objects[Index]);
end;

function TDocumentStore.DocumentCount: Integer;
begin
  Result := FItems.Count;
end;

procedure TDocumentStore.DidOpen(const Uri: RawByteString; Version: Int64;
  const Text: RawByteString);
var
  Index: Integer;
  NewDocument, OldDocument: TFpcTextDocument;
begin
  NewDocument := TFpcTextDocument.Create(Uri, Version, Text);
  Index := FindIndex(Uri);
  if Index >= 0 then
  begin
    OldDocument := TFpcTextDocument(FItems.Objects[Index]);
    FItems.Objects[Index] := NewDocument;
    OldDocument.Free;
  end
  else
  begin
    try
      FItems.AddObject(String(Uri), NewDocument);
    except
      NewDocument.Free;
      raise;
    end;
  end;

  Inc(FOpenCount);
  FLastUri := Uri;
  FLastVersion := Version;
  FLastText := Text;
  FLastContentChangeCount := 0;
end;

procedure TDocumentStore.DidChange(const Uri: RawByteString; Version: Int64;
  const Changes: array of TTextChange);
var
  Document: TFpcTextDocument;
  ErrorText: RawByteString;
begin
  Document := FindDocument(Uri);
  if Document = nil then
    raise ETextDocumentError.Create('Document is not open: ' + Uri);
  if not Document.ApplyChanges(Version, Changes, ErrorText) then
    raise ETextDocumentError.Create(ErrorText);

  Inc(FChangeCount);
  FLastUri := Uri;
  FLastVersion := Version;
  FLastText := Document.Text;
  FLastContentChangeCount := Length(Changes);
end;

procedure TDocumentStore.DidClose(const Uri: RawByteString);
var
  Document: TFpcTextDocument;
  Index: Integer;
begin
  Index := FindIndex(Uri);
  if Index < 0 then
    raise ETextDocumentError.Create('Document is not open: ' + Uri);
  Document := TFpcTextDocument(FItems.Objects[Index]);
  FItems.Delete(Index);
  Document.Free;

  Inc(FCloseCount);
  FLastUri := Uri;
end;

constructor TLspDispatcher.Create;
begin
  inherited Create;
  FDocuments := TDocumentStore.Create;
  FState := lsPreInitialize;
  FExitCode := 1;
end;

destructor TLspDispatcher.Destroy;
begin
  FDocuments.Free;
  inherited Destroy;
end;

procedure TLspDispatcher.Log(const MessageText: UTF8String);
begin
  WriteLn(ErrOutput, '[fpcxui-ls] ', MessageText);
end;

function TLspDispatcher.ErrorResponse(Id: TJSONData; Code: Integer;
  const MessageText: UTF8String): RawByteString;
begin
  Result := '{"jsonrpc":"2.0","id":' + JsonId(Id) +
    ',"error":{"code":' + RawByteString(IntToStr(Code)) +
    ',"message":' + JsonQuote(MessageText) + '}}';
end;

function TLspDispatcher.ResultResponse(Id: TJSONData;
  const ResultJson: RawByteString): RawByteString;
begin
  Result := '{"jsonrpc":"2.0","id":' + JsonId(Id) +
    ',"result":' + ResultJson + '}';
end;

procedure TLspDispatcher.HandleDidOpen(Params: TJSONData);
var
  ParamsObject, TextDocument: TJSONObject;
begin
  ParamsObject := RequireObject(Params, 'params');
  TextDocument := RequireObjectField(ParamsObject, 'textDocument');
  FDocuments.DidOpen(
    RequireStringField(TextDocument, 'uri'),
    RequireIntegerField(TextDocument, 'version'),
    RequireStringField(TextDocument, 'text'));
end;

procedure TLspDispatcher.HandleDidChange(Params: TJSONData);
type
  TTextChangeArray = array of TTextChange;
var
  Change, RangeData: TJSONData;
  ChangeObject: TJSONObject;
  Changes: TJSONArray;
  ParsedChanges: TTextChangeArray;
  I: Integer;
  ParamsObject, TextDocument: TJSONObject;
begin
  ParamsObject := RequireObject(Params, 'params');
  TextDocument := RequireObjectField(ParamsObject, 'textDocument');
  Change := RequireField(ParamsObject, 'contentChanges');
  if Change.JSONType <> jtArray then
    raise ELspInvalidParams.Create('contentChanges must be an array');
  Changes := TJSONArray(Change);
  SetLength(ParsedChanges, Changes.Count);

  for I := 0 to Changes.Count - 1 do
  begin
    ChangeObject := RequireObject(Changes.Items[I], 'content change');
    RangeData := ChangeObject.Find('range');
    if RangeData = nil then
      ParsedChanges[I] := FullTextChange(
        RequireStringField(ChangeObject, 'text'))
    else
      ParsedChanges[I] := IncrementalTextChange(
        RequireTextRange(RangeData),
        RequireStringField(ChangeObject, 'text'));
  end;

  FDocuments.DidChange(
    RequireStringField(TextDocument, 'uri'),
    RequireIntegerField(TextDocument, 'version'),
    ParsedChanges);
end;

procedure TLspDispatcher.HandleDidClose(Params: TJSONData);
var
  ParamsObject, TextDocument: TJSONObject;
begin
  ParamsObject := RequireObject(Params, 'params');
  TextDocument := RequireObjectField(ParamsObject, 'textDocument');
  FDocuments.DidClose(RequireStringField(TextDocument, 'uri'));
end;

procedure TLspDispatcher.HandleCancellation(Params: TJSONData);
var
  Id: TJSONData;
  ParamsObject: TJSONObject;
begin
  ParamsObject := RequireObject(Params, 'params');
  Id := RequireField(ParamsObject, 'id');
  if not (Id.JSONType in [jtString, jtNumber]) then
    raise ELspInvalidParams.Create('Cancellation id must be a string or number');
  Inc(FCancelledCount);
  FLastCancelledId := Id.AsJSON;
end;

function TLspDispatcher.HandleRequest(const AMethod: UTF8String; Id,
  Params: TJSONData; out Response: RawByteString): Boolean;
begin
  Result := True;

  if AMethod = 'initialize' then
  begin
    if FState <> lsPreInitialize then
      Response := ErrorResponse(Id, JSONRPC_INVALID_REQUEST,
        'initialize may only be sent once')
    else
    begin
      if (Params <> nil) and (Params.JSONType <> jtObject) then
      begin
        Response := ErrorResponse(Id, JSONRPC_INVALID_PARAMS,
          'initialize params must be an object');
        Exit;
      end;
      FState := lsAwaitingInitialized;
      Response := ResultResponse(Id,
        '{"capabilities":{"textDocumentSync":{"openClose":true,"change":2}},' +
        '"serverInfo":{"name":"fpcxui-ls","version":"0.0.0-phase0"}}');
    end;
    Exit;
  end;

  if FState = lsPreInitialize then
  begin
    Response := ErrorResponse(Id, LSP_SERVER_NOT_INITIALIZED,
      'Server not initialized');
    Exit;
  end;
  if FState = lsShutdown then
  begin
    Response := ErrorResponse(Id, JSONRPC_INVALID_REQUEST,
      'Server has shut down');
    Exit;
  end;
  if FState <> lsRunning then
  begin
    Response := ErrorResponse(Id, JSONRPC_INVALID_REQUEST,
      'Server is not ready for requests');
    Exit;
  end;

  if AMethod = 'shutdown' then
  begin
    if (Params <> nil) and (Params.JSONType <> jtNull) then
    begin
      Response := ErrorResponse(Id, JSONRPC_INVALID_PARAMS,
        'shutdown does not accept params');
      Exit;
    end;
    FState := lsShutdown;
    Response := ResultResponse(Id, 'null');
  end
  else if AMethod = 'fpc/ping' then
  begin
    if (Params <> nil) and not (Params.JSONType in [jtObject, jtArray, jtNull]) then
    begin
      Response := ErrorResponse(Id, JSONRPC_INVALID_PARAMS,
        'fpc/ping params must be structured JSON');
      Exit;
    end;
    Response := ResultResponse(Id,
      '{"pong":true,"server":"fpcxui-ls","phase":0}');
  end
  else
    Response := ErrorResponse(Id, JSONRPC_METHOD_NOT_FOUND,
      'Method not found: ' + AMethod);
end;

procedure TLspDispatcher.HandleNotification(const AMethod: UTF8String;
  Params: TJSONData);
begin
  try
    if AMethod = 'initialized' then
    begin
      if FState = lsAwaitingInitialized then
        FState := lsRunning
      else
        Log('Ignoring initialized notification in invalid lifecycle state');
    end
    else if AMethod = 'exit' then
    begin
      if FState = lsShutdown then
        FExitCode := 0
      else
        FExitCode := 1;
      FState := lsExited;
      FShouldExit := True;
    end
    else if AMethod = '$/cancelRequest' then
      HandleCancellation(Params)
    else if FState <> lsRunning then
      Log('Ignoring notification before server is running: ' + AMethod)
    else if AMethod = 'textDocument/didOpen' then
      HandleDidOpen(Params)
    else if AMethod = 'textDocument/didChange' then
      HandleDidChange(Params)
    else if AMethod = 'textDocument/didClose' then
      HandleDidClose(Params);
    { Unknown notifications are intentionally ignored per JSON-RPC 2.0. }
  except
    on E: ELspInvalidParams do
      Log('Invalid ' + AMethod + ' notification: ' + E.Message);
    on E: ETextDocumentError do
      Log('Rejected ' + AMethod + ' notification: ' + E.Message);
  end;
end;

function TLspDispatcher.HandleMessage(const Payload: RawByteString;
  out Response: RawByteString): Boolean;
var
  Id, MethodData, Params, VersionData: TJSONData;
  IsRequest: Boolean;
  JsonPayload: RawByteString;
  RequestMethod: UTF8String;
  RequestObject: TJSONObject;
  Root: TJSONData;
begin
  Response := '';
  Result := False;
  Root := nil;
  try
    try
      JsonPayload := Payload;
      SetCodePage(JsonPayload, CP_UTF8, False);
      { The legacy AUseUTF8=True overload converts through the system code
        page. False preserves the parser's native UTF-8 strings. }
      Root := GetJSON(JsonPayload, False);
    except
      on E: Exception do
      begin
        Response := ErrorResponse(nil, JSONRPC_PARSE_ERROR, 'Parse error');
        Log('Rejected malformed JSON: ' + E.Message);
        Exit(True);
      end;
    end;

    if Root.JSONType <> jtObject then
    begin
      Response := ErrorResponse(nil, JSONRPC_INVALID_REQUEST,
        'Request must be a JSON object');
      Exit(True);
    end;

    RequestObject := TJSONObject(Root);
    Id := RequestObject.Find('id');
    IsRequest := Id <> nil;
    if IsRequest and not (Id.JSONType in [jtNull, jtString, jtNumber]) then
    begin
      Response := ErrorResponse(nil, JSONRPC_INVALID_REQUEST,
        'Invalid request id');
      Exit(True);
    end;

    VersionData := RequestObject.Find('jsonrpc');
    MethodData := RequestObject.Find('method');
    if (VersionData = nil) or (VersionData.JSONType <> jtString) or
       (VersionData.AsString <> '2.0') or (MethodData = nil) or
       (MethodData.JSONType <> jtString) then
    begin
      Response := ErrorResponse(Id, JSONRPC_INVALID_REQUEST,
        'Invalid JSON-RPC request');
      Exit(True);
    end;

    RequestMethod := MethodData.AsString;
    Params := RequestObject.Find('params');
    if (Params <> nil) and not (Params.JSONType in [jtObject, jtArray, jtNull]) then
    begin
      if IsRequest then
      begin
        Response := ErrorResponse(Id, JSONRPC_INVALID_PARAMS,
          'params must be an object or array');
        Exit(True);
      end;
      Log('Ignoring notification with invalid params: ' + RequestMethod);
      Exit(False);
    end;

    if IsRequest then
    begin
      if (RequestMethod = 'initialized') or (RequestMethod = 'exit') or
         (RequestMethod = '$/cancelRequest') or
         (RequestMethod = 'textDocument/didOpen') or
         (RequestMethod = 'textDocument/didChange') or
         (RequestMethod = 'textDocument/didClose') then
      begin
        Response := ErrorResponse(Id, JSONRPC_INVALID_REQUEST,
          RequestMethod + ' must be a notification');
        Exit(True);
      end;
      Result := HandleRequest(RequestMethod, Id, Params, Response);
    end
    else
    begin
      if (RequestMethod = 'initialize') or (RequestMethod = 'shutdown') or
         (RequestMethod = 'fpc/ping') then
      begin
        Log('Ignoring request-only method sent as notification: ' + RequestMethod);
        Exit(False);
      end;
      HandleNotification(RequestMethod, Params);
      Result := False;
    end;
  finally
    Root.Free;
  end;
end;

end.
