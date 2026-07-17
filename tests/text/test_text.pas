program TestText;

{$mode objfpc}{$H+}

uses
  SysUtils, Fpcx_Text;

var
  Assertions: Integer = 0;

procedure Check(ACondition: Boolean; const AMessage: String);
begin
  Inc(Assertions);
  if not ACondition then
    raise Exception.Create('Assertion failed: ' + AMessage);
end;

procedure CheckEqual(AExpected, AActual: SizeInt; const AMessage: String);
begin
  Check(AExpected = AActual, Format('%s (expected %d, got %d)',
    [AMessage, AExpected, AActual]));
end;

procedure CheckText(const AExpected, AActual: RawByteString;
  const AMessage: String);
begin
  Check(AExpected = AActual, AMessage + ' (expected "' + AExpected +
    '", got "' + AActual + '")');
end;

procedure CheckError(const AExpectedCode, AActual: RawByteString;
  const AMessage: String);
begin
  Check(Pos(AExpectedCode + ':', AActual) = 1,
    AMessage + ' (got "' + AActual + '")');
end;

procedure TestUtf16AndLineEndings;
const
  Emoji: RawByteString = #240#159#152#128;
var
  Doc: TFpcTextDocument;
  Source, ErrorText: RawByteString;
  Offset: SizeInt;
  Posn: TTextPosition;
begin
  Source := 'ab' + Emoji + 'c' + #13#10 + 'xy' + #10;
  Doc := TFpcTextDocument.Create('file:///unicode.pas', 1, Source);
  try
    CheckEqual(3, Doc.LineCount, 'CRLF and LF form three lines');

    Check(Doc.PositionToByteOffset(TextPosition(0, 2), Offset, ErrorText),
      'position before emoji is valid');
    CheckEqual(2, Offset, 'emoji starts at byte 2');
    Check(Doc.PositionToByteOffset(TextPosition(0, 4), Offset, ErrorText),
      'position after emoji is valid');
    CheckEqual(6, Offset, 'emoji consumes four UTF-8 bytes and two UTF-16 units');
    Check(not Doc.PositionToByteOffset(TextPosition(0, 3), Offset, ErrorText),
      'position splitting surrogate pair is rejected');
    CheckError('TXT005', ErrorText, 'surrogate split has deterministic code');

    Check(Doc.ByteOffsetToPosition(7, Posn, ErrorText),
      'byte at CR maps to line end');
    CheckEqual(0, Posn.Line, 'CR belongs to previous line end');
    CheckEqual(5, Posn.Character, 'line zero UTF-16 length');
    Check(not Doc.ByteOffsetToPosition(8, Posn, ErrorText),
      'byte between CR and LF is rejected');
    CheckError('TXT009', ErrorText, 'CRLF split has deterministic code');
    Check(Doc.ByteOffsetToPosition(9, Posn, ErrorText),
      'byte after CRLF is valid');
    CheckEqual(1, Posn.Line, 'byte after CRLF is line one');
    CheckEqual(0, Posn.Character, 'line one starts at UTF-16 zero');
    Check(not Doc.ByteOffsetToPosition(3, Posn, ErrorText),
      'byte splitting UTF-8 scalar is rejected');
    CheckError('TXT008', ErrorText, 'UTF-8 split has deterministic code');

    Check(Doc.PositionToByteOffset(TextPosition(1, 2), Offset, ErrorText),
      'line one end is representable');
    CheckEqual(11, Offset, 'line one end points to LF');
    Check(Doc.PositionToByteOffset(TextPosition(2, 0), Offset, ErrorText),
      'empty final line is representable');
    CheckEqual(12, Offset, 'final line starts at EOF');
  finally
    Doc.Free;
  end;
end;

procedure TestRoundTrip;
const
  Emoji: RawByteString = #240#159#152#128;
  ValidOffsets: array[0..9] of SizeInt = (0, 1, 2, 6, 7, 9, 10, 11, 12, 13);
var
  Doc: TFpcTextDocument;
  Source, ErrorText: RawByteString;
  Posn: TTextPosition;
  Offset, RoundTrip, I: SizeInt;
begin
  Source := 'ab' + Emoji + 'c' + #13#10 + 'xy' + #10 + 'q';
  Doc := TFpcTextDocument.Create('file:///roundtrip.pas', 7, Source);
  try
    for I := Low(ValidOffsets) to High(ValidOffsets) do
    begin
      Offset := ValidOffsets[I];
      Check(Doc.ByteOffsetToPosition(Offset, Posn, ErrorText),
        Format('byte %d maps to a position', [Offset]));
      Check(Doc.PositionToByteOffset(Posn, RoundTrip, ErrorText),
        Format('position for byte %d maps back', [Offset]));
      CheckEqual(Offset, RoundTrip, Format('byte %d round trips', [Offset]));
    end;
  finally
    Doc.Free;
  end;
end;

procedure TestVersionedChanges;
const
  Emoji: RawByteString = #240#159#152#128;
var
  Doc: TFpcTextDocument;
  ErrorText, BeforeFailure: RawByteString;
begin
  Doc := TFpcTextDocument.Create('file:///changes.pas', 1,
    'ab' + Emoji + 'c' + #13#10 + 'xy');
  try
    Check(Doc.ApplyIncrementalChange(2, TextRange(0, 2, 0, 4), 'Z',
      ErrorText), 'replace astral scalar');
    CheckText('abZc' + #13#10 + 'xy', Doc.Text,
      'first incremental result');
    CheckEqual(2, Doc.Version, 'first edit advances version');

    Check(Doc.ApplyIncrementalChange(3, TextRange(1, 0, 1, 2), 'hello',
      ErrorText), 'replace second line');
    CheckText('abZc' + #13#10 + 'hello', Doc.Text,
      'second sequential incremental result');
    CheckEqual(3, Doc.Version, 'second edit advances version');

    BeforeFailure := Doc.Text;
    Check(not Doc.ApplyIncrementalChange(3, TextRange(0, 0, 0, 1), 'X',
      ErrorText), 'same version is stale');
    CheckError('TXT002', ErrorText, 'stale version has deterministic code');
    CheckText(BeforeFailure, Doc.Text, 'stale edit does not mutate text');
    CheckEqual(3, Doc.Version, 'stale edit does not mutate version');

    Check(not Doc.ApplyIncrementalChange(4, TextRange(1, 3, 0, 0), 'X',
      ErrorText), 'reversed range is rejected');
    CheckError('TXT006', ErrorText, 'reversed range has deterministic code');
    CheckText(BeforeFailure, Doc.Text, 'reversed range does not mutate text');

    Check(Doc.ApplyFullChange(4, 'final' + #10, ErrorText),
      'full change is accepted');
    CheckText('final' + #10, Doc.Text, 'full change replaces document');
    CheckEqual(4, Doc.Version, 'full change advances version');
  finally
    Doc.Free;
  end;
end;

procedure TestInvalidInputs;
var
  Doc: TFpcTextDocument;
  ErrorText: RawByteString;
  Offset: SizeInt;
  Raised: Boolean;
begin
  Raised := False;
  try
    Doc := TFpcTextDocument.Create('file:///invalid.pas', 1, #$C0#$AF);
    Doc.Free;
  except
    on E: ETextDocumentError do
    begin
      Raised := True;
      CheckError('TXT001', E.Message, 'constructor rejects invalid UTF-8');
    end;
  end;
  Check(Raised, 'invalid UTF-8 raises a deterministic document error');

  Doc := TFpcTextDocument.Create('file:///bounds.pas', 1, 'abc');
  try
    Check(not Doc.PositionToByteOffset(TextPosition(0, 4), Offset, ErrorText),
      'character beyond line end is rejected');
    CheckError('TXT004', ErrorText, 'line bound has deterministic code');
    Check(not Doc.PositionToByteOffset(TextPosition(1, 0), Offset, ErrorText),
      'line beyond document is rejected');
    CheckError('TXT003', ErrorText, 'line bound has deterministic code');
  finally
    Doc.Free;
  end;
end;

procedure TestAtomicChangeBatch;
var
  Doc: TFpcTextDocument;
  Changes: array[0..1] of TTextChange;
  ErrorText, BeforeFailure: RawByteString;
begin
  Doc := TFpcTextDocument.Create('file:///batch.pas', 10,
    'one' + #10 + 'two' + #10 + 'three');
  try
    Changes[0] := IncrementalTextChange(TextRange(0, 0, 0, 3), '1');
    Changes[1] := IncrementalTextChange(TextRange(1, 0, 1, 3), '2');
    Check(Doc.ApplyChanges(11, Changes, ErrorText),
      'sequential content changes share one final version');
    CheckText('1' + #10 + '2' + #10 + 'three', Doc.Text,
      'batch changes apply in array order');
    CheckEqual(11, Doc.Version, 'batch advances version once');

    BeforeFailure := Doc.Text;
    Changes[0] := IncrementalTextChange(TextRange(0, 0, 0, 1), 'first');
    Changes[1] := IncrementalTextChange(TextRange(99, 0, 99, 0), 'bad');
    Check(not Doc.ApplyChanges(12, Changes, ErrorText),
      'invalid later change rejects entire batch');
    Check(Pos('change 1: TXT003:', ErrorText) = 1,
      'batch error identifies change index and deterministic mapping code');
    CheckText(BeforeFailure, Doc.Text, 'failed batch is atomic');
    CheckEqual(11, Doc.Version, 'failed batch does not advance version');

    Changes[0] := FullTextChange('abc' + #10);
    Changes[1] := IncrementalTextChange(TextRange(0, 1, 0, 2), 'Z');
    Check(Doc.ApplyChanges(12, Changes, ErrorText),
      'full and ranged changes can be sequenced');
    CheckText('aZc' + #10, Doc.Text,
      'ranged change observes preceding full replacement');
    CheckEqual(12, Doc.Version, 'mixed batch commits final version');
  finally
    Doc.Free;
  end;
end;

begin
  TestUtf16AndLineEndings;
  TestRoundTrip;
  TestVersionedChanges;
  TestInvalidInputs;
  TestAtomicChangeBatch;
  WriteLn('PASS test_text assertions=', Assertions);
end.
