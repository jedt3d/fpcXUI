program ValidFeatures;

{$mode objfpc}{$H+}
{$ifdef FPC}

type
  generic TBox<T> = record
    Value: T;
  end;

  TIntegerHelper = type helper for Integer
    function Doubled: Integer;
  end;

function TIntegerHelper.Doubled: Integer;
begin
  Result := Self * 2;
end;

var
  Box: specialize TBox<Integer>;

begin
  Box.Value := 21;
  WriteLn(Box.Value.Doubled);
end.
{$endif}
