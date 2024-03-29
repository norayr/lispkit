[INHERIT('SYS$LIBRARY:STARLET')] { FAB-related definitions }

program LispKit(Input, Output, InFile, OutFile);

(*-----------------------------------------------------------------*)
(*                                                                 *)
(*   Reference model lazy interactive SECD machine, 3              *)
(*      -- version 3a                                    April 83  *)
(*      -- IMPLODE and EXPLODE instructions, version 3b    May 83  *)
(*                                                                 *)
(*   Modifications specific to VAX VMS Pascal gaj        April 83  *)
(*   Break long lines in file output gaj                August 83  *)
(*   I/O compatible with both version 1 & 2 compilers    April 84  *)
(*                                                                 *)
(*-----------------------------------------------------------------*)
(*                                                                 *)
(*    (c)  Copyright  P Henderson, G A Jones, S B Jones            *)
(*                    Oxford University Computing Laboratory       *)
(*                    Programming Research Group                   *)
(*                    8-11 Keble Road                              *)
(*                    OXFORD  OX1 3QD                              *)
(*                                                                 *)
(*-----------------------------------------------------------------*)
(*                                                                 *)
(*   Documentation:                                                *)
(*                                                                 *)
(*     P Henderson, G A Jones, S B Jones                           *)
(*         The LispKit Manual                                      *)
(*         Oxford University Computing Laboratory                  *)
(*         Programming Research Group technical monograph PRG-32   *)
(*         Oxford, August 1983                                     *)
(*                                                                 *)
(*     P Henderson                                                 *)
(*         Functional Programming: Application and Implementation. *)
(*         Prentice-Hall International, London, 1980               *)
(*                                                                 *)
(*-----------------------------------------------------------------*)

(*------------------ Machine dependent constants ------------------*)

label 99;

const TopCell = 40000;     (*    size of heap storage    *)
      FileRecordLimit = 255;
      OutFileWidth = 200;
      OutTermWidth = 80;

(*--------------- Machine dependent file management ---------------*)

var InOpen : boolean;
    InFile : text;
    NewInput, InFromTerminal, OutToTerminal : boolean;
    OutFile : text; 
    OutFileColumn : integer;
    OutTermColumn : integer;
    NullName : packed array[1..255] of char;

function IsTerminal(VAR f : text) : boolean;
  type phyle = [UNSAFE] text;
       pointer = ^FAB$TYPE;
  var p : pointer;
      d : [UNSAFE] DEV$TYPE;
  function PAS$FAB(VAR f : phyle) : pointer; EXTERN;
begin p := PAS$FAB(f);
      d := p^.FAB$L_DEV;
      IsTerminal := d.DEV$V_TRM
end {IsTerminal};

procedure OpenInFile;
var s : packed array[1..255] of char;
begin writeln(Output);
      write(Output, 'Take input from where? ');
      if eoln(Input) then s := NullName else read(Input, s);
      readln(Input);
      if s = NullName then
        open(File_Variable := InFile,
             File_Name := 'SYS$INPUT',
             History := Old)
      else
        open(File_Variable := InFile,
             File_Name := s,
             History := Old,
             Error := CONTINUE);
      InOpen := Status(InFile) <= 0;
      if InOpen then
          begin reset(InFile); InFromTerminal := IsTerminal(InFile) end
      else write(Output, 'Cannot read from that file')
end {OpenInFile};

procedure CloseInFile; begin close(InFile); InOpen := false end;

procedure ChangeOutFile;
var s : packed array[1..255] of char;
    ok : boolean;
begin close(OutFile);
      repeat writeln(Output);
             write(Output, 'Send output to where? ');
             if eoln(Input) then s := NullName else read(Input, s);
             readln(Input);
             if s = NullName then
               open(File_Variable := OutFile,
                    File_Name := 'SYS$OUTPUT',
                    History := New,
                    Record_Length := FileRecordLimit)
             else
               open(File_Variable := OutFile,
                    File_Name := s,
                    History := New,
                    Record_Length := FileRecordLimit,
                    Error := CONTINUE);
             ok := Status(OutFile) <= 0;
             if ok then rewrite(OutFile)
             else write(Output, 'Cannot write to that file')
      until ok;
      OutToTerminal := IsTerminal(OutFile);
      OutTermColumn := 0;
      OutFileColumn := 0
end {ChangeOutFile};

(*------------------- Character input and output ------------------*)

procedure GetChar(VAR ch : char);
const EM = 8;
begin while not InOpen do begin OpenInFile; NewInput := true end;
      if eof(InFile) then begin CloseInFile; ch := ' ' end
      else
        if eoln(InFile) then
              begin readln(InFile); NewInput := true; ch := ' ' end
      else
        begin if NewInput then
                begin if InFromTerminal then OutTermColumn := 0;
                      NewInput := false
                end;
              read(InFile, ch);
              if ch = chr(EM) then
                   begin readln(InFile); ChangeOutFile; ch := ' ' end
        end;
end {GetChar};

procedure PutChar(ch : char);
const CR = 13;
begin if ch = ' '
      then if OutToTerminal then
              begin if OutTermColumn >= OutTermWidth then ch := chr(CR) end
           else
              begin if OutFileColumn >= OutFileWidth then ch := chr(CR) end;
      if ch = chr(CR) then
         begin writeln(OutFile);
               if OutToTerminal then
                     OutTermColumn := 0
               else OutFileColumn := 0
         end
      else
         begin write(OutFile, ch);
               if OutToTerminal then
                    OutTermColumn := OutTermColumn + 1
               else OutFileColumn := OutFileColumn + 1
         end
end {PutChar};

(*------- Machine dependent initialisation and finalisation -------*)

procedure Initialise(Version, SubVersion : char);
var i : 1..255;
begin writeln(Output, 'VAX Pascal SECD machine ', Version, SubVersion);
      for i := 1 to 255 do NullName[i] := ' ';
      open(File_Variable := InFile,
           File_Name := 'LISPKIT$SECDBOOT',
           History := Old,
           Error := CONTINUE);
      InOpen := status(InFile) <= 0;
      if InOpen then
             begin reset(InFile); InFromTerminal := IsTerminal(InFile) end
      else writeln(Output, 'No file LispKit$SECDboot');
      NewInput := true;
      open(File_Variable := OutFile,
           File_Name := 'SYS$OUTPUT',
           History := New,
           Record_Length := FileRecordLimit);
      rewrite(OutFile);
      OutToTerminal := IsTerminal(OutFile);
      OutTermColumn := 0;
      OutFileColumn := 0
end {Initialise};

procedure Terminate;
begin writeln(OutFile); close(OutFile); goto 99 end {Terminate};

(*--------- The code which follows is in Standard Pascal ----------*)
(*   As far as is possible, it is also machine independent.   The  *)
(*  most obvious machine dependency is that the character code of  *)
(*  the host machine has been assumed to be ISO-7 or similar.      *)
(*-----------------------------------------------------------------*)

procedure Machine;

const Version = '3';
      SubVersion = 'b';

type TokenType = (Numeric, Alpha, Delimiter);

var Marked, IsAtom, IsNumb : packed array [1..TopCell] of 0..1;
        {-----------------------------------------------}
        {       Cell type coding:   IsAtom   IsNumb     }
        {       Cons                  0         0       }
        {       Recipe                0         1       }
        {       Number                1         1       }
        {       Symbol                1         0       }
        {-----------------------------------------------}
    Head, Tail : array[1..TopCell] of integer;
        {-----------------------------------------------}
        { Head is also used for value of integer, IVAL  }
        {                       pointer to symbol, SVAL }
        {                       BODY of recipe          }
        { Tail is also used for ENVironment of recipe   }
        {-----------------------------------------------}

    S, E, C, D, W, SymbolTable : integer;
    NILL, T, F, OpenParen, Point, CloseParen : integer;
    FreeCell : integer;
    Halted : boolean;

    InCh : char;
    InTokType : TokenType;

(*------------------ Garbage collection routines ------------------*)

procedure CollectGarbage;

    procedure Mark(n : integer);
    begin if Marked[n] = 0
          then begin Marked[n] := 1;
                     if (IsAtom[n] = 0) or (IsNumb[n] = 0) then
                            begin Mark(Head[n]); Mark(Tail[n]) end
          end
    end {Mark};

    procedure MarkAccessibleStore;
    begin Mark(NILL); Mark(T); Mark(F);
          Mark(OpenParen); Mark(Point); Mark(CloseParen);
          Mark(S); Mark(E); Mark(C); Mark(D); Mark(W)
    end;

    procedure ScanSymbols(var i : integer);
    begin if i <> NILL then
                if Marked[Head[Head[i]]] = 1 then
                      begin Marked[i] := 1;
                            Marked[Head[i]] := 1;
                            ScanSymbols(Tail[i])
                      end
                else begin i := Tail[i]; ScanSymbols(i) end
    end;

    procedure ConstructFreeList;
    var i : integer;
    begin for i := 1 to TopCell do
             if Marked[i] = 0 then
                  begin Tail[i] := FreeCell; FreeCell := i end   
             else Marked[i] := 0
    end;

begin MarkAccessibleStore;
      ScanSymbols(SymbolTable);
      FreeCell := 0;
      ConstructFreeList;
      if FreeCell = 0 then
            begin writeln(Output, 'Cell store overflow'); Terminate end
end {CollectGarbage};

(*------------------ Storage allocation routines ------------------*)

function Cell : integer;
begin if FreeCell = 0 then CollectGarbage;
      Cell := FreeCell;
      FreeCell := Tail[FreeCell]
end {Cell};

function Cons : integer;
var i : integer;
begin i := Cell;
      IsAtom[i] := 0; IsNumb[i] := 0; Head[i] := NILL; Tail[i] := NILL;
      Cons := i
end {Cons};

function Recipe : integer;
var i : integer;
begin i := Cell;
      IsAtom[i] := 0; IsNumb[i] := 1; Head[i] := NILL; Tail[i] := NILL;
      Recipe := i
end {Recipe};

function Symb : integer;
var i : integer;
begin i := Cell;
      IsAtom[i] := 1; IsNumb[i] := 0; Head[i] := NILL; Tail[i] := NILL;
      Symb := i
end {Symb};

function Numb : integer;
var i : integer;
begin i := Cell;
      IsAtom[i] := 1; IsNumb[i] := 1;
      Numb := i
end {Numb};

function IsCons(i : integer) : boolean;
begin IsCons := (IsAtom[i] = 0) and (IsNumb[i] = 0) end;

function IsRecipe(i : integer) : boolean;
begin IsRecipe := (IsAtom[i] = 0) and (IsNumb[i] = 1) end;

function IsNumber(i : integer) : boolean;
begin IsNumber := (IsAtom[i] = 1) and (IsNumb[i] = 1) end;

function IsSymbol(i : integer) : boolean;
begin IsSymbol := (IsAtom[i] = 1) and (IsNumb[i] = 0) end;

function IsNill(i : integer) : boolean;
begin IsNill := IsSymbol(i) and (Head[i] = Head[NILL]) end;

procedure Store(var T : integer);
var Si, Sij, Tj : integer;
    found : boolean;
begin Tj := T;
      if IsAtom[Tj] = 1 then Tj := NILL
      else
        begin while IsAtom[Tail[Tj]] = 0 do Tj := Tail[Tj];
              Tail[Tj] := NILL
        end;
      Si := SymbolTable; found := false;
      while (not found) and (Si <> NILL) do
          begin Sij := Head[Head[Si]]; Tj := T; found := true;
                while found and (Tj <> NILL) and (Sij <> NILL) do
                   begin if Head[Tj] <> Head[Sij] then
                             if Head[Head[Tj]] = Head[Head[Sij]]
                             then Head[Tj] := Head[Sij]
                             else found := false;
                         Tj := Tail[Tj]; Sij := Tail[Sij]
                   end;
                if found then found := Tj = Sij;
                if found then T := Head[Si] else Si := Tail[Si]
          end;
      if not found then
          begin Tj := T;         (* NB: T may be an alias for W *)
                W := Cons;
                Tail[W] := Tj;
                Head[W] := Symb;
                Head[Head[W]] := Tail[W];
                Tail[W] := SymbolTable;
                SymbolTable := W;
                T := Head[W]
          end
end {Store};                                    

procedure InitListStorage;

        var i : integer;

        function List(ch : char) : integer;
        begin W := Cons;
              Head[W] := Numb; Head[Head[W]] := ord(ch);
              List := W
        end {List};

    procedure OneChar(var reg : integer; ch : char);
    begin reg := List(ch); Store(reg) end {OneChar};

begin FreeCell := 1;
      for i := 1 to TopCell - 1 do begin Marked[i] := 0; Tail[i] := i + 1 end;
      Marked[TopCell] := 0;
      Tail[TopCell] := 0;
      NILL := Symb; Head[NILL] := NILL; Tail[NILL] := NILL;
      S := NILL; E := NILL; C := NILL; D := NILL; W := NILL;
      T := NILL; F := NILL;
      OpenParen := NILL; Point := NILL; CloseParen := NILL;
      Head[NILL] := List('N');
      Tail[Head[NILL]] := List('I');
      Tail[Tail[Head[NILL]]] := List('L');
      SymbolTable := Cons;
    { Head[SymbolTable] := NILL; the symbol ...     }
    { Tail[SymbolTable] := NILL; the empty list ... }
      OneChar(T, 'T');
      OneChar(F, 'F');
      OneChar(OpenParen, '(');
      OneChar(Point, '.');
      OneChar(CloseParen, ')')
end {InitListStorage};

procedure Update(x, y : integer);
begin IsAtom[x] := IsAtom[y];
      IsNumb[x] := IsNumb[y];
      Head[x] := Head[y];
      Tail[x] := Tail[y]
end {Update};

(*--------------------- Token input and output --------------------*)

procedure GetToken(var Token : integer);
var x : char;
    p : integer;
begin while InCh = ' ' do GetChar(InCh);
      x := InCh;
      GetChar(InCh);
      if (('0' <= x) and (x <= '9'))
        or (    ((x = '-') or (x = '+'))
            and ('0' <= InCh) and (InCh <= '9')) then
              begin InTokType := Numeric;
                    Token := Numb;
                    if (x = '+') or (x = '-')
                        then Head[Token] := 0
                        else Head[Token] := ord(x) - ord('0');
                    while ('0' <= InCh) and (InCh <= '9') do
                        begin Head[Token] := (10 * Head[Token])
                                           + (ord(InCh) - ord('0'));
                              GetChar(InCh)
                        end;
                    if x = '-' then Head[Token] := - Head[Token]
              end
   else
        if (x = '(') or (x = ')') or (x = '.') then
              begin InTokType := Delimiter;
                    if x = '(' then Token := OpenParen
               else if x = '.' then Token := Point
               else Token := CloseParen
              end
   else
        begin InTokType := Alpha;
              Token := Cons; p := Token;
              Head[p] := Numb; Head[Head[p]] := ord(x);
              while not ( (InCh = '(') or (InCh = ')')
                       or (InCh = '.') or (InCh = ' ') ) do
                  begin Tail[p] := Cons; p := Tail[p];
                        Head[p] := Numb; Head[Head[p]] := ord(InCh);
                        GetChar(InCh)
                  end;
              Store(Token)
        end
end {GetToken};

procedure PutSymbol(Symbol : integer);
var p : integer;
begin p := Head[Symbol];
      while p <> NILL do begin PutChar(chr(Head[Head[p]])); p := Tail[p] end;
      PutChar(' ')
end {PutSymbol};

procedure PutNumber(Number : integer);

  procedure PutN(n : integer);
  begin if n > 9 then PutN(n div 10); PutChar(chr(ord('0') + (n mod 10))) end;

begin if Head[Number] < 0 then begin PutChar('-'); PutN(-Head[Number]) end
                          else PutN(Head[Number]);
      PutChar(' ')
end {PutNumber};

procedure PutRecipe(E : integer);
begin PutChar('*');
      PutChar('*');
      PutChar('R');
      PutChar('E');
      PutChar('C');
      PutChar('I');
      PutChar('P');
      PutChar('E');
      PutChar('*');
      PutChar('*');
      PutChar(' ')
end {PutRecipe};

(*----------------- S-expression input and output -----------------*)

procedure GetExp(var E : integer);

    procedure GetList(var E : integer);
    begin if E = CloseParen then E := NILL
          else begin W := Cons; Head[W] := E; E := W;
                     if Head[E] = OpenParen then
                         begin GetToken(Head[E]); GetList(Head[E]) end;
                     GetToken(Tail[E]);
                     if Tail[E] = Point then
                          begin GetExp(Tail[E]); GetToken(W) end
                     else GetList(Tail[E])
               end
    end {GetList};

begin GetToken(E); if E = OpenParen then begin GetToken(E); GetList(E) end
end {GetExp};

procedure PutExp(E : integer);
var p : integer;
begin if IsRecipe(E) then PutRecipe(E)
 else if IsSymbol(E) then PutSymbol(E)
 else if IsNumber(E) then PutNumber(E)
 else begin PutSymbol(OpenParen);
            p := E;
            while IsCons(p) do begin PutExp(Head[p]); p := Tail[p] end;
            if not IsNill(p) then begin PutSymbol(Point); PutExp(p) end;
            PutSymbol(CloseParen)
      end
end {PutExp};

procedure LoadBootstrapProgram;
begin InCh := ' ';
      GetExp(S);                  (* NB GetExp corrupts W *)
      E := Tail[S]; C := Head[S];
      S := NILL; D := NILL; W := NILL
end {LoadBootstrapProgram};

(*------------- Microcode for SECD machine operations -------------*)

procedure LDX;
var Wx, i : integer;
begin Wx := E;
      for i := 1 to Head[Head[Head[Tail[C]]]] do Wx := Tail[Wx];
      Wx := Head[Wx];
      for i := 1 to Head[Tail[Head[Tail[C]]]] do Wx := Tail[Wx];
      Wx := Head[Wx];
      W := Cons; Head[W] := Wx; Tail[W] := S; S := W;
      C := Tail[Tail[C]]
end {LDX};

procedure LDCX;
begin W := Cons; Head[W] := Head[Tail[C]]; Tail[W] := S; S := W;
      C := Tail[Tail[C]]
end {LDCX};

procedure LDFX;
begin W := Cons; Head[W] := Cons;
      Head[Head[W]] := Head[Tail[C]]; Tail[Head[W]] := E;
      Tail[W] := S; S := W;
      C := Tail[Tail[C]]
end {LDFX};

procedure APX;
begin W := Cons; Head[W] := Tail[Tail[S]];
      Tail[W] := Cons; Head[Tail[W]] := E;
      Tail[Tail[W]] := Cons; Head[Tail[Tail[W]]] := Tail[C];
      Tail[Tail[Tail[W]]] := D; D := W;
      W := Cons; Head[W] := Head[Tail[S]]; Tail[W] := Tail[Head[S]]; E := W;
      C := Head[Head[S]];
      S := NILL
end {APX};

procedure RTNX;
begin W := Cons; Head[W] := Head[S]; Tail[W] := Head[D]; S := W;
      E := Head[Tail[D]];
      C := Head[Tail[Tail[D]]];
      D := Tail[Tail[Tail[D]]]
end {RTNX};

procedure DUMX;
begin W := Cons; Head[W] := NILL; Tail[W] := E; E := W; C := Tail[C] end {DUMX};

procedure RAPX;
begin W := Cons; Head[W] := Tail[Tail[S]];
      Tail[W] := Cons; Head[Tail[W]] := Tail[E];
      Tail[Tail[W]] := Cons; Head[Tail[Tail[W]]] := Tail[C];
      Tail[Tail[Tail[W]]] := D; D := W;
      E := Tail[Head[S]]; Head[E] := Head[Tail[S]];
      C := Head[Head[S]];
      S := NILL
end {RAPX};

procedure SELX;
begin W := Cons; Head[W] := Tail[Tail[Tail[C]]]; Tail[W] := D; D := W;
      if Head[Head[S]] = Head[T] then C := Head[Tail[C]]
                                 else C := Head[Tail[Tail[C]]];
      S := Tail[S]
end {SELX};

procedure JOINX; begin C := Head[D]; D := Tail[D] end {JOINX};
          
procedure CARX;
begin W := Cons; Head[W] := Head[Head[S]]; Tail[W] := Tail[S]; S := W;
      C := Tail[C]
end {CARX};

procedure CDRX;
begin W := Cons; Head[W] := Tail[Head[S]]; Tail[W] := Tail[S]; S := W;
      C := Tail[C]
end {CDRX};

procedure ATOMX;
begin W := Cons;
      if IsAtom[Head[S]] = 1 then Head[W] := T else Head[W] := F;
      Tail[W] := Tail[S]; S := W;
      C := Tail[C]
end {ATOMX};

procedure CONSX;
begin W := Cons; Head[W] := Cons;
      Head[Head[W]] := Head[S]; Tail[Head[W]] := Head[Tail[S]];
      Tail[W] := Tail[Tail[S]]; S := W;
      C := Tail[C]
end {CONSX};

procedure EQX;
begin W := Cons;
      if ( ( IsSymbol(Head[S]) and IsSymbol(Head[Tail[S]]) )
        or ( IsNumber(Head[S]) and IsNumber(Head[Tail[S]]) ) )
       and (Head[Head[S]] = Head[Head[Tail[S]]])
      then Head[W] := T
      else Head[W] := F;
      Tail[W] := Tail[Tail[S]]; S := W;
      C := Tail[C]
end {EQX};

procedure ADDX;
begin W := Cons;
      Head[W] := Numb; Head[Head[W]] := Head[Head[Tail[S]]] + Head[Head[S]];
      Tail[W] := Tail[Tail[S]]; S := W;
      C := Tail[C]
end {ADDX};

procedure SUBX;
begin W := Cons;
      Head[W] := Numb; Head[Head[W]] := Head[Head[Tail[S]]] - Head[Head[S]];
      Tail[W] := Tail[Tail[S]]; S := W;
      C := Tail[C]
end {SUBX};

procedure MULX;
begin W := Cons;
      Head[W] := Numb; Head[Head[W]] := Head[Head[Tail[S]]] * Head[Head[S]];
      Tail[W] := Tail[Tail[S]]; S := W;
      C := Tail[C]
end {MULX};

procedure DIVX;
begin W := Cons;
      Head[W] := Numb; Head[Head[W]] := Head[Head[Tail[S]]] div Head[Head[S]];
      Tail[W] := Tail[Tail[S]]; S := W;
      C := Tail[C]
end {DIVX};

procedure REMX;
begin W := Cons;
      Head[W] := Numb; Head[Head[W]] := Head[Head[Tail[S]]] mod Head[Head[S]];
      Tail[W] := Tail[Tail[S]]; S := W;
      C := Tail[C]
end {REMX};

procedure LEQX;
begin W := Cons;
      if Head[Head[Tail[S]]] <= Head[Head[S]] then Head[W] := T
                                              else Head[W] := F;
      Tail[W] := Tail[Tail[S]]; S := W;
      C := Tail[C]
end {LEQX};

procedure STOPX;
begin if IsAtom[Head[S]] = 1 then Halted := true
      else begin W := Cons; Head[W] := Tail[S];
                 Tail[W] := Cons; Head[Tail[W]] := E;
                 Tail[Tail[W]] := Cons; Head[Tail[Tail[W]]] := C;
                 Tail[Tail[Tail[W]]] := D; D := W;
                 C := Head[Head[Head[S]]];
                 W := Cons;
                 Head[W] := Tail[Head[S]]; Tail[W] := Tail[Head[Head[S]]];
                 E := W;
                 S := NILL
           end
end {STOPX};

procedure LDEX;
begin W := Cons; Tail[W] := S; S := W;
      Head[W] := Recipe; Head[Head[W]] := Head[Tail[C]]; Tail[Head[W]] := E;
      C := Tail[Tail[C]]
end {LDEX};

procedure UPDX;
begin Update(Head[Head[D]],Head[S]);
      S := Head[D];
      E := Head[Tail[D]];
      C := Head[Tail[Tail[D]]];
      D := Tail[Tail[Tail[D]]]
end {UPDX};

procedure AP0X;
begin if IsRecipe(Head[S]) then
          begin W := Cons; Head[W] := S;
                Tail[W] := Cons; Head[Tail[W]] := E;
                Tail[Tail[W]] := Cons; Head[Tail[Tail[W]]] := Tail[C];
                Tail[Tail[Tail[W]]] := D; D := W;
                C := Head[Head[S]];
                E := Tail[Head[S]];
                S := NILL
          end
      else C := Tail[C]
end {AP0X};

procedure READX;
begin W := Cons; Tail[W] := S; S := W; GetExp(Head[S]); C := Tail[C] end {READX}
;

procedure PRINTX; begin PutExp(Head[S]); S := Tail[S]; C := Tail[C] end {PRINTX}
;
                          
procedure IMPLODEX;
begin W := Cons; Head[W] := Head[S]; Tail[W] := Tail[S]; S := W;
      if IsNumber(Head[S]) then
            if Head[Head[S]] = ord(' ') then Head[S] := NILL
                  else begin W := Cons; Head[W] := Head[S]; Head[S] := W end;
      Store(Head[S]);
      C := Tail[C]
end {IMPLODEX};

procedure EXPLODEX;
begin W := Cons; Head[W] := Head[Head[S]]; Tail[W] := Tail[S]; S := W;
      C := Tail[C]
end {EXPLODEX};

(*-------------------- Instruction decode loop --------------------*)

procedure FetchExecuteLoop;
label 1;
begin Halted := false;
   1: case Head[Head[C]] of
                 1:   LDX;              11:  CDRX;
                 2:  LDCX;              12: ATOMX;
                 3:  LDFX;              13: CONSX;
                 4:   APX;              14:   EQX;
                 5:  RTNX;              15:  ADDX;
                 6:  DUMX;              16:  SUBX;
                 7:  RAPX;              17:  MULX;
                 8:  SELX;              18:  DIVX;
                 9: JOINX;              19:  REMX;
                10:  CARX;              20:  LEQX;

                21: begin STOPX; if Halted then Terminate end;

                22: LDEX;               25: READX;
                23: UPDX;               26: PRINTX;
                24: AP0X;               27: IMPLODEX;
                                        28: EXPLODEX
      end;
      goto 1
end {FetchExecuteLoop};

(*------------------ body of procedure Machine --------------------*)

begin Initialise(Version, SubVersion);
      InitListStorage;
      LoadBootstrapProgram;
      FetchExecuteLoop
end {Machine};

(*------------------- body of program LispKit ---------------------*)

begin Machine; 99: end {LispKit}.
