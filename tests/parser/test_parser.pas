program TestParser;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, Fpcx_Syntax;

var
  Assertions: Integer = 0;

procedure Check(ACondition: Boolean; const AMessage: String);
begin
  Inc(Assertions);
  if not ACondition then
    raise Exception.Create('Assertion failed: ' + AMessage);
end;

function LoadRaw(const AFileName: String): RawByteString;
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, Stream.Size);
    if Stream.Size > 0 then
      Stream.ReadBuffer(Result[1], Stream.Size);
  finally
    Stream.Free;
  end;
end;

function CorpusPath(const AName: String): String;
var
  Root: String;
begin
  if ParamCount > 0 then
    Root := ParamStr(1)
  else
    Root := 'tests/corpus';
  Result := IncludeTrailingPathDelimiter(Root) + AName;
end;

procedure CheckLossless(const ASource: RawByteString; AResult: TSyntaxResult;
  const ALabel: String);
var
  I, ExpectedStart: SizeInt;
  Reconstructed: RawByteString;
  Tok: TSyntaxToken;
begin
  Reconstructed := '';
  ExpectedStart := 0;
  for I := 0 to AResult.TokenCount - 1 do
  begin
    Tok := AResult.Token(I);
    if Tok.Kind = tkEof then
    begin
      Check(Tok.StartByte = Length(ASource), ALabel + ': EOF start span');
      Check(Tok.EndByte = Length(ASource), ALabel + ': EOF end span');
      Continue;
    end;
    Check(Tok.StartByte = ExpectedStart, Format('%s: token %d starts at %d',
      [ALabel, I, ExpectedStart]));
    Check(Tok.EndByte >= Tok.StartByte, ALabel + ': token span is ordered');
    Check(Length(Tok.Text) = Tok.EndByte - Tok.StartByte,
      ALabel + ': token text length equals span length');
    Reconstructed := Reconstructed + Tok.Text;
    ExpectedStart := Tok.EndByte;
  end;
  Check(ExpectedStart = Length(ASource), ALabel + ': tokens cover source');
  Check(Reconstructed = ASource, ALabel + ': token text reconstructs source');
end;

procedure CheckDeterministic(const ASource: RawByteString; const ALabel: String);
var
  First, Second: TSyntaxResult;
  I: SizeInt;
  E1, E2: TSyntaxError;
  T1, T2: TSyntaxToken;
begin
  First := ParsePascal(ASource);
  Second := ParsePascal(ASource);
  try
    Check(First.TokenCount = Second.TokenCount,
      ALabel + ': deterministic token count');
    Check(First.ErrorCount = Second.ErrorCount,
      ALabel + ': deterministic error count');
    Check(First.NodeCount = Second.NodeCount,
      ALabel + ': deterministic node count');
    for I := 0 to First.TokenCount - 1 do
    begin
      T1 := First.Token(I);
      T2 := Second.Token(I);
      Check((T1.Kind = T2.Kind) and (T1.StartByte = T2.StartByte) and
        (T1.EndByte = T2.EndByte) and (T1.Text = T2.Text),
        Format('%s: deterministic token %d', [ALabel, I]));
    end;
    for I := 0 to First.ErrorCount - 1 do
    begin
      E1 := First.Error(I);
      E2 := Second.Error(I);
      Check((E1.Code = E2.Code) and (E1.Message = E2.Message) and
        (E1.StartByte = E2.StartByte) and (E1.EndByte = E2.EndByte),
        Format('%s: deterministic error %d', [ALabel, I]));
    end;
  finally
    Second.Free;
    First.Free;
  end;
end;

procedure TestValidSource;
var
  Source: RawByteString;
  Parsed: TSyntaxResult;
  I, TriviaCount, BlockCount: SizeInt;
  Tok: TSyntaxToken;
begin
  Source := LoadRaw(CorpusPath('valid_basic.pas'));
  Parsed := ParsePascal(Source);
  try
    CheckLossless(Source, Parsed, 'valid_basic');
    Check(Parsed.ErrorCount = 0, 'valid basic source has no proof-parser errors');
    TriviaCount := 0;
    for I := 0 to Parsed.TokenCount - 1 do
    begin
      Tok := Parsed.Token(I);
      if Tok.Kind in [tkWhitespace, tkNewline, tkComment] then
        Inc(TriviaCount);
    end;
    Check(TriviaCount > 0, 'trivia tokens are retained');
    BlockCount := 0;
    for I := 0 to Parsed.NodeCount - 1 do
      if Parsed.Node(I).Kind = nkBeginEndBlock then
        Inc(BlockCount);
    Check(BlockCount = 1, 'valid source has one begin/end block');
  finally
    Parsed.Free;
  end;
end;

procedure TestCrLfToken;
var
  Source: RawByteString;
  Parsed: TSyntaxResult;
  I: SizeInt;
  Found: Boolean;
begin
  Source := 'begin' + #13#10 + '  Work;' + #13#10 + 'end.';
  Parsed := ParsePascal(Source);
  try
    CheckLossless(Source, Parsed, 'crlf');
    Found := False;
    for I := 0 to Parsed.TokenCount - 1 do
      if (Parsed.Token(I).Kind = tkNewline) and
        (Parsed.Token(I).Text = #13#10) then
        Found := True;
    Check(Found, 'CRLF is retained as a single newline token');
  finally
    Parsed.Free;
  end;
end;

procedure TestMissingSemicolon;
var
  Source: RawByteString;
  Parsed: TSyntaxResult;
  I: SizeInt;
  FoundRecoveredStatement, FoundMissingToken: Boolean;
begin
  Source := LoadRaw(CorpusPath('missing_semicolon.pas'));
  Parsed := ParsePascal(Source);
  try
    CheckLossless(Source, Parsed, 'missing_semicolon');
    Check(Parsed.HasErrorCode('PAR001'),
      'missing semicolon produces PAR001 and parsing continues');
    FoundRecoveredStatement := False;
    FoundMissingToken := False;
    for I := 0 to Parsed.NodeCount - 1 do
    begin
      if (Parsed.Node(I).Kind = nkStatement) and
        Parsed.Node(I).IsRecovered then
        FoundRecoveredStatement := True;
      if (Parsed.Node(I).Kind = nkMissingToken) and
        Parsed.Node(I).IsRecovered then
        FoundMissingToken := True;
    end;
    Check(FoundRecoveredStatement, 'statement before missing semicolon is retained');
    Check(FoundMissingToken, 'missing semicolon has an explicit recovery node');
    CheckDeterministic(Source, 'missing_semicolon');
  finally
    Parsed.Free;
  end;
end;

procedure TestUnmatchedBlocks;
var
  Source: RawByteString;
  Parsed: TSyntaxResult;
  I, RecoveredBlocks: SizeInt;
begin
  Source := LoadRaw(CorpusPath('unmatched_begin.pas'));
  Parsed := ParsePascal(Source);
  try
    CheckLossless(Source, Parsed, 'unmatched_begin');
    Check(Parsed.HasErrorCode('PAR003'),
      'unmatched begin produces an expected-end diagnostic');
    RecoveredBlocks := 0;
    for I := 0 to Parsed.NodeCount - 1 do
      if (Parsed.Node(I).Kind = nkBeginEndBlock) and
        Parsed.Node(I).IsRecovered then
        Inc(RecoveredBlocks);
    Check(RecoveredBlocks = 2, 'both open blocks recover at EOF');
  finally
    Parsed.Free;
  end;

  Source := LoadRaw(CorpusPath('unexpected_end.pas'));
  Parsed := ParsePascal(Source);
  try
    CheckLossless(Source, Parsed, 'unexpected_end');
    Check(Parsed.HasErrorCode('PAR002'),
      'unexpected end produces PAR002 without a crash');
  finally
    Parsed.Free;
  end;
end;

procedure TestUnterminatedLexemes;
var
  Source: RawByteString;
  Parsed: TSyntaxResult;
begin
  Source := LoadRaw(CorpusPath('unterminated_string.pas'));
  Parsed := ParsePascal(Source);
  try
    CheckLossless(Source, Parsed, 'unterminated_string');
    Check(Parsed.HasErrorCode('LEX001'),
      'unterminated string produces LEX001');
  finally
    Parsed.Free;
  end;

  Source := LoadRaw(CorpusPath('unterminated_comment.pas'));
  Parsed := ParsePascal(Source);
  try
    CheckLossless(Source, Parsed, 'unterminated_comment');
    Check(Parsed.HasErrorCode('LEX002'),
      'unterminated comment produces LEX002');
  finally
    Parsed.Free;
  end;
end;

procedure TestEntireCorpusNeverCrashes;
const
  Names: array[0..8] of String = (
    'valid_basic.pas',
    'valid_features.pas',
    'missing_semicolon.pas',
    'unmatched_begin.pas',
    'unexpected_end.pas',
    'unterminated_string.pas',
    'unterminated_comment.pas',
    'incomplete_expression.pas',
    'directives_and_include.inc'
  );
var
  I: SizeInt;
  Source: RawByteString;
  Parsed: TSyntaxResult;
begin
  for I := Low(Names) to High(Names) do
  begin
    Source := LoadRaw(CorpusPath(Names[I]));
    Parsed := ParsePascal(Source);
    try
      CheckLossless(Source, Parsed, Names[I]);
      Check(Parsed.NodeCount > 0, Names[I] + ': parser always returns a root node');
    finally
      Parsed.Free;
    end;
  end;
end;

begin
  TestValidSource;
  TestCrLfToken;
  TestMissingSemicolon;
  TestUnmatchedBlocks;
  TestUnterminatedLexemes;
  TestEntireCorpusNeverCrashes;
  WriteLn('PASS test_parser assertions=', Assertions);
end.
