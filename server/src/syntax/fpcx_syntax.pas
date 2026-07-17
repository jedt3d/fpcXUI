unit Fpcx_Syntax;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  TSyntaxTokenKind = (
    tkIdentifier,
    tkKeyword,
    tkNumber,
    tkString,
    tkSymbol,
    tkSemicolon,
    tkWhitespace,
    tkNewline,
    tkComment,
    tkUnknown,
    tkEof
  );

  TSyntaxNodeKind = (
    nkCompilationUnit,
    nkBeginEndBlock,
    nkStatement,
    nkMissingToken
  );

  TSyntaxToken = record
    Kind: TSyntaxTokenKind;
    StartByte: SizeInt;
    EndByte: SizeInt;
    Text: RawByteString;
  end;

  TSyntaxError = record
    Code: RawByteString;
    Message: RawByteString;
    StartByte: SizeInt;
    EndByte: SizeInt;
  end;

  { Nodes are a flat Phase 0 proof. ParentIndex preserves hierarchy while
    token indices and byte spans make every recovered region inspectable. }
  TSyntaxNode = record
    Kind: TSyntaxNodeKind;
    StartByte: SizeInt;
    EndByte: SizeInt;
    FirstToken: SizeInt;
    LastToken: SizeInt;
    ParentIndex: SizeInt;
    IsRecovered: Boolean;
  end;

  TSyntaxResult = class
  private
    FTokens: array of TSyntaxToken;
    FErrors: array of TSyntaxError;
    FNodes: array of TSyntaxNode;
    function AddToken(AKind: TSyntaxTokenKind; AStartByte, AEndByte: SizeInt;
      const AText: RawByteString): SizeInt;
    function AddError(const ACode, AMessage: RawByteString;
      AStartByte, AEndByte: SizeInt): SizeInt;
    function AddNode(AKind: TSyntaxNodeKind; AStartByte, AEndByte,
      AFirstToken, ALastToken, AParentIndex: SizeInt;
      AIsRecovered: Boolean): SizeInt;
    procedure SetNode(AIndex: SizeInt; const ANode: TSyntaxNode);
  public
    function TokenCount: SizeInt;
    function ErrorCount: SizeInt;
    function NodeCount: SizeInt;
    function Token(AIndex: SizeInt): TSyntaxToken;
    function Error(AIndex: SizeInt): TSyntaxError;
    function Node(AIndex: SizeInt): TSyntaxNode;
    function HasErrorCode(const ACode: RawByteString): Boolean;
  end;

function ParsePascal(const ASource: RawByteString): TSyntaxResult;
function SyntaxTokenKindName(AKind: TSyntaxTokenKind): RawByteString;

implementation

type
  TBlockFrame = record
    NodeIndex: SizeInt;
    BeginTokenIndex: SizeInt;
    StatementFirstToken: SizeInt;
    StatementLastToken: SizeInt;
    SawLineBreak: Boolean;
  end;

function SyntaxTokenKindName(AKind: TSyntaxTokenKind): RawByteString;
begin
  case AKind of
    tkIdentifier: Result := 'identifier';
    tkKeyword: Result := 'keyword';
    tkNumber: Result := 'number';
    tkString: Result := 'string';
    tkSymbol: Result := 'symbol';
    tkSemicolon: Result := 'semicolon';
    tkWhitespace: Result := 'whitespace';
    tkNewline: Result := 'newline';
    tkComment: Result := 'comment';
    tkUnknown: Result := 'unknown';
    tkEof: Result := 'eof';
  end;
end;

function TSyntaxResult.AddToken(AKind: TSyntaxTokenKind; AStartByte,
  AEndByte: SizeInt; const AText: RawByteString): SizeInt;
begin
  Result := Length(FTokens);
  SetLength(FTokens, Result + 1);
  FTokens[Result].Kind := AKind;
  FTokens[Result].StartByte := AStartByte;
  FTokens[Result].EndByte := AEndByte;
  FTokens[Result].Text := AText;
end;

function TSyntaxResult.AddError(const ACode, AMessage: RawByteString;
  AStartByte, AEndByte: SizeInt): SizeInt;
begin
  Result := Length(FErrors);
  SetLength(FErrors, Result + 1);
  FErrors[Result].Code := ACode;
  FErrors[Result].Message := AMessage;
  FErrors[Result].StartByte := AStartByte;
  FErrors[Result].EndByte := AEndByte;
end;

function TSyntaxResult.AddNode(AKind: TSyntaxNodeKind; AStartByte, AEndByte,
  AFirstToken, ALastToken, AParentIndex: SizeInt;
  AIsRecovered: Boolean): SizeInt;
begin
  Result := Length(FNodes);
  SetLength(FNodes, Result + 1);
  FNodes[Result].Kind := AKind;
  FNodes[Result].StartByte := AStartByte;
  FNodes[Result].EndByte := AEndByte;
  FNodes[Result].FirstToken := AFirstToken;
  FNodes[Result].LastToken := ALastToken;
  FNodes[Result].ParentIndex := AParentIndex;
  FNodes[Result].IsRecovered := AIsRecovered;
end;

procedure TSyntaxResult.SetNode(AIndex: SizeInt; const ANode: TSyntaxNode);
begin
  FNodes[AIndex] := ANode;
end;

function TSyntaxResult.TokenCount: SizeInt;
begin
  Result := Length(FTokens);
end;

function TSyntaxResult.ErrorCount: SizeInt;
begin
  Result := Length(FErrors);
end;

function TSyntaxResult.NodeCount: SizeInt;
begin
  Result := Length(FNodes);
end;

function TSyntaxResult.Token(AIndex: SizeInt): TSyntaxToken;
begin
  if (AIndex < 0) or (AIndex >= Length(FTokens)) then
    raise ERangeError.CreateFmt('Token index %d is outside 0..%d',
      [AIndex, Length(FTokens) - 1]);
  Result := FTokens[AIndex];
end;

function TSyntaxResult.Error(AIndex: SizeInt): TSyntaxError;
begin
  if (AIndex < 0) or (AIndex >= Length(FErrors)) then
    raise ERangeError.CreateFmt('Error index %d is outside 0..%d',
      [AIndex, Length(FErrors) - 1]);
  Result := FErrors[AIndex];
end;

function TSyntaxResult.Node(AIndex: SizeInt): TSyntaxNode;
begin
  if (AIndex < 0) or (AIndex >= Length(FNodes)) then
    raise ERangeError.CreateFmt('Node index %d is outside 0..%d',
      [AIndex, Length(FNodes) - 1]);
  Result := FNodes[AIndex];
end;

function TSyntaxResult.HasErrorCode(const ACode: RawByteString): Boolean;
var
  I: SizeInt;
begin
  for I := 0 to High(FErrors) do
    if FErrors[I].Code = ACode then
      Exit(True);
  Result := False;
end;

function IsIdentifierStart(AByte: Byte): Boolean;
begin
  Result := (AByte = Ord('_')) or
    ((AByte >= Ord('A')) and (AByte <= Ord('Z'))) or
    ((AByte >= Ord('a')) and (AByte <= Ord('z'))) or
    (AByte >= $80);
end;

function IsIdentifierPart(AByte: Byte): Boolean;
begin
  Result := IsIdentifierStart(AByte) or
    ((AByte >= Ord('0')) and (AByte <= Ord('9')));
end;

function IsHexDigit(AByte: Byte): Boolean;
begin
  Result := ((AByte >= Ord('0')) and (AByte <= Ord('9'))) or
    ((AByte >= Ord('A')) and (AByte <= Ord('F'))) or
    ((AByte >= Ord('a')) and (AByte <= Ord('f')));
end;

function IsKeyword(const AText: RawByteString): Boolean;
var
  S: RawByteString;
begin
  S := LowerCase(AText);
  Result :=
    (S = 'and') or (S = 'array') or (S = 'as') or (S = 'asm') or
    (S = 'begin') or (S = 'case') or (S = 'class') or (S = 'const') or
    (S = 'constructor') or (S = 'destructor') or (S = 'div') or
    (S = 'do') or (S = 'downto') or (S = 'else') or (S = 'end') or
    (S = 'except') or (S = 'exports') or (S = 'file') or
    (S = 'finalization') or (S = 'finally') or (S = 'for') or
    (S = 'function') or (S = 'generic') or (S = 'goto') or
    (S = 'if') or (S = 'implementation') or (S = 'in') or
    (S = 'inherited') or (S = 'initialization') or (S = 'inline') or
    (S = 'interface') or (S = 'is') or (S = 'label') or
    (S = 'library') or (S = 'mod') or (S = 'nil') or (S = 'not') or
    (S = 'object') or (S = 'of') or (S = 'on') or (S = 'operator') or
    (S = 'or') or (S = 'packed') or (S = 'procedure') or
    (S = 'program') or (S = 'property') or (S = 'raise') or
    (S = 'record') or (S = 'repeat') or (S = 'resourcestring') or
    (S = 'set') or (S = 'shl') or (S = 'shr') or (S = 'specialize') or
    (S = 'then') or (S = 'threadvar') or (S = 'to') or (S = 'try') or
    (S = 'type') or (S = 'unit') or (S = 'until') or (S = 'uses') or
    (S = 'var') or (S = 'while') or (S = 'with') or (S = 'xor');
end;

procedure Lex(const ASource: RawByteString; AResult: TSyntaxResult);
var
  Offset, StartOffset, SourceLength: SizeInt;
  B: Byte;
  TokenText: RawByteString;
  Kind: TSyntaxTokenKind;
  Closed: Boolean;
begin
  Offset := 0;
  SourceLength := Length(ASource);
  while Offset < SourceLength do
  begin
    StartOffset := Offset;
    B := Ord(ASource[Offset + 1]);

    if (B = Ord(' ')) or (B = 9) then
    begin
      Inc(Offset);
      while (Offset < SourceLength) and
        ((ASource[Offset + 1] = ' ') or (ASource[Offset + 1] = #9)) do
        Inc(Offset);
      AResult.AddToken(tkWhitespace, StartOffset, Offset,
        Copy(ASource, StartOffset + 1, Offset - StartOffset));
      Continue;
    end;

    if (B = 13) or (B = 10) then
    begin
      Inc(Offset);
      if (B = 13) and (Offset < SourceLength) and
        (ASource[Offset + 1] = #10) then
        Inc(Offset);
      AResult.AddToken(tkNewline, StartOffset, Offset,
        Copy(ASource, StartOffset + 1, Offset - StartOffset));
      Continue;
    end;

    if (B = Ord('/')) and (Offset + 1 < SourceLength) and
      (ASource[Offset + 2] = '/') then
    begin
      Inc(Offset, 2);
      while (Offset < SourceLength) and
        (ASource[Offset + 1] <> #13) and (ASource[Offset + 1] <> #10) do
        Inc(Offset);
      AResult.AddToken(tkComment, StartOffset, Offset,
        Copy(ASource, StartOffset + 1, Offset - StartOffset));
      Continue;
    end;

    if B = Ord('{') then
    begin
      Inc(Offset);
      Closed := False;
      while Offset < SourceLength do
      begin
        if ASource[Offset + 1] = '}' then
        begin
          Inc(Offset);
          Closed := True;
          Break;
        end;
        Inc(Offset);
      end;
      AResult.AddToken(tkComment, StartOffset, Offset,
        Copy(ASource, StartOffset + 1, Offset - StartOffset));
      if not Closed then
        AResult.AddError('LEX002', 'Unterminated brace comment',
          StartOffset, Offset);
      Continue;
    end;

    if (B = Ord('(')) and (Offset + 1 < SourceLength) and
      (ASource[Offset + 2] = '*') then
    begin
      Inc(Offset, 2);
      Closed := False;
      while Offset < SourceLength do
      begin
        if (ASource[Offset + 1] = '*') and (Offset + 1 < SourceLength) and
          (ASource[Offset + 2] = ')') then
        begin
          Inc(Offset, 2);
          Closed := True;
          Break;
        end;
        Inc(Offset);
      end;
      AResult.AddToken(tkComment, StartOffset, Offset,
        Copy(ASource, StartOffset + 1, Offset - StartOffset));
      if not Closed then
        AResult.AddError('LEX002', 'Unterminated parenthesized comment',
          StartOffset, Offset);
      Continue;
    end;

    if B = Ord('''') then
    begin
      Inc(Offset);
      Closed := False;
      while Offset < SourceLength do
      begin
        if ASource[Offset + 1] = '''' then
        begin
          if (Offset + 1 < SourceLength) and
            (ASource[Offset + 2] = '''') then
            Inc(Offset, 2)
          else
          begin
            Inc(Offset);
            Closed := True;
            Break;
          end;
        end
        else if (ASource[Offset + 1] = #13) or
          (ASource[Offset + 1] = #10) then
          Break
        else
          Inc(Offset);
      end;
      AResult.AddToken(tkString, StartOffset, Offset,
        Copy(ASource, StartOffset + 1, Offset - StartOffset));
      if not Closed then
        AResult.AddError('LEX001', 'Unterminated string literal',
          StartOffset, Offset);
      Continue;
    end;

    if IsIdentifierStart(B) then
    begin
      Inc(Offset);
      while (Offset < SourceLength) and
        IsIdentifierPart(Ord(ASource[Offset + 1])) do
        Inc(Offset);
      TokenText := Copy(ASource, StartOffset + 1, Offset - StartOffset);
      if IsKeyword(TokenText) then
        Kind := tkKeyword
      else
        Kind := tkIdentifier;
      AResult.AddToken(Kind, StartOffset, Offset, TokenText);
      Continue;
    end;

    if ((B >= Ord('0')) and (B <= Ord('9'))) or
      ((B = Ord('$')) and (Offset + 1 < SourceLength) and
       IsHexDigit(Ord(ASource[Offset + 2]))) then
    begin
      Inc(Offset);
      while (Offset < SourceLength) and
        (IsHexDigit(Ord(ASource[Offset + 1])) or
         (ASource[Offset + 1] = '.') or (ASource[Offset + 1] = '_')) do
        Inc(Offset);
      AResult.AddToken(tkNumber, StartOffset, Offset,
        Copy(ASource, StartOffset + 1, Offset - StartOffset));
      Continue;
    end;

    if B = Ord(';') then
    begin
      Inc(Offset);
      AResult.AddToken(tkSemicolon, StartOffset, Offset, ';');
      Continue;
    end;

    if (Offset + 1 < SourceLength) and
      (((ASource[Offset + 1] = ':') and (ASource[Offset + 2] = '=')) or
       ((ASource[Offset + 1] = '<') and
        ((ASource[Offset + 2] = '=') or (ASource[Offset + 2] = '>'))) or
       ((ASource[Offset + 1] = '>') and (ASource[Offset + 2] = '=')) or
       ((ASource[Offset + 1] = '.') and (ASource[Offset + 2] = '.'))) then
    begin
      Inc(Offset, 2);
      AResult.AddToken(tkSymbol, StartOffset, Offset,
        Copy(ASource, StartOffset + 1, 2));
      Continue;
    end;

    if Char(B) in ['(', ')', '[', ']', ',', '.', ':', '=', '+', '-', '*',
      '/', '<', '>', '@', '^'] then
    begin
      Inc(Offset);
      AResult.AddToken(tkSymbol, StartOffset, Offset,
        Copy(ASource, StartOffset + 1, 1));
      Continue;
    end;

    Inc(Offset);
    AResult.AddToken(tkUnknown, StartOffset, Offset,
      Copy(ASource, StartOffset + 1, 1));
    AResult.AddError('LEX003', 'Unrecognized source byte',
      StartOffset, Offset);
  end;
  AResult.AddToken(tkEof, SourceLength, SourceLength, '');
end;

function TokenLower(const AToken: TSyntaxToken): RawByteString;
begin
  Result := LowerCase(AToken.Text);
end;

function IsTrivia(const AToken: TSyntaxToken): Boolean;
begin
  Result := AToken.Kind in [tkWhitespace, tkNewline, tkComment];
end;

function CanEndStatement(const AToken: TSyntaxToken): Boolean;
var
  S: RawByteString;
begin
  if AToken.Kind in [tkIdentifier, tkNumber, tkString] then
    Exit(True);
  if AToken.Kind = tkSymbol then
    Exit((AToken.Text = ')') or (AToken.Text = ']') or
      (AToken.Text = '^'));
  if AToken.Kind <> tkKeyword then
    Exit(False);
  S := TokenLower(AToken);
  Result := not ((S = 'and') or (S = 'as') or (S = 'begin') or
    (S = 'case') or (S = 'div') or (S = 'do') or (S = 'downto') or
    (S = 'else') or (S = 'except') or (S = 'finally') or
    (S = 'for') or (S = 'if') or (S = 'in') or (S = 'is') or
    (S = 'mod') or (S = 'not') or (S = 'of') or (S = 'on') or
    (S = 'or') or (S = 'repeat') or (S = 'shl') or (S = 'shr') or
    (S = 'then') or (S = 'to') or (S = 'try') or (S = 'until') or
    (S = 'while') or (S = 'with') or (S = 'xor'));
end;

function CanStartStatement(const AToken: TSyntaxToken): Boolean;
var
  S: RawByteString;
begin
  if AToken.Kind = tkIdentifier then
    Exit(True);
  if AToken.Kind <> tkKeyword then
    Exit(False);
  S := TokenLower(AToken);
  Result := (S = 'asm') or (S = 'begin') or (S = 'case') or
    (S = 'for') or (S = 'goto') or (S = 'if') or (S = 'inherited') or
    (S = 'raise') or (S = 'repeat') or (S = 'try') or
    (S = 'while') or (S = 'with');
end;

procedure FinishStatement(AResult: TSyntaxResult; var AFrame: TBlockFrame;
  AParentNode: SizeInt; ARecovered: Boolean);
var
  FirstToken, LastToken: TSyntaxToken;
begin
  if AFrame.StatementFirstToken < 0 then
    Exit;
  FirstToken := AResult.Token(AFrame.StatementFirstToken);
  LastToken := AResult.Token(AFrame.StatementLastToken);
  AResult.AddNode(nkStatement, FirstToken.StartByte, LastToken.EndByte,
    AFrame.StatementFirstToken, AFrame.StatementLastToken, AParentNode,
    ARecovered);
  AFrame.StatementFirstToken := -1;
  AFrame.StatementLastToken := -1;
  AFrame.SawLineBreak := False;
end;

procedure ParseTokens(const ASource: RawByteString; AResult: TSyntaxResult);
var
  Frames: array of TBlockFrame;
  I, FrameIndex, ParentNode, ClosedBeginToken: SizeInt;
  Current, BlockNode: TSyntaxNode;
  Token, Previous: TSyntaxToken;
  Frame: TBlockFrame;
  Lower: RawByteString;
begin
  SetLength(Frames, 0);
  AResult.AddNode(nkCompilationUnit, 0, Length(ASource), 0,
    AResult.TokenCount - 1, -1, False);

  for I := 0 to AResult.TokenCount - 1 do
  begin
    Token := AResult.Token(I);
    if Token.Kind = tkEof then
      Break;
    if Token.Kind = tkNewline then
    begin
      if (Length(Frames) > 0) and
        (Frames[High(Frames)].StatementFirstToken >= 0) then
        Frames[High(Frames)].SawLineBreak := True;
      Continue;
    end;
    if IsTrivia(Token) then
      Continue;

    Lower := TokenLower(Token);
    if (Token.Kind = tkKeyword) and (Lower = 'begin') then
    begin
      if Length(Frames) > 0 then
      begin
        FrameIndex := High(Frames);
        if Frames[FrameIndex].StatementFirstToken < 0 then
          Frames[FrameIndex].StatementFirstToken := I;
        Frames[FrameIndex].StatementLastToken := I;
        Frames[FrameIndex].SawLineBreak := False;
        ParentNode := Frames[FrameIndex].NodeIndex;
      end
      else
        ParentNode := 0;
      Frame.NodeIndex := AResult.AddNode(nkBeginEndBlock, Token.StartByte,
        Length(ASource), I, I, ParentNode, False);
      Frame.BeginTokenIndex := I;
      Frame.StatementFirstToken := -1;
      Frame.StatementLastToken := -1;
      Frame.SawLineBreak := False;
      SetLength(Frames, Length(Frames) + 1);
      Frames[High(Frames)] := Frame;
      Continue;
    end;

    if (Token.Kind = tkKeyword) and (Lower = 'end') then
    begin
      if Length(Frames) = 0 then
      begin
        AResult.AddError('PAR002', 'Unexpected "end" without matching "begin"',
          Token.StartByte, Token.EndByte);
        AResult.AddNode(nkMissingToken, Token.StartByte, Token.StartByte,
          I, I, 0, True);
        Continue;
      end;

      FrameIndex := High(Frames);
      FinishStatement(AResult, Frames[FrameIndex],
        Frames[FrameIndex].NodeIndex, False);
      BlockNode := AResult.Node(Frames[FrameIndex].NodeIndex);
      BlockNode.EndByte := Token.EndByte;
      BlockNode.LastToken := I;
      AResult.SetNode(Frames[FrameIndex].NodeIndex, BlockNode);
      ClosedBeginToken := Frames[FrameIndex].BeginTokenIndex;
      SetLength(Frames, Length(Frames) - 1);

      if Length(Frames) > 0 then
      begin
        FrameIndex := High(Frames);
        if Frames[FrameIndex].StatementFirstToken < 0 then
          Frames[FrameIndex].StatementFirstToken := ClosedBeginToken;
        Frames[FrameIndex].StatementLastToken := I;
        Frames[FrameIndex].SawLineBreak := False;
      end;
      Continue;
    end;

    if Token.Kind = tkSemicolon then
    begin
      if Length(Frames) > 0 then
      begin
        FrameIndex := High(Frames);
        if Frames[FrameIndex].StatementFirstToken < 0 then
          Frames[FrameIndex].StatementFirstToken := I;
        Frames[FrameIndex].StatementLastToken := I;
        FinishStatement(AResult, Frames[FrameIndex],
          Frames[FrameIndex].NodeIndex, False);
      end;
      Continue;
    end;

    if Length(Frames) = 0 then
      Continue;

    FrameIndex := High(Frames);
    if (Frames[FrameIndex].StatementFirstToken >= 0) and
      Frames[FrameIndex].SawLineBreak and CanStartStatement(Token) then
    begin
      Previous := AResult.Token(Frames[FrameIndex].StatementLastToken);
      if CanEndStatement(Previous) then
      begin
        AResult.AddError('PAR001', 'Expected ";" between statements',
          Previous.EndByte, Previous.EndByte);
        AResult.AddNode(nkMissingToken, Previous.EndByte, Previous.EndByte,
          Frames[FrameIndex].StatementLastToken,
          Frames[FrameIndex].StatementLastToken,
          Frames[FrameIndex].NodeIndex, True);
        FinishStatement(AResult, Frames[FrameIndex],
          Frames[FrameIndex].NodeIndex, True);
      end;
    end;
    if Frames[FrameIndex].StatementFirstToken < 0 then
      Frames[FrameIndex].StatementFirstToken := I;
    Frames[FrameIndex].StatementLastToken := I;
    Frames[FrameIndex].SawLineBreak := False;
  end;

  while Length(Frames) > 0 do
  begin
    FrameIndex := High(Frames);
    FinishStatement(AResult, Frames[FrameIndex],
      Frames[FrameIndex].NodeIndex, False);
    AResult.AddError('PAR003', 'Expected "end" before end of file',
      Length(ASource), Length(ASource));
    AResult.AddNode(nkMissingToken, Length(ASource), Length(ASource),
      AResult.TokenCount - 1, AResult.TokenCount - 1,
      Frames[FrameIndex].NodeIndex, True);
    Current := AResult.Node(Frames[FrameIndex].NodeIndex);
    Current.EndByte := Length(ASource);
    Current.LastToken := AResult.TokenCount - 1;
    Current.IsRecovered := True;
    AResult.SetNode(Frames[FrameIndex].NodeIndex, Current);
    SetLength(Frames, Length(Frames) - 1);
  end;
end;

function ParsePascal(const ASource: RawByteString): TSyntaxResult;
begin
  Result := TSyntaxResult.Create;
  try
    Lex(ASource, Result);
    ParseTokens(ASource, Result);
  except
    Result.Free;
    raise;
  end;
end;

end.
