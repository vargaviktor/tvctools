program crctvc;  { Creating a raw CRC from a CAS file}
{Based on the wav2ptp program by joco}
{Based on the pri2ptp program by Varga Viktor}
{Based on the ptp2pri program by Varga Viktor}
{Based on the crcprimo program by Varga Viktor}
{Programed by Viktor Varga <vargaviktor@pro.hu>}
{and Kiss K roly <k_karesz@freemail.hu>}
{The program and source is free.}
                                              
uses dos,crt;
var
      f : file;
     fo : file;
      c : char;
      s : string;
  i,j,k : integer;
      l : longint;
 casname: array[1..800] of string[32];
  cascrc: array[1..800] of longint;
    err : integer;
CVTfiles: integer;
inf,otf : string[100];
   fCRC : longint;
      b : byte;
   long : boolean;

const
     hd : array[0..15] of char='0123456789ABCDEF';

function hex(x:byte):string;
begin
     hex:=hd[x shr 4]+hd[x and 15];
end;

function bcd(x:byte):byte;
begin
     if x >99 then bcd:=0;
     bcd:= ((x div 10) shl 4) or (x mod 10);
end;

procedure msg(s:string);
begin
     inc(err);
     writeln(s);
end;

function GetByte_:byte;
var
   b : byte;
begin
Blockread(f,b,1);
GetByte_:=b;
end;

function i2s(ll:longint):string;
var
  s : string[32];
begin
 str(ll,s);
 i2s:=s;
end;

procedure Check;
var
   null,ftype, autorun: byte;
   blknum,blkmar,bsize,fsize:word;
begin
     blknum:=0;
     blkmar:=0;
     fCRC:=0;
     if Getbyte_=$11 then
     Begin
     Writeln('Valid CAS file found: ',inf);
     inc(CVTfiles,1);
     blknum:=Getbyte_ + Getbyte_ *256;
     if long then Writeln('- Full ($80) blocks in the file:   $', hex(hi(blknum)),hex(lo(blknum)),' (',blknum,')');

     blkmar:=Getbyte_+Getbyte_*256;
     if long then Writeln('- Last block size in the file:     $', hex(hi(blkmar)),hex(lo(blkmar)),' (',blkmar,')');

     bsize:=blknum*$80+blkmar;
     if long then Writeln('- Size of the blocks (calculated): $', hex(hi(bsize)),hex(lo(bsize)),' (',bsize,')');

     for i:=$06 to $81 do Null:=Getbyte_;

     Ftype:=Getbyte_;
     case Ftype of
     0 : if long then Writeln('- File type: Program file.');
     1 : if long then Writeln('- File type: Data file.')
     end;
     if (ftype<>0) and (ftype<>1) then Writeln ('! Unknown data file type.');

     Fsize:=Getbyte_*256+Getbyte_;
     if long then Writeln('- Size of the file: $', hex(hi(fsize)),hex(lo(fsize)),' (',fsize,')');

     Autorun:=Getbyte_;
     case Autorun of
       0 : if long then Writeln('- Autostarted file.');
     $ff : if long then Writeln('- Not autostarted file')
     end;
     if (autorun<>0) and (autorun<>$ff) then Writeln ('! Autorun value is not normal, but maybe valid.');

     for i:=$85 to $8f do Null:=Getbyte_;

     for i:=$90 to bsize-1 do inc(fCRC, Getbyte_);

     if filesize(f)<>fsize+144 then
     begin
     Writeln('! PC file size is different than the file size calculated from the value stored in CAS file.');
     Writeln('! PC Filesize: ',filesize(f));
     Writeln('! Stored file size +144: ',fsize+144);
     end;

     if filesize(f)<>bsize then
     begin
     Writeln('File length calculated from block size is different than the size stored in CAS file.');
     Writeln('! PC Filesize: ',filesize(f));
     Writeln('! Stored block size: ',bsize);
     end;

     Writeln('Raw CRC: ',fCRC);
     Writeln;

     CASname[CVTfiles]:=inf;
     CAScrc[CVTfiles]:=fCRC;
     end
     else begin
          Writeln(inf:12,' file isn''t a valid CAS file. Skipped...');
          end;
     close(f);

end;



procedure Checkfile;
var lng:byte;
    fln:string;
    DirInfo: SearchRec;
begin
if long then lng:=2 else lng:=1;
for k:=lng to paramcount do
begin
    fln:=paramstr(k);
    inf:='';
    FindFirst(fln, Archive, DirInfo);
    while DosError = 0 do
    begin
         inf:=DirInfo.Name;
         assign(f,inf);
         {$I-}
         reset(f,1);
         {$I+}
         if IOresult<>0 then writeln('Input file (',inf,') open error. Skipped...')
         else begin
                  {seek to 1st byte of data}
                  Seek(f,0);
                  If inf<>'STDERR.TXT' then Check;
              end;
         FindNext(DirInfo);
    end;
end; {for end}
end; {procedure end}


BEGIN
assign(output,'');
Rewrite(output);
Writeln;
CVTfiles:=0;
if paramcount > 0 then
    if paramstr(1)='-l' then long:=true else long:=false
else
    begin
    Writeln('CRCCAS  - Creating a raw CRC from a TVC .CAS file');
    writeln('USE: crccas [-l] inputfile [inputfile] [inputfile...]');
    writeln('Parameters:');
    writeln(' -l: long info with additional information');
    writeln(' inputfiles are CAS files');
    writeln('For example:');
    writeln(' crccas -l tvc1.cas tvc2.cas');
    writeln('OR');
    writeln(' crccas a*.cas');
    writeln('OR redirect output to file');
    writeln(' crccas *.cas >list.txt');
    halt;
    end;

Checkfile;
Writeln;
Writeln('Summary:');
Writeln('--------');
If CVTfiles>0 then
For i:=1 to CVTfiles do
begin
     WriteLn('File: ',CASname[i]:12,' Raw CRC: ',CAScrc[i]:8);
end;
Writeln;
Writeln('HTTP://TVC.HOMESERVER.HU');
Writeln('HTTP://TVC.8BIT.HU');
Writeln;
Writeln('Ne felejtsd elkuldeni nekunk, ha olyan');
Writeln('programod van, ami nincs a weboldalon.');
Writeln;
Writeln('Don''t forget to send us, if you have a');
Writeln('software that we have not on the website.');

close(output);
END.                            