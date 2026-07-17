unit Fpcx_Text;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  ETextDocumentError = class(Exception);

  TTextPosition = record
    Line: SizeInt;
    Character: SizeInt;
  end;

  TTextRange = record
    StartPos: TTextPosition;
    EndPos: TTextPosition;
  end;

  TTextChange = record
    HasRange: Boolean;
    Range: TTextRange;
    Text: RawByteString;
  end;

  { TFpcTextDocument

    Text is UTF-8. Byte offsets are zero based and EndByte-style offsets are
    exclusive. LSP positions use zero-based lines and UTF-16 code units. }

  TFpcTextDocument = class
  private
    FUri: RawByteString;
    FVersion: Int64;
    FText: RawByteString;
    function CheckNewVersion(ANewVersion: Int64; out AError: RawByteString): Boolean;
  public
    constructor Create(const AUri: RawByteString; AVersion: Int64;
      const AText: RawByteString);
    function ApplyFullChange(ANewVersion: Int64; const AText: RawByteString;
      out AError: RawByteString): Boolean;
    function ApplyIncrementalChange(ANewVersion: Int64; const ARange: TTextRange;
      const AReplacement: RawByteString; out AError: RawByteString): Boolean;
    function ApplyChanges(ANewVersion: Int64; const AChanges: array of TTextChange;
      out AError: RawByteString): Boolean;
    function PositionToByteOffset(const APosition: TTextPosition;
      out AByteOffset: SizeInt; out AError: RawByteString): Boolean;
    function ByteOffsetToPosition(AByteOffset: SizeInt; out APosition: TTextPosition;
      out AError: RawByteString): Boolean;
    function LineCount: SizeInt;
    property Uri: RawByteString read FUri;
    property Version: Int64 read FVersion;
    property Text: RawByteString read FText;
  end;

function TextPosition(ALine, ACharacter: SizeInt): TTextPosition;
function TextRange(AStartLine, AStartCharacter, AEndLine,
  AEndCharacter: SizeInt): TTextRange;
function FullTextChange(const AText: RawByteString): TTextChange;
function IncrementalTextChange(const ARange: TTextRange;
  const AText: RawByteString): TTextChange;
function ValidateUtf8(const AText: RawByteString;
  out AError: RawByteString): Boolean;

implementation

const
  ERR_INVALID_UTF8 = 'TXT001';
  ERR_STALE_VERSION = 'TXT002';
  ERR_LINE_OUTSIDE = 'TXT003';
  ERR_CHARACTER_OUTSIDE = 'TXT004';
  ERR_SPLIT_SURROGATE = 'TXT005';
  ERR_REVERSED_RANGE = 'TXT006';
  ERR_BYTE_OUTSIDE = 'TXT007';
  ERR_SPLIT_UTF8 = 'TXT008';
  ERR_SPLIT_CRLF = 'TXT009';

function TextPosition(ALine, ACharacter: SizeInt): TTextPosition;
begin
  Result.Line := ALine;
  Result.Character := ACharacter;
end;

function TextRange(AStartLine, AStartCharacter, AEndLine,
  AEndCharacter: SizeInt): TTextRange;
begin
  Result.StartPos := TextPosition(AStartLine, AStartCharacter);
  Result.EndPos := TextPosition(AEndLine, AEndCharacter);
end;

function FullTextChange(const AText: RawByteString): TTextChange;
begin
  Result.HasRange := False;
  Result.Range := TextRange(0, 0, 0, 0);
  Result.Text := AText;
end;

function IncrementalTextChange(const ARange: TTextRange;
  const AText: RawByteString): TTextChange;
begin
  Result.HasRange := True;
  Result.Range := ARange;
  Result.Text := AText;
end;

function DecodeUtf8(const AText: RawByteString; AByteOffset: SizeInt;
  out ACodePoint: Cardinal; out AByteCount: SizeInt): Boolean;
var
  B0, B1, B2, B3: Byte;
  Remaining: SizeInt;
begin
  Result := False;
  ACodePoint := 0;
  AByteCount := 0;
  Remaining := Length(AText) - AByteOffset;
  if Remaining <= 0 then
    Exit;

  B0 := Ord(AText[AByteOffset + 1]);
  if B0 < $80 then
  begin
    ACodePoint := B0;
    AByteCount := 1;
    Exit(True);
  end;

  if (B0 >= $C2) and (B0 <= $DF) then
  begin
    if Remaining < 2 then
      Exit;
    B1 := Ord(AText[AByteOffset + 2]);
    if (B1 and $C0) <> $80 then
      Exit;
    ACodePoint := ((B0 and $1F) shl 6) or (B1 and $3F);
    AByteCount := 2;
    Exit(True);
  end;

  if (B0 >= $E0) and (B0 <= $EF) then
  begin
    if Remaining < 3 then
      Exit;
    B1 := Ord(AText[AByteOffset + 2]);
    B2 := Ord(AText[AByteOffset + 3]);
    if ((B1 and $C0) <> $80) or ((B2 and $C0) <> $80) then
      Exit;
    if ((B0 = $E0) and (B1 < $A0)) or
       ((B0 = $ED) and (B1 >= $A0)) then
      Exit;
    ACodePoint := ((B0 and $0F) shl 12) or ((B1 and $3F) shl 6) or
      (B2 and $3F);
    AByteCount := 3;
    Exit(True);
  end;

  if (B0 >= $F0) and (B0 <= $F4) then
  begin
    if Remaining < 4 then
      Exit;
    B1 := Ord(AText[AByteOffset + 2]);
    B2 := Ord(AText[AByteOffset + 3]);
    B3 := Ord(AText[AByteOffset + 4]);
    if ((B1 and $C0) <> $80) or ((B2 and $C0) <> $80) or
       ((B3 and $C0) <> $80) then
      Exit;
    if ((B0 = $F0) and (B1 < $90)) or
       ((B0 = $F4) and (B1 >= $90)) then
      Exit;
    ACodePoint := ((B0 and $07) shl 18) or ((B1 and $3F) shl 12) or
      ((B2 and $3F) shl 6) or (B3 and $3F);
    AByteCount := 4;
    Exit(True);
  end;
end;

function ValidateUtf8(const AText: RawByteString;
  out AError: RawByteString): Boolean;
var
  Offset, ByteCount: SizeInt;
  CodePoint: Cardinal;
begin
  AError := '';
  Offset := 0;
  while Offset < Length(AText) do
  begin
    if not DecodeUtf8(AText, Offset, CodePoint, ByteCount) then
    begin
      AError := Format('%s: invalid UTF-8 at byte %d',
        [ERR_INVALID_UTF8, Offset]);
      Exit(False);
    end;
    Inc(Offset, ByteCount);
  end;
  Result := True;
end;

function ComparePositions(const ALeft, ARight: TTextPosition): Integer;
begin
  if ALeft.Line < ARight.Line then
    Exit(-1);
  if ALeft.Line > ARight.Line then
    Exit(1);
  if ALeft.Character < ARight.Character then
    Exit(-1);
  if ALeft.Character > ARight.Character then
    Exit(1);
  Result := 0;
end;

constructor TFpcTextDocument.Create(const AUri: RawByteString; AVersion: Int64;
  const AText: RawByteString);
var
  ErrorText: RawByteString;
begin
  inherited Create;
  if not ValidateUtf8(AText, ErrorText) then
    raise ETextDocumentError.Create(ErrorText);
  FUri := AUri;
  FVersion := AVersion;
  FText := AText;
end;

function TFpcTextDocument.CheckNewVersion(ANewVersion: Int64;
  out AError: RawByteString): Boolean;
begin
  AError := '';
  if ANewVersion <= FVersion then
  begin
    AError := Format('%s: document version %d is not newer than %d',
      [ERR_STALE_VERSION, ANewVersion, FVersion]);
    Exit(False);
  end;
  Result := True;
end;

function TFpcTextDocument.ApplyFullChange(ANewVersion: Int64;
  const AText: RawByteString; out AError: RawByteString): Boolean;
begin
  if not CheckNewVersion(ANewVersion, AError) then
    Exit(False);
  if not ValidateUtf8(AText, AError) then
    Exit(False);
  FText := AText;
  FVersion := ANewVersion;
  AError := '';
  Result := True;
end;

function TFpcTextDocument.ApplyIncrementalChange(ANewVersion: Int64;
  const ARange: TTextRange; const AReplacement: RawByteString;
  out AError: RawByteString): Boolean;
var
  StartByte, EndByte: SizeInt;
  NewText: RawByteString;
begin
  if not CheckNewVersion(ANewVersion, AError) then
    Exit(False);
  if not ValidateUtf8(AReplacement, AError) then
    Exit(False);
  if ComparePositions(ARange.StartPos, ARange.EndPos) > 0 then
  begin
    AError := ERR_REVERSED_RANGE + ': range start is after range end';
    Exit(False);
  end;
  if not PositionToByteOffset(ARange.StartPos, StartByte, AError) then
    Exit(False);
  if not PositionToByteOffset(ARange.EndPos, EndByte, AError) then
    Exit(False);
  NewText := Copy(FText, 1, StartByte) + AReplacement +
    Copy(FText, EndByte + 1, Length(FText) - EndByte);
  FText := NewText;
  FVersion := ANewVersion;
  AError := '';
  Result := True;
end;

function TFpcTextDocument.ApplyChanges(ANewVersion: Int64;
  const AChanges: array of TTextChange; out AError: RawByteString): Boolean;
var
  I, StartByte, EndByte: SizeInt;
  Working: TFpcTextDocument;
  ChangeError: RawByteString;
begin
  if not CheckNewVersion(ANewVersion, AError) then
    Exit(False);

  Working := TFpcTextDocument.Create(FUri, FVersion, FText);
  try
    for I := Low(AChanges) to High(AChanges) do
    begin
      if not ValidateUtf8(AChanges[I].Text, ChangeError) then
      begin
        AError := Format('change %d: %s', [I, ChangeError]);
        Exit(False);
      end;

      if not AChanges[I].HasRange then
      begin
        Working.FText := AChanges[I].Text;
        Continue;
      end;

      if ComparePositions(AChanges[I].Range.StartPos,
        AChanges[I].Range.EndPos) > 0 then
      begin
        AError := Format('change %d: %s: range start is after range end',
          [I, ERR_REVERSED_RANGE]);
        Exit(False);
      end;
      if not Working.PositionToByteOffset(AChanges[I].Range.StartPos,
        StartByte, ChangeError) then
      begin
        AError := Format('change %d: %s', [I, ChangeError]);
        Exit(False);
      end;
      if not Working.PositionToByteOffset(AChanges[I].Range.EndPos,
        EndByte, ChangeError) then
      begin
        AError := Format('change %d: %s', [I, ChangeError]);
        Exit(False);
      end;
      Working.FText := Copy(Working.FText, 1, StartByte) + AChanges[I].Text +
        Copy(Working.FText, EndByte + 1, Length(Working.FText) - EndByte);
    end;

    FText := Working.FText;
    FVersion := ANewVersion;
    AError := '';
    Result := True;
  finally
    Working.Free;
  end;
end;

function TFpcTextDocument.PositionToByteOffset(const APosition: TTextPosition;
  out AByteOffset: SizeInt; out AError: RawByteString): Boolean;
var
  Offset, CurrentLine, Utf16Column, ByteCount, Units: SizeInt;
  CodePoint: Cardinal;
begin
  AByteOffset := -1;
  AError := '';
  if APosition.Line < 0 then
  begin
    AError := Format('%s: line %d is outside the document',
      [ERR_LINE_OUTSIDE, APosition.Line]);
    Exit(False);
  end;
  if APosition.Character < 0 then
  begin
    AError := Format('%s: character %d is outside line %d',
      [ERR_CHARACTER_OUTSIDE, APosition.Character, APosition.Line]);
    Exit(False);
  end;

  Offset := 0;
  CurrentLine := 0;
  while CurrentLine < APosition.Line do
  begin
    if Offset >= Length(FText) then
    begin
      AError := Format('%s: line %d is outside the document',
        [ERR_LINE_OUTSIDE, APosition.Line]);
      Exit(False);
    end;
    if FText[Offset + 1] = #13 then
    begin
      Inc(Offset);
      if (Offset < Length(FText)) and (FText[Offset + 1] = #10) then
        Inc(Offset);
      Inc(CurrentLine);
    end
    else if FText[Offset + 1] = #10 then
    begin
      Inc(Offset);
      Inc(CurrentLine);
    end
    else
    begin
      if not DecodeUtf8(FText, Offset, CodePoint, ByteCount) then
      begin
        AError := Format('%s: invalid UTF-8 at byte %d',
          [ERR_INVALID_UTF8, Offset]);
        Exit(False);
      end;
      Inc(Offset, ByteCount);
    end;
  end;

  Utf16Column := 0;
  while Offset < Length(FText) do
  begin
    if Utf16Column = APosition.Character then
    begin
      AByteOffset := Offset;
      Exit(True);
    end;
    if (FText[Offset + 1] = #13) or (FText[Offset + 1] = #10) then
      Break;
    if not DecodeUtf8(FText, Offset, CodePoint, ByteCount) then
    begin
      AError := Format('%s: invalid UTF-8 at byte %d',
        [ERR_INVALID_UTF8, Offset]);
      Exit(False);
    end;
    if CodePoint > $FFFF then
      Units := 2
    else
      Units := 1;
    if Utf16Column + Units > APosition.Character then
    begin
      AError := Format('%s: character %d splits a surrogate pair on line %d',
        [ERR_SPLIT_SURROGATE, APosition.Character, APosition.Line]);
      Exit(False);
    end;
    Inc(Utf16Column, Units);
    Inc(Offset, ByteCount);
  end;

  if Utf16Column = APosition.Character then
  begin
    AByteOffset := Offset;
    Exit(True);
  end;
  AError := Format('%s: character %d is outside line %d (length %d)',
    [ERR_CHARACTER_OUTSIDE, APosition.Character, APosition.Line, Utf16Column]);
  Result := False;
end;

function TFpcTextDocument.ByteOffsetToPosition(AByteOffset: SizeInt;
  out APosition: TTextPosition; out AError: RawByteString): Boolean;
var
  Offset, ByteCount, Units: SizeInt;
  CodePoint: Cardinal;
begin
  APosition := TextPosition(-1, -1);
  AError := '';
  if (AByteOffset < 0) or (AByteOffset > Length(FText)) then
  begin
    AError := Format('%s: byte %d is outside the document',
      [ERR_BYTE_OUTSIDE, AByteOffset]);
    Exit(False);
  end;

  Offset := 0;
  APosition := TextPosition(0, 0);
  while Offset < Length(FText) do
  begin
    if Offset = AByteOffset then
      Exit(True);
    if FText[Offset + 1] = #13 then
    begin
      if (Offset + 1 < Length(FText)) and (FText[Offset + 2] = #10) then
      begin
        if AByteOffset = Offset + 1 then
        begin
          AError := Format('%s: byte %d splits a CRLF line ending',
            [ERR_SPLIT_CRLF, AByteOffset]);
          Exit(False);
        end;
        Inc(Offset, 2);
      end
      else
        Inc(Offset);
      Inc(APosition.Line);
      APosition.Character := 0;
      Continue;
    end;
    if FText[Offset + 1] = #10 then
    begin
      Inc(Offset);
      Inc(APosition.Line);
      APosition.Character := 0;
      Continue;
    end;
    if not DecodeUtf8(FText, Offset, CodePoint, ByteCount) then
    begin
      AError := Format('%s: invalid UTF-8 at byte %d',
        [ERR_INVALID_UTF8, Offset]);
      Exit(False);
    end;
    if (AByteOffset > Offset) and (AByteOffset < Offset + ByteCount) then
    begin
      AError := Format('%s: byte %d splits a UTF-8 scalar',
        [ERR_SPLIT_UTF8, AByteOffset]);
      Exit(False);
    end;
    if CodePoint > $FFFF then
      Units := 2
    else
      Units := 1;
    Inc(APosition.Character, Units);
    Inc(Offset, ByteCount);
  end;
  Result := Offset = AByteOffset;
end;

function TFpcTextDocument.LineCount: SizeInt;
var
  Offset: SizeInt;
begin
  Result := 1;
  Offset := 0;
  while Offset < Length(FText) do
  begin
    if FText[Offset + 1] = #13 then
    begin
      Inc(Offset);
      if (Offset < Length(FText)) and (FText[Offset + 1] = #10) then
        Inc(Offset);
      Inc(Result);
    end
    else if FText[Offset + 1] = #10 then
    begin
      Inc(Offset);
      Inc(Result);
    end
    else
      Inc(Offset);
  end;
end;

end.
