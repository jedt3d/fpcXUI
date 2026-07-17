program ProbeFclPassrc;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, PassrcUtil;

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

procedure SaveRaw(const AFileName: String; const ASource: RawByteString);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(AFileName, fmCreate);
  try
    if Length(ASource) > 0 then
      Stream.WriteBuffer(ASource[1], Length(ASource));
  finally
    Stream.Free;
  end;
end;

function ParseFile(const AFileName: String; out AIdentifierCount: Integer;
  out AError: String): Boolean;
var
  Analysis: TPasSrcAnalysis;
  Identifiers: TStringList;
begin
  Result := False;
  AIdentifierCount := 0;
  AError := '';
  Analysis := TPasSrcAnalysis.Create(nil);
  Identifiers := TStringList.Create;
  try
    try
      Analysis.FileName := ExpandFileName(AFileName);
      Analysis.GetAllIdentifiers(Identifiers, True);
      AIdentifierCount := Identifiers.Count;
      Result := True;
    except
      on E: Exception do
        AError := E.ClassName + ': ' + E.Message;
    end;
  finally
    Identifiers.Free;
    Analysis.Free;
  end;
end;

procedure RunFiles;
var
  I, IdentifierCount: Integer;
  ErrorText: String;
begin
  if ParamCount = 0 then
    raise Exception.Create('pass one or more Pascal source files');
  for I := 1 to ParamCount do
    if ParseFile(ParamStr(I), IdentifierCount, ErrorText) then
      WriteLn('file=', ParamStr(I), ' status=ok identifiers=', IdentifierCount)
    else
      WriteLn('file=', ParamStr(I), ' status=error detail=', ErrorText);
end;

procedure RunBenchmark;
var
  Iterations, StatementCount, I, IdentifierCount: Integer;
  Source: RawByteString;
  TempFile, ErrorText: String;
  Started, ElapsedMs, TotalBytes: QWord;
  MegabytesPerSecond: Double;
begin
  Iterations := 100;
  StatementCount := 1000;
  if ParamCount >= 2 then
    Iterations := StrToInt(ParamStr(2));
  if ParamCount >= 3 then
    StatementCount := StrToInt(ParamStr(3));
  if (Iterations < 1) or (StatementCount < 1) then
    raise Exception.Create('iterations and statement count must be positive');

  Source := BuildSource(StatementCount);
  TempFile := GetTempFileName(GetTempDir(False), 'fpcx') + '.pas';
  SaveRaw(TempFile, Source);
  try
    if not ParseFile(TempFile, IdentifierCount, ErrorText) then
      raise Exception.Create('fcl-passrc warmup failed: ' + ErrorText);
    Started := GetTickCount64;
    for I := 1 to Iterations do
      if not ParseFile(TempFile, IdentifierCount, ErrorText) then
        raise Exception.Create('fcl-passrc parse failed: ' + ErrorText);
    ElapsedMs := GetTickCount64 - Started;
  finally
    DeleteFile(TempFile);
  end;
  if ElapsedMs = 0 then
    ElapsedMs := 1;
  TotalBytes := QWord(Length(Source)) * QWord(Iterations);
  MegabytesPerSecond := (TotalBytes / 1048576.0) / (ElapsedMs / 1000.0);

  WriteLn('engine=fcl-passrc-3.2.2');
  WriteLn('iterations=', Iterations);
  WriteLn('statements=', StatementCount);
  WriteLn('source_bytes=', Length(Source));
  WriteLn('total_bytes=', TotalBytes);
  WriteLn('elapsed_ms=', ElapsedMs);
  WriteLn('throughput_mib_per_s=', FormatFloat('0.00', MegabytesPerSecond));
  WriteLn('identifier_count=', IdentifierCount);
end;

begin
  if (ParamCount >= 1) and (ParamStr(1) = '--benchmark') then
    RunBenchmark
  else
    RunFiles;
end.
