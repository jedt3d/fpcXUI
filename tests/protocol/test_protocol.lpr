program test_protocol;

{$mode objfpc}{$H+}
{$codepage utf8}

uses
  SysUtils, fpcxui_transport, fpcxui_dispatch;

type
  ETestFailure = class(Exception);

procedure Check(Condition: Boolean; const MessageText: String);
begin
  if not Condition then
    raise ETestFailure.Create(MessageText);
end;

procedure CheckContains(const Actual, Expected, Context: RawByteString);
begin
  Check(Pos(Expected, Actual) > 0,
    String(Context + ': expected fragment ' + Expected + ' in ' + Actual));
end;

function ByteHex(const Value: RawByteString): String;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(Value) do
    Result := Result + IntToHex(Ord(Value[I]), 2);
end;

procedure FeedString(Reader: TLspFrameReader; const Value: RawByteString);
begin
  if Length(Value) > 0 then
    Reader.Feed(@Value[1], Length(Value));
end;

procedure ExpectTransportError(const Frame, Context: RawByteString);
var
  Decoded: RawByteString;
  Raised: Boolean;
  Reader: TLspFrameReader;
begin
  Reader := TLspFrameReader.Create;
  try
    FeedString(Reader, Frame);
    Raised := False;
    try
      Reader.TryReadFrame(Decoded);
    except
      on E: ELspTransportError do
        Raised := True;
    end;
    Check(Raised, String(Context + ': expected transport error'));
  finally
    Reader.Free;
  end;
end;

procedure TestFragmentedUnicodeFrame;
var
  Decoded, Frame, Payload: RawByteString;
  FrameReady: Boolean;
  I: Integer;
  Reader: TLspFrameReader;
begin
  Payload := '{"text":"' + RawByteString(#$F0#$9F#$98#$80) + '"}';
  Frame := BuildLspFrame(Payload);
  Reader := TLspFrameReader.Create;
  try
    FrameReady := False;
    for I := 1 to Length(Frame) do
    begin
      Reader.Feed(@Frame[I], 1);
      if Reader.TryReadFrame(Decoded) then
      begin
        Check(I = Length(Frame), 'fragmented frame completed too early');
        FrameReady := True;
      end;
    end;
    Check(FrameReady, Format(
      'fragmented frame was not emitted: frame_length=%d payload_length=%d frame_hex=%s',
      [Length(Frame), Length(Payload), ByteHex(Frame)]));
    Check(Decoded = Payload, 'UTF-8 payload changed during framing');
    Check(not Reader.HasPendingData, 'fragmented frame left buffered bytes');
  finally
    Reader.Free;
  end;
end;

procedure TestMultipleFrames;
var
  Decoded, Frames: RawByteString;
  Reader: TLspFrameReader;
begin
  Frames := BuildLspFrame('{"n":1}') + BuildLspFrame('{"n":2}');
  Reader := TLspFrameReader.Create;
  try
    FeedString(Reader, Frames);
    Check(Reader.TryReadFrame(Decoded), 'first coalesced frame missing');
    Check(Decoded = '{"n":1}', 'first coalesced frame differs');
    Check(Reader.TryReadFrame(Decoded), 'second coalesced frame missing');
    Check(Decoded = '{"n":2}', 'second coalesced frame differs');
    Check(not Reader.TryReadFrame(Decoded), 'unexpected third coalesced frame');
    Check(not Reader.HasPendingData, 'coalesced frames left buffered bytes');
  finally
    Reader.Free;
  end;
end;

procedure TestEmptyFrame;
var
  Decoded: RawByteString;
  Reader: TLspFrameReader;
begin
  Reader := TLspFrameReader.Create;
  try
    FeedString(Reader, 'Content-Length: 0'#13#10#13#10);
    Check(Reader.TryReadFrame(Decoded), 'zero-length frame missing');
    Check(Decoded = '', 'zero-length frame contained bytes');
  finally
    Reader.Free;
  end;
end;

procedure TestMalformedHeaders;
var
  OversizedHeader: RawByteString;
begin
  ExpectTransportError('Content-Length: nope'#13#10#13#10'{}',
    'non-numeric Content-Length');
  ExpectTransportError('X-Test: yes'#13#10#13#10'{}',
    'missing Content-Length');
  ExpectTransportError('Content-Length: 2'#13#10 +
    'Content-Length: 2'#13#10#13#10'{}', 'duplicate Content-Length');
  ExpectTransportError('Content-Length: 16777217'#13#10#13#10,
    'oversized payload declaration');
  OversizedHeader := StringOfChar('x', LSP_MAX_HEADER_BYTES + 1);
  ExpectTransportError(OversizedHeader, 'oversized unterminated header');
end;

function Dispatch(Server: TLspDispatcher; const Payload: RawByteString;
  out Response: RawByteString): Boolean;
begin
  Result := Server.HandleMessage(Payload, Response);
end;

procedure TestLifecycleAndDispatch;
var
  HasResponse: Boolean;
  Response: RawByteString;
  Server: TLspDispatcher;
begin
  Server := TLspDispatcher.Create;
  try
    HasResponse := Dispatch(Server,
      '{"jsonrpc":"2.0","id":1,"method":"fpc/ping","params":{}}',
      Response);
    Check(HasResponse, 'pre-initialize ping did not produce an error');
    CheckContains(Response, '"code":-32002', 'pre-initialize ping');

    HasResponse := Dispatch(Server, '{not-json', Response);
    Check(HasResponse, 'malformed JSON did not produce parse error');
    CheckContains(Response, '"code":-32700', 'malformed JSON');

    HasResponse := Dispatch(Server,
      '{"jsonrpc":"2.0","id":"init-1","method":"initialize","params":{}}',
      Response);
    Check(HasResponse, 'initialize response missing');
    CheckContains(Response, '"id":"init-1"', 'initialize id');
    CheckContains(Response, '"textDocumentSync"', 'initialize capabilities');
    Check(Server.State = lsAwaitingInitialized,
      'initialize did not advance lifecycle state');

    HasResponse := Dispatch(Server,
      '{"jsonrpc":"2.0","id":2,"method":"initialize","params":{}}',
      Response);
    Check(HasResponse, 'duplicate initialize response missing');
    CheckContains(Response, '"code":-32600', 'duplicate initialize');

    HasResponse := Dispatch(Server,
      '{"jsonrpc":"2.0","method":"initialized","params":{}}', Response);
    Check(not HasResponse, 'initialized notification produced a response');
    Check(Server.State = lsRunning, 'initialized did not start server');

    HasResponse := Dispatch(Server,
      '{"jsonrpc":"2.0","id":3,"method":"fpc/ping","params":{}}',
      Response);
    Check(HasResponse, 'ping response missing');
    CheckContains(Response, '"pong":true', 'ping result');

    HasResponse := Dispatch(Server,
      '{"jsonrpc":"2.0","id":4,"method":"fpc/noSuchMethod"}', Response);
    Check(HasResponse, 'unknown request response missing');
    CheckContains(Response, '"code":-32601', 'unknown request');

    HasResponse := Dispatch(Server,
      '{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":3}}',
      Response);
    Check(not HasResponse, 'cancellation notification produced a response');
    Check(Server.CancelledCount = 1, 'cancellation was not recorded');
    Check(Server.LastCancelledId = '3', 'cancellation id changed');

    HasResponse := Dispatch(Server,
      '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":' +
      '{"textDocument":{"uri":"file:///tmp/a.pas","languageId":"pascal",' +
      '"version":1,"text":"program a;"}}}', Response);
    Check(not HasResponse, 'didOpen produced a response');
    Check(Server.Documents.OpenCount = 1, 'didOpen was not recorded');
    Check(Server.Documents.LastVersion = 1, 'didOpen version changed');
    Check(Server.Documents.LastText = 'program a;', 'didOpen text changed');

    HasResponse := Dispatch(Server,
      '{"jsonrpc":"2.0","method":"textDocument/didChange","params":' +
      '{"textDocument":{"uri":"file:///tmp/a.pas","version":2},' +
      '"contentChanges":[{"text":"program b;"},{"text":"program c;"}]}}',
      Response);
    Check(not HasResponse, 'didChange produced a response');
    Check(Server.Documents.ChangeCount = 1, 'didChange was not recorded');
    Check(Server.Documents.LastVersion = 2, 'didChange version changed');
    Check(Server.Documents.LastContentChangeCount = 2,
      'didChange content-change count changed');

    HasResponse := Dispatch(Server,
      '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{}}',
      Response);
    Check(not HasResponse, 'invalid didOpen produced a response');
    Check(Server.Documents.OpenCount = 1,
      'invalid didOpen reached document sink');

    HasResponse := Dispatch(Server,
      '{"jsonrpc":"2.0","method":"textDocument/didClose","params":' +
      '{"textDocument":{"uri":"file:///tmp/a.pas"}}}', Response);
    Check(not HasResponse, 'didClose produced a response');
    Check(Server.Documents.CloseCount = 1, 'didClose was not recorded');

    HasResponse := Dispatch(Server,
      '{"jsonrpc":"2.0","id":5,"method":"shutdown"}', Response);
    Check(HasResponse, 'shutdown response missing');
    CheckContains(Response, '"result":null', 'shutdown result');
    Check(Server.State = lsShutdown, 'shutdown did not advance lifecycle');

    HasResponse := Dispatch(Server,
      '{"jsonrpc":"2.0","id":6,"method":"fpc/ping","params":{}}',
      Response);
    Check(HasResponse, 'post-shutdown ping response missing');
    CheckContains(Response, '"code":-32600', 'post-shutdown request');

    HasResponse := Dispatch(Server,
      '{"jsonrpc":"2.0","method":"exit"}', Response);
    Check(not HasResponse, 'exit notification produced a response');
    Check(Server.ShouldExit, 'exit did not stop server');
    Check(Server.ExitCode = 0, 'orderly shutdown exit code was not zero');
    Check(Server.State = lsExited, 'exit did not finalize lifecycle');
  finally
    Server.Free;
  end;
end;

procedure TestExitWithoutShutdown;
var
  Response: RawByteString;
  Server: TLspDispatcher;
begin
  Server := TLspDispatcher.Create;
  try
    Check(not Dispatch(Server, '{"jsonrpc":"2.0","method":"exit"}',
      Response), 'early exit produced a response');
    Check(Server.ShouldExit, 'early exit did not stop server');
    Check(Server.ExitCode = 1, 'early exit should have failure exit code');
  finally
    Server.Free;
  end;
end;

procedure StartRunning(Server: TLspDispatcher);
var
  Response: RawByteString;
begin
  Check(Dispatch(Server,
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}',
    Response), 'document integration initialize response missing');
  Check(not Dispatch(Server,
    '{"jsonrpc":"2.0","method":"initialized","params":{}}', Response),
    'document integration initialized produced a response');
  Check(Server.State = lsRunning,
    'document integration server did not reach running state');
end;

procedure TestVersionedDocumentIntegration;
const
  Emoji: RawByteString = #240#159#152#128;
  Uri: RawByteString = 'file:///tmp/unicode.pas';
var
  BeforeFailure, ExpectedText, Response: RawByteString;
  HasResponse: Boolean;
  Server: TLspDispatcher;
begin
  Server := TLspDispatcher.Create;
  try
    StartRunning(Server);

    HasResponse := Dispatch(Server,
      '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":' +
      '{"textDocument":{"uri":"' + Uri + '","languageId":"pascal",' +
      '"version":1,"text":"placeholder"}}}', Response);
    Check(not HasResponse, 'versioned didOpen produced a response');
    Check(Server.Documents.DocumentCount = 1,
      'didOpen did not add an owned text document');
    Check(Server.Documents.FindDocument(Uri) <> nil,
      'didOpen document is not URI-addressable');
    Check(Server.Documents.FindDocument(Uri).Text = 'placeholder',
      'didOpen document text changed');
    Check(Server.Documents.FindDocument(Uri).Version = 1,
      'didOpen document version changed');

    HasResponse := Dispatch(Server,
      '{"jsonrpc":"2.0","method":"textDocument/didChange","params":' +
      '{"textDocument":{"uri":"' + Uri + '","version":2},' +
      '"contentChanges":[{"text":"ab' + Emoji + 'c\r\nxy"}]}}',
      Response);
    Check(not HasResponse, 'full replacement produced a response');
    ExpectedText := 'ab' + Emoji + 'c' + #13#10 + 'xy';
    CheckContains(Server.Documents.FindDocument(Uri).Text, 'ab',
      'full replacement stored text prefix');
    Check(Server.Documents.FindDocument(Uri).Text = ExpectedText,
      'full replacement did not update stored text; expected bytes=' +
      IntToStr(Length(ExpectedText)) + ', actual bytes=' +
      IntToStr(Length(Server.Documents.FindDocument(Uri).Text)) +
      ', expected hex=' + ByteHex(ExpectedText) + ', actual hex=' +
      ByteHex(Server.Documents.FindDocument(Uri).Text));
    Check(Server.Documents.FindDocument(Uri).Version = 2,
      'full replacement did not update stored version');
    Check(RawByteString(Server.Documents.LastText) = ExpectedText,
      'full replacement did not preserve UTF-8 last text');
    Check(Server.Documents.ChangeCount = 1,
      'full replacement did not increment successful change count');

    HasResponse := Dispatch(Server,
      '{"jsonrpc":"2.0","method":"textDocument/didChange","params":' +
      '{"textDocument":{"uri":"' + Uri + '","version":3},' +
      '"contentChanges":[' +
      '{"range":{"start":{"line":0,"character":2},' +
      '"end":{"line":0,"character":4}},"text":"Z"},' +
      '{"range":{"start":{"line":1,"character":0},' +
      '"end":{"line":1,"character":2}},"text":"done"}]}}', Response);
    Check(not HasResponse, 'ranged edit batch produced a response');
    ExpectedText := 'abZc' + #13#10 + 'done';
    Check(Server.Documents.FindDocument(Uri).Text = ExpectedText,
      'UTF-16/CRLF ranged edit batch produced incorrect text');
    Check(Server.Documents.FindDocument(Uri).Version = 3,
      'ranged edit batch did not commit one final version');
    Check(Server.Documents.ChangeCount = 2,
      'ranged edit batch did not increment successful change count once');
    Check(Server.Documents.LastContentChangeCount = 2,
      'ranged edit batch did not preserve content-change count');
    Check(Server.Documents.LastText = ExpectedText,
      'ranged edit batch did not preserve last text property');

    BeforeFailure := Server.Documents.FindDocument(Uri).Text;
    HasResponse := Dispatch(Server,
      '{"jsonrpc":"2.0","method":"textDocument/didChange","params":' +
      '{"textDocument":{"uri":"' + Uri + '","version":4},' +
      '"contentChanges":[' +
      '{"range":{"start":{"line":0,"character":0},' +
      '"end":{"line":0,"character":2}},"text":"XX"},' +
      '{"range":{"start":{"line":99,"character":0},' +
      '"end":{"line":99,"character":0}},"text":"bad"}]}}', Response);
    Check(not HasResponse, 'invalid atomic batch produced a response');
    Check(Server.Documents.FindDocument(Uri).Text = BeforeFailure,
      'invalid later edit did not roll back earlier batch edit');
    Check(Server.Documents.FindDocument(Uri).Version = 3,
      'invalid atomic batch advanced document version');
    Check(Server.Documents.ChangeCount = 2,
      'invalid atomic batch incremented successful change count');

    HasResponse := Dispatch(Server,
      '{"jsonrpc":"2.0","method":"textDocument/didChange","params":' +
      '{"textDocument":{"uri":"' + Uri + '","version":3},' +
      '"contentChanges":[{"text":"stale"}]}}', Response);
    Check(not HasResponse, 'stale edit produced a response');
    Check(Server.Documents.FindDocument(Uri).Text = BeforeFailure,
      'stale edit mutated stored text');
    Check(Server.Documents.FindDocument(Uri).Version = 3,
      'stale edit mutated stored version');
    Check(Server.Documents.ChangeCount = 2,
      'stale edit incremented successful change count');

    HasResponse := Dispatch(Server,
      '{"jsonrpc":"2.0","method":"textDocument/didChange","params":' +
      '{"textDocument":{"uri":"' + Uri + '","version":4},' +
      '"contentChanges":[{"range":{"start":{"line":-1,"character":0},' +
      '"end":{"line":0,"character":0}},"text":"invalid"}]}}',
      Response);
    Check(not HasResponse, 'negative range edit produced a response');
    Check(Server.Documents.FindDocument(Uri).Text = BeforeFailure,
      'negative range edit mutated stored text');
    Check(Server.Documents.FindDocument(Uri).Version = 3,
      'negative range edit mutated stored version');

    HasResponse := Dispatch(Server,
      '{"jsonrpc":"2.0","method":"textDocument/didClose","params":' +
      '{"textDocument":{"uri":"' + Uri + '"}}}', Response);
    Check(not HasResponse, 'versioned didClose produced a response');
    Check(Server.Documents.DocumentCount = 0,
      'didClose did not remove owned text document');
    Check(Server.Documents.FindDocument(Uri) = nil,
      'didClose left the URI-addressable document alive');

    HasResponse := Dispatch(Server,
      '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":' +
      '{"textDocument":{"uri":"file:///tmp/owned.pas",' +
      '"languageId":"pascal","version":1,"text":"owned"}}}', Response);
    Check(not HasResponse, 'owned-document didOpen produced a response');
    Check(Server.Documents.DocumentCount = 1,
      'second URI was not stored independently');
    Check(Server.Documents.FindDocument('file:///tmp/owned.pas') <> nil,
      'second URI is not addressable');
    { The dispatcher destructor must free this deliberately open document. }
  finally
    Server.Free;
  end;
end;

begin
  try
    TestFragmentedUnicodeFrame;
    TestMultipleFrames;
    TestEmptyFrame;
    TestMalformedHeaders;
    TestLifecycleAndDispatch;
    TestVersionedDocumentIntegration;
    TestExitWithoutShutdown;
    WriteLn('PASS: protocol transport and dispatcher tests');
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, 'FAIL: ', E.Message);
      Halt(1);
    end;
  end;
end.
