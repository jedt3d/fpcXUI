program fpcxui_ls;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, fpcxui_transport, fpcxui_dispatch;

const
  READ_BUFFER_SIZE = 8192;

function RunServer: Integer;
var
  BytesRead: LongInt;
  Dispatcher: TLspDispatcher;
  InputStream, OutputStream: THandleStream;
  Payload, Response: RawByteString;
  ReadBuffer: array[0..READ_BUFFER_SIZE - 1] of Byte;
  Reader: TLspFrameReader;
begin
  Dispatcher := TLspDispatcher.Create;
  Reader := TLspFrameReader.Create;
  InputStream := THandleStream.Create(TTextRec(Input).Handle);
  OutputStream := THandleStream.Create(TTextRec(Output).Handle);
  try
    repeat
      BytesRead := InputStream.Read(ReadBuffer, SizeOf(ReadBuffer));
      if BytesRead < 0 then
        raise ELspTransportError.Create('Failed to read standard input');
      if BytesRead = 0 then
        Break;

      Reader.Feed(ReadBuffer, BytesRead);
      while Reader.TryReadFrame(Payload) do
      begin
        if Dispatcher.HandleMessage(Payload, Response) then
          WriteLspFrame(OutputStream, Response);
        if Dispatcher.ShouldExit then
          Break;
      end;
    until Dispatcher.ShouldExit;

    if not Dispatcher.ShouldExit and Reader.HasPendingData then
      raise ELspTransportError.Create('Unexpected EOF inside LSP frame');
    Result := Dispatcher.ExitCode;
  finally
    OutputStream.Free;
    InputStream.Free;
    Reader.Free;
    Dispatcher.Free;
  end;
end;

var
  ProcessExitCode: Integer;
begin
  try
    ProcessExitCode := RunServer;
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, '[fpcxui-ls] fatal: ', E.Message);
      ProcessExitCode := 1;
    end;
  end;
  Halt(ProcessExitCode);
end.
