unit fpcxui_transport;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  LSP_MAX_HEADER_BYTES = 8192;
  LSP_MAX_PAYLOAD_BYTES = 16 * 1024 * 1024;

type
  ELspTransportError = class(Exception);

  { Incremental byte reader for the LSP Content-Length wire format. }
  TLspFrameReader = class
  private
    FBuffer: TBytes;
    function FindHeaderEnd: SizeInt;
    function ParseContentLength(const Header: RawByteString): SizeInt;
  public
    procedure Feed(const Data; Count: SizeInt);
    function TryReadFrame(out Payload: RawByteString): Boolean;
    function HasPendingData: Boolean;
  end;

function BuildLspFrame(const Payload: RawByteString): RawByteString;
procedure WriteLspFrame(Stream: TStream; const Payload: RawByteString);

implementation

function IsAsciiDigit(Value: AnsiChar): Boolean;
begin
  Result := (Value >= '0') and (Value <= '9');
end;

procedure TLspFrameReader.Feed(const Data; Count: SizeInt);
var
  OldLength: SizeInt;
begin
  if Count < 0 then
    raise ELspTransportError.Create('Cannot append a negative byte count');
  if Count = 0 then
    Exit;

  OldLength := Length(FBuffer);
  SetLength(FBuffer, OldLength + Count);
  Move(Data, FBuffer[OldLength], Count);
end;

function TLspFrameReader.FindHeaderEnd: SizeInt;
var
  I: SizeInt;
begin
  Result := -1;
  if Length(FBuffer) < 4 then
    Exit;

  for I := 0 to Length(FBuffer) - 4 do
    if (FBuffer[I] = 13) and (FBuffer[I + 1] = 10) and
       (FBuffer[I + 2] = 13) and (FBuffer[I + 3] = 10) then
    begin
      Result := I;
      Exit;
    end;
end;

function TLspFrameReader.ParseContentLength(
  const Header: RawByteString): SizeInt;
var
  ColonPos, I, LineEnd, LineStart: SizeInt;
  HeaderName, HeaderValue, Line: RawByteString;
  LengthFound: Boolean;
  ParsedLength: Int64;
begin
  LengthFound := False;
  ParsedLength := 0;
  LineStart := 1;

  while LineStart <= Length(Header) do
  begin
    LineEnd := LineStart;
    while (LineEnd <= Length(Header) - 1) and
          not ((Header[LineEnd] = #13) and (Header[LineEnd + 1] = #10)) do
      Inc(LineEnd);

    if (LineEnd <= Length(Header) - 1) and
       (Header[LineEnd] = #13) and (Header[LineEnd + 1] = #10) then
    begin
      Line := Copy(Header, LineStart, LineEnd - LineStart);
      LineStart := LineEnd + 2;
    end
    else
    begin
      Line := Copy(Header, LineStart, Length(Header) - LineStart + 1);
      LineStart := Length(Header) + 1;
    end;

    ColonPos := Pos(':', Line);
    if ColonPos <= 1 then
      raise ELspTransportError.Create('Malformed LSP header line');

    HeaderName := LowerCase(Trim(Copy(Line, 1, ColonPos - 1)));
    HeaderValue := Trim(Copy(Line, ColonPos + 1, MaxInt));
    if HeaderName = 'content-length' then
    begin
      if LengthFound then
        raise ELspTransportError.Create('Duplicate Content-Length header');
      if HeaderValue = '' then
        raise ELspTransportError.Create('Empty Content-Length header');

      ParsedLength := 0;
      for I := 1 to Length(HeaderValue) do
      begin
        if not IsAsciiDigit(HeaderValue[I]) then
          raise ELspTransportError.Create('Invalid Content-Length header');
        ParsedLength := (ParsedLength * 10) + (Ord(HeaderValue[I]) - Ord('0'));
        if ParsedLength > LSP_MAX_PAYLOAD_BYTES then
          raise ELspTransportError.CreateFmt(
            'LSP payload exceeds %d-byte limit', [LSP_MAX_PAYLOAD_BYTES]);
      end;
      LengthFound := True;
    end;
  end;

  if not LengthFound then
    raise ELspTransportError.Create('Missing Content-Length header');
  Result := SizeInt(ParsedLength);
end;

function TLspFrameReader.TryReadFrame(out Payload: RawByteString): Boolean;
var
  BodyStart, BytesRemaining, ContentLength, HeaderEnd, TotalLength: SizeInt;
  Header: RawByteString;
begin
  Payload := '';
  HeaderEnd := FindHeaderEnd;
  if HeaderEnd < 0 then
  begin
    if Length(FBuffer) > LSP_MAX_HEADER_BYTES then
      raise ELspTransportError.CreateFmt(
        'LSP header exceeds %d-byte limit', [LSP_MAX_HEADER_BYTES]);
    Exit(False);
  end;

  if HeaderEnd > LSP_MAX_HEADER_BYTES then
    raise ELspTransportError.CreateFmt(
      'LSP header exceeds %d-byte limit', [LSP_MAX_HEADER_BYTES]);

  if HeaderEnd = 0 then
    Header := ''
  else
    SetString(Header, PAnsiChar(@FBuffer[0]), HeaderEnd);
  ContentLength := ParseContentLength(Header);

  BodyStart := HeaderEnd + 4;
  TotalLength := BodyStart + ContentLength;
  if Length(FBuffer) < TotalLength then
    Exit(False);

  SetLength(Payload, ContentLength);
  if ContentLength > 0 then
    Move(FBuffer[BodyStart], Payload[1], ContentLength);

  BytesRemaining := Length(FBuffer) - TotalLength;
  if BytesRemaining > 0 then
    Move(FBuffer[TotalLength], FBuffer[0], BytesRemaining);
  SetLength(FBuffer, BytesRemaining);
  Result := True;
end;

function TLspFrameReader.HasPendingData: Boolean;
begin
  Result := Length(FBuffer) > 0;
end;

function BuildLspFrame(const Payload: RawByteString): RawByteString;
begin
  Result := 'Content-Length: ' + RawByteString(IntToStr(Length(Payload))) +
    #13#10#13#10 + Payload;
end;

procedure WriteLspFrame(Stream: TStream; const Payload: RawByteString);
var
  Frame: RawByteString;
begin
  Frame := BuildLspFrame(Payload);
  if Length(Frame) > 0 then
    Stream.WriteBuffer(Frame[1], Length(Frame));
end;

end.
