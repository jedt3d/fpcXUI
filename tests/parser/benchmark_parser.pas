program BenchmarkParser;

{$mode objfpc}{$H+}

uses
  SysUtils, Fpcx_Syntax;

function BuildSource(AStatementCount: Integer): RawByteString;
var
  I: Integer;
begin
  Result := 'program GeneratedBenchmark;' + LineEnding +
    '{$mode objfpc}{$H+}' + LineEnding +
    'var Value: Integer;' + LineEnding +
    'begin' + LineEnding;
  for I := 1 to AStatementCount do
    Result := Result + '  Value := Value + ' + IntToStr((I mod 17) + 1) +
      '; // retained trivia ' + IntToStr(I) + LineEnding;
  Result := Result + '  WriteLn(Value);' + LineEnding + 'end.' + LineEnding;
end;

var
  Iterations, StatementCount, I: Integer;
  Source: RawByteString;
  Parsed: TSyntaxResult;
  Started, ElapsedMs, TotalBytes: QWord;
  MegabytesPerSecond: Double;
begin
  Iterations := 100;
  StatementCount := 1000;
  if ParamCount >= 1 then
    Iterations := StrToInt(ParamStr(1));
  if ParamCount >= 2 then
    StatementCount := StrToInt(ParamStr(2));
  if (Iterations < 1) or (StatementCount < 1) then
    raise Exception.Create('iterations and statement count must be positive');

  Source := BuildSource(StatementCount);
  Parsed := ParsePascal(Source);
  try
    if Parsed.ErrorCount <> 0 then
      raise Exception.CreateFmt('generated source has %d parser errors',
        [Parsed.ErrorCount]);
  finally
    Parsed.Free;
  end;

  Started := GetTickCount64;
  for I := 1 to Iterations do
  begin
    Parsed := ParsePascal(Source);
    Parsed.Free;
  end;
  ElapsedMs := GetTickCount64 - Started;
  if ElapsedMs = 0 then
    ElapsedMs := 1;
  TotalBytes := QWord(Length(Source)) * QWord(Iterations);
  MegabytesPerSecond := (TotalBytes / 1048576.0) / (ElapsedMs / 1000.0);

  WriteLn('engine=independent-proof');
  WriteLn('iterations=', Iterations);
  WriteLn('statements=', StatementCount);
  WriteLn('source_bytes=', Length(Source));
  WriteLn('total_bytes=', TotalBytes);
  WriteLn('elapsed_ms=', ElapsedMs);
  WriteLn('throughput_mib_per_s=', FormatFloat('0.00', MegabytesPerSecond));
end.
