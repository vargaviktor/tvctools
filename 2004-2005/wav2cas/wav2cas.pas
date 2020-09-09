program wav2cas;  { WAV file -> TVC CAS file }
{WAV2CAS converter
Program to convert digitized TVC tapes, to a CAS file, which is
loadable into emulators
Version 1.1
Programmed by Varga Viktor (vargaviktor@pro.hu)
Based on the converter of Laszlo Jozsef
Thanks to Kiss Karoly for some helps.
The code is freeware.

Mindefelekeppen javitani kell a tobbfajlos kiolvasast, mert amiatt hibas az egesz.

Possible upgrades:
-cleaning the code, remove unused variables
-check, that the digitizing a wave file which includes more than one
tape file (it should be wokring, but it was not checked)
maybe, the variables are not cleared before a new file.
-converting the filename included in the wav audio file to normal charset,
changing not useble ascii chars to x are not working
-it only converts non puffered files
}

uses dos,crt;

type
txtID = array[0..3] of char;

 {wav file fejlecenek felepitese -ok}
WAVhead = record
          riffID : txtID;
         riffLen : longint;
          waveID : txtID;
           fmtID : txtID;
          fmtLen : longint;
        wFormTag : word;
       nChannels : word;
   nSamplePerSec : longint;
  nAvgBytePerSec : longint;
     nBlockAlign : word;
        FormSpec : word;
          end;

{wav fajl adatteruletenek felepitese -ok}
DATAdesc = record
          dataID : txtID;
         dataLen : longint;
           end;

DATAdescPtr = ^DATAdesc;

var
      f : file;
     fo : file;
      c : char;
  sleep : integer;
      s : string;
  i,j,k,fsb,ps : integer;
      l : longint;
   head : WAVhead;
   data : DATAdesc;
   dofs : longint;
   dlen : longint;
    err,actsec : integer;
  fbuff : array[0..1023] of shortint;
  fbidx : integer;
   CCRC : word;
   feof : boolean;
   fpos : longint;
   fCRC : longint;
   flst : integer;
    inf,
    otf : string[100];

     bf : array[0..639] of shortint;

         b : byte;
     c1,c2,c3,csum : word;
    buffer : array[0..50000] of byte;
   w,q,bfl : word;
        fe : boolean;
      fact : real;
    fndTVC : boolean;
    TVCnam : string;
const

 hd : array[0..15] of char='0123456789ABCDEF';
lim : shortint = 20; {a nem vizsgalt tartomany: -lim <-> +lim}

{hexadecimalis atalakito fuggveny - ok}
function hex(x:byte):string;
begin
     hex:=hd[x shr 4]+hd[x and 15];
end;

{ID vizsgalat - ok}
function isID(id:txtID; s:string):boolean;
begin
     isID:=(id[0]=s[1])and(id[1]=s[2])and(id[2]=s[3])and(id[3]=s[4]);
end;

{byte ertek tarolasa pufferban -ok}
procedure Store(x:byte);
begin
     buffer[bfl]:=x;
     inc(bfl);
end;

{string tarolasa pufferban -ok}
procedure StoreStr(var s:string);
var
   i : integer;
begin
     if length(s)=0 then exit;
     For i:=1 to length(s) do Store(byte(s[i]));
end;

{word ertek tarolasa pufferban -ok}
procedure StoreWord(x:word);
begin
     Store(lo(x));
     Store(hi(x));
end;

function crccalc (bit:byte; hl:word):word;
var
    al: byte;
    cy: boolean;
    bx: word;
begin
    bx := hl;                { mov  bx,hl }
    if bit<>0 then al := $80  { mov  al,$80 }
    else           al := $00; { xor  al,al  }

    al := al xor (bx shr 8); { xor  al,bh  }
    cy := (al AND $80) <> 0; { rcl  al,1   }

    if (cy) then begin       { jnc  @fb0a  }
        bx := bx xor $0810;  { mov  al,bh  }
                             { xor  al,$08 }
                             { mov  bh,al  }
                             { mov  al,bl  }
                             { xor  al,$10 }
                             { mov  bl,al  }
                             { stc         }
    end;                     { @fb0a:      }
    bx := bx shl 1;          { adc  bx,bx  }
    if (cy) then inc (bx);
    crccalc := bx;           { mov  ax,bx  }
end;

{data segmens keresese a wav fileban -ok}
function seekfordata:longint;
var
 buff : array[0..1023] of byte;
    i : integer;
  cur : longint;
    d : longint;
   id : ^txtID;
begin
     d:=0;
     cur:=filepos(f);
     blockread(f,buff,1024);
     For i:=0 to 1023-4 do
     begin
          id:=Addr(buff[i]);
          if isID(id^,'data') then d:=cur+i;
     end;
     seekfordata:=d;
end;

{uzenet kiirasa fuggveny -ok}
procedure msg(s:string);
begin
     inc(err);
     WriteLn(s);
end;

{kovetkezo hang olvasasa a bufferbol -  ok}
function nextsample:shortint;
begin
     nextsample:=0;
     if feof then {exit;}
     begin
          close(f);
          WriteLn('! End of WAV file.');

          Writeln;
          Writeln('HTTP://TVC.HOMESERVER.HU');
          Writeln('HTTP://TVC.8BIT.HU');
          Writeln;
          Writeln('Ne felejtsd elkuldeni nekunk, ha olyan');
          Writeln('programod van, ami nincs a weboldalon.');
          Writeln;
          Writeln('Don''t forget to send us, if you have a');
          Writeln('software that we have not on the website.');

          Halt;
     end;
     nextsample:=fbuff[fbidx]-128;
     inc(fbidx);
     inc(fpos);
     if fbidx=flst then
     begin
          if flst<>1024 then
          begin
               feof:=true;
               exit;
          end;
          blockread(f,fbuff,1024,flst);
          fbidx:=0;
     end;
end;

{magas impulzus keresese -ok}
procedure WaitForHigh;
begin
     while nextsample<lim do;
end;

{alacsony impulzus keresese -ok}
procedure WaitForLow;
begin
     while nextsample>-lim do;
end;

{impulzus keresese - ok
hivogatja a magas es alacsony jel kereseset, es szamolgatja az
impulzusokat. ha tobb egymas utani van, es azok szama magasabb,
mint noiselim, de kisebb mint 25 akkor 0 bit, ha 14-17 hosszu, akkor 1 bit
b erteke a biteket egy bajtban, folyamatosan begorgetve tartalmazza}
procedure NextPulse;
begin
     repeat
           WaitForHigh;
           c1:=1;
           while nextsample>lim do inc(c1);
     until (25>c1);
     repeat
           WaitForLow;
           c3:=1;
     while nextsample<-lim do inc(c3);
     until (25>c3);
     csum:=c1+c3;

     if csum>=(sleep+10) then b:=0;
     b:=b shr 1;
     if csum in [sleep-6 .. sleep-3] then
     begin
          b:=b or 128; {1 bit}
          CCRC:=crcCalc(1,CCRC);
     end
     else CCRC:=crcCalc(0,CCRC)
     {sleep deafult=20}
     {if csum in [14..17] then egyesbit;}
     {if csum in [21..24] then nullabit;}
     {if csum in [18..20] then bevezeto szinkron hang;}
end;


{tiz pulzus atugrasa - a nem beallt bevezeto hang
elejenek atugrasahoz szukseges}
procedure SkipTenPulse;
begin
     For i:= 1 to 10 do Nextpulse; {10 impulzus atolvasasa}
end;

procedure SearchSyncPulse;
begin
     SkipTenPulse;
     repeat
           NextPulse;
     until csum>=sleep+10;
     WriteLn;
     WriteLn('- Sync pulse found.');
end;

{byte beolvasasa tarolas nelkul}
function GetByte_ns:byte;
var
   i : integer;
begin
     b:=0;
     For i:=0 to 7 do NextPulse;
     GetByte_ns:=b;
end;

{byte beolvasasa tarolas es crc nelkul - ok}
function GetByte_nsc:byte;
var
      i : integer;
   pCRC : word;
begin
     pCRC:=CCRC;

     b:=0;
     For i:=0 to 7 do NextPulse;
     GetByte_nsc:=b;

     CCRC:=pCRC;
end;

{byte beolvasasa tarolassal - ok}
function GetByte:byte;
begin
     GetByte:=GetByte_ns;
     Store(b);
end;

{integer ertek stringge alakitasa - ok}
function i2s(ll:longint):string;
var
  s : string[32];
begin
     str(ll,s);
     i2s:=s;
end;

procedure WriteFile(fname:string);
begin
{cas fileba kiiras}
  q:=bfl;

  bfl:=2;
  Store(lo(q div $80));  { number of $80 long blocks}
  Store(hi(q div $80));

  bfl:=4;
  Store(q mod $80);      { bytes in the last block }

  bfl:=q;

assign(fo,concat(fname,'.CAS'));
writeln('Filename: ',fname);
{$I-}
Reset(fo,1); {existing?}
if IOresult=0 then
     begin
     close(fo);
     WriteLn('File already exists. Please give another filename.');
     Readln(fname);
     assign(fo,concat(fname,'.CAS'));
     end;

ReWrite(fo,1);
     WriteLn('New file... (',fname,'.CAS)');
     if IOresult<>0 then
          begin
               WriteLn('New file creation (',fname,'.CAS) failed. Abort.');
               Close(f);
               Halt;
          end;
{$I+}
BlockWrite(fo,buffer,bfl);
Close(fo);
end;

{ sector-v‚gi crc beolvas sa, ellen‹rz‚se }
procedure CheckSectorCrc (SectorCounter: byte);
var
    CRClo, CRChi: byte;
    scrc: WORD;
begin
    CRClo:=GetByte_nsc;
    CRChi:=GetByte_nsc;
    scrc:=crchi*256+crclo;
    if ccrc<>scrc then begin
        WriteLn('! CRC error in sector:', SectorCounter);
        Writeln('! CRC waited:',ccrc,' - CRC arrived:',scrc);
    end;
end;

{fajl konvertalasa}
procedure ConvertFile;
var
       i,j : integer;
         b : byte;
      null : byte;
      sync : byte;
   TmbType : byte;
   filetyp,FileEnd,puffered,version : byte;
   ReadOnly : byte;
    NumberOfSectors,SectorCounter,filelenlo,filelenhi : byte;
       CRC,crctemp, filelen : word;

     blknum, sum : byte;
     wdata, bytsec : word;
     bdata : byte;
     fname : string[32];
    buffer : array[0..256] of byte;

begin
fndTVC:=false;
repeat
     fCRC:=0; {fCRC is cleared}

     {writing out the .cas file head structure to buffer}
              bfl:=0;
              actsec:=0;
              Store($11);     {cas file start}
              Store(0);       {Protected}
              StoreWord(0);   {block number (80h large)}
              Store(0);       {bytes in the last block}

     For i:=5 to $7f do Store(0); {fill $06-$80 with $00}
     {head structure in buffer}

repeat
     Searchsyncpulse;

     Null:=Getbyte_ns;    {null byte}
     CCRC:=0;
     Sync:=GetByte_ns;    {sync byte - always 6a}

     TmbType:=GetByte_ns; {tmb type - 00 data, ff head}
     WriteLn;
     case TmbType of
          0 : begin WriteLn('- Data block found.');fndTVC:=true; end;
        255 : begin WriteLn('- Head block found.');fndTVC:=true; end;
     else WriteLn('! Error in the program file. - tmbtype:',tmbtype)
     end;

     Puffered:=GetByte_ns; {puffered file - 01 puffered 11 nonpuffered}

     case puffered of
          1 : WriteLn('- Puffered file.');
         17 : WriteLn('- Non puffered file.');
     else WriteLn('! Error in the program file. - puffered:',puffered)
     end;

     ReadOnly:=GetByte_ns;  {readonly - 00 non protected}
     if ReadOnly=0 then WriteLn('- File is unprotected.')
     else WriteLn('- File is copy-protected.');

     NumberOfSectors:=GetByte_ns;  {sectors in the tmb}
     WriteLn('- Sectors in this block: ',NumberOfSectors);

     {secnum:=GetByte; CRC:=blknum;}
     case TmbType of
     $FF: {head tmb}
     begin
          SectorCounter:=GetByte_ns; {counter of sector - starts with 00}
          {if actsec then WriteLn('Sector no. not correct!');}

          bytsec:=GetByte_ns; {bytes in sector - 00 means 256}
          if bytsec=0 then bytsec:=256;
          {Write(bytsec,' b');}

          bdata:=GetByte_ns;
          fname[0]:=char(bdata); {file name lenght}

          For j:=1 to bdata do
          begin
               b:=GetByte_ns;
               fname[j]:=char(b);    {filename}
          end;
          WriteLn('- Filename (TVC): ',fname);

          For j:=1 to 8 do
          if ((ord(fname[j])<32) or (ord(fname[j])>128)) then fname[j]:='X';
          {filename converted to DOS compatible}
          WriteLn('- Filename (DOS): ',fname);

          Null:=Getbyte;      {00}

          filetyp:=Getbyte;   {filetype - 1 prg file, 00 -asc, xx -other}

          case filetyp of
               1 : WriteLn('- File type: Program');
               0 : WriteLn('- File type: ASCII');
          else WriteLn('- File type: Other (',hex(filetyp),')')
          end;

          filelenlo:=Getbyte; {filelenght lo/hi}
          filelenhi:=Getbyte;
          filelen:= filelenlo+filelenhi*256; {calculate tvc file lenght}
          WriteLn('- File lenght: ', filelen,' bytes.');

          For j:=0 to 10 do
          begin
               b:=Getbyte;
          end;

          version := GetByte; { never used }

          FileEnd:=GetByte_ns;  {file end? -when yes, not null}
          if FileEnd=$ff then Write('- EOF in head block - No data.');
          inc(actsec);

          CheckSectorCrc (SectorCounter);

          SkipTenpulse; {skip the last 5 and the first pulses}
          SkipTenPulse;
          SkipTenPulse;

     end;
     $00: { data tmb}
     begin
          WriteLn;

          For i:=actsec to NumberOfSectors do
          begin
              if i>1 then CCRC:=0;
              {crc not reseted when the sector is the first sector after head}

              SectorCounter:=GetByte_ns; {counter of sector - starts with 00}
              if i<>SectorCounter then WriteLn('! Sector number is invalid.');
              {WriteLn('- Data block (act/all): ',SectorCounter,'/',NumberOfSectors);}

              bytsec:=GetByte_ns; {bytes in sector - 00 means 256}
              if bytsec=0 then bytsec:=256;

              For j:=1 to bytsec do
              begin
                   b:=GetByte;
                   inc(fCRC,b); {add datbyte to fcrc}
              end;

              FileEnd:=GetByte_ns; {file end? -when yes, not null}
              if FileEnd=$FF then
                             begin
                                  WriteLn('- End of TVC file.');
                                  fndTVC:=false;
                             end;

              CheckSectorCrc (SectorCounter);
              if FileEnd=$ff then WriteFile(fname);
              if FileEnd=$ff then Writeln('Raw CRC: ',fCRC);
              {utolso szektorban ez FF a tobbiben 0}
          end;
     end;
     end;
until (FileEnd=$ff);


until fndTVC=false;
end;

{foprogram}
BEGIN
assign(output,'');
rewrite(output);

sleep:=20; {set sleep paramter to 20}

{parancsori bemeneti parameter vizsgalat25.}
 if paramcount in [1,2] then
  begin
   inf:=paramstr(1);
   if paramcount=2 then
    begin
     val(paramstr(2),i,j);
     if (j=0) and (i<25)and(i>15) then
           begin
           sleep:=i; {sleep ertek valtozatas}
           WriteLn('! Sleep value is changed to: ',sleep);
           end
        else
           Writeln('! Sleep should be between 15 and 25. It wasn''t changed.');
    end;
  end
 else
  begin
   WriteLn('USE: wav2cas inputfile [sleepvalue]');
   WriteLn('  inputfile: WAV file (8 bit mono SR=44100Hz)');
   WriteLn(' sleepvalue: with this parameter we can set the tape speed');
   Writeln('             default value is 20, if you can''t convert a tape,');
   Writeln('             maybe values between 16 and 24 are good for you.');
   Writeln('             if it doesn''t help, please check the waveform');
   Writeln;
   WriteLn('For example:');
   WriteLn('    wav2cas tvc1.wav');
   Writeln('    wav2cas tvc2.wav 19');
   Writeln;
   Writeln('If you have a wave file, you can try to make it more louder, with');
   Writeln('Freewave editor software. If it doesn''t help, please send to us.');
   halt;
  end;

{fajl hozzarendelese}
assign(f,inf);

{$I-}
reset(f,1);
{$I+}
if IOresult<>0 then
begin
     WriteLn('Input file (',inf,') open error. Abort');
     halt;
end;

{blokk olvasasa wav filebol}
blockread(f,head,sizeof(head));
err:=0;
with head do
  begin
       if not isID(riffID,'RIFF') then msg('RIFF-id not found');
       if not isID(waveID,'WAVE') then msg('WAVE-id not found');
       if not isID( fmtID,'fmt ') then msg(' fmt-id not found');
       if err=0 then WriteLn('WAVE file IDs found');
       if wFormTag<>$0001 then msg('This is not a PCM wave data');
       if nChannels<>1 then msg('This is not a MONO audio file');
       WriteLn('Sample frequency = ',nSamplePerSec);
       if FormSpec<>$0008 then msg('This is not an 8 bit audio file')
                          else WriteLn('8 bit samples, good.');
       if nSamplePerSec<>44100 then
            begin
            WriteLn('WARNING: this is not a 44100 Hz sampled WAV');
            WriteLn('Program stopped.');
            halt;
            end;
  end;

{wav adatszegmens keresese -ok}
l:=seekfordata;
if l<>0 then
     begin
     seek(f,l);
     blockread(f,data,sizeof(data));
     dofs:=l+8;
     dlen:=data.dataLen;
     WriteLn('DATA found, pos=',dofs,', length=',dlen);
     end
     else msg('DATA chunk not found in the audio file.');

if err<>0 then halt;

{ENTER vagy ESC varasa -ok}
WriteLn('Press ENTER to parse the WAV or ESC to quit');
c:=readkey;
if c<>#13 then
     begin
     close(f);
     halt;
     end;

{az elso adatbyte megkeresese a wav fileban -ok}
seek(f,dofs);
fbidx:=0;
fpos:=0;
feof:=false;
blockread(f,fbuff,1024,flst);

{tvc file convertalasa - ok}
repeat
ConvertFile;
Writeln;
Writeln('# Searching for another TVC file.');
until false;
close(output);
END.
