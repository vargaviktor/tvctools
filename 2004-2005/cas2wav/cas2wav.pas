program cas2wav;
{
CAS2WAV
Program to convert TVC emulator files (CAS) to WAV.
It is transferable after back to the original computer.
Version 1.1
The code is freeware.

Programmed by Varga Viktor (vargaviktor@pro.hu
Based on the converter of Laszlo Jozsef
Thanks to Kiss Karoly for some help.
}

type
  mymem = array[0..65520] of byte;
 pmymem = ^mymem;

const

hd : array[0..15] of char='0123456789ABCDEF';

  SILENCE = $80;
 POS_PEAK = $f8;
 NEG_PEAK = $08;


 bt1 : array[0..15] of byte=(POS_PEAK,POS_PEAK,POS_PEAK,POS_PEAK,
                             POS_PEAK,POS_PEAK,POS_PEAK,POS_PEAK,
                             NEG_PEAK,NEG_PEAK,NEG_PEAK,NEG_PEAK,
                             NEG_PEAK,NEG_PEAK,NEG_PEAK,NEG_PEAK);

 bt0 : array[0..21] of byte=(POS_PEAK,POS_PEAK,POS_PEAK,POS_PEAK,
                             POS_PEAK,POS_PEAK,POS_PEAK,POS_PEAK,
                             POS_PEAK,POS_PEAK,POS_PEAK,
                             NEG_PEAK,NEG_PEAK,NEG_PEAK,NEG_PEAK,
                             NEG_PEAK,NEG_PEAK,NEG_PEAK,NEG_PEAK,
                             NEG_PEAK,NEG_PEAK,NEG_PEAK);

 pre : array[0..17] of byte=(POS_PEAK,POS_PEAK,POS_PEAK,POS_PEAK,
                             POS_PEAK,POS_PEAK,POS_PEAK,POS_PEAK,
                             POS_PEAK,
                             NEG_PEAK,NEG_PEAK,NEG_PEAK,NEG_PEAK,
                             NEG_PEAK,NEG_PEAK,NEG_PEAK,NEG_PEAK,
                             NEG_PEAK);

 syn : array[0..33] of byte=(POS_PEAK,POS_PEAK,POS_PEAK,POS_PEAK,
                             POS_PEAK,POS_PEAK,POS_PEAK,POS_PEAK,
                             POS_PEAK,POS_PEAK,POS_PEAK,POS_PEAK,
                             POS_PEAK,POS_PEAK,POS_PEAK,POS_PEAK,POS_PEAK,
                             NEG_PEAK,NEG_PEAK,NEG_PEAK,NEG_PEAK,
                             NEG_PEAK,NEG_PEAK,NEG_PEAK,NEG_PEAK,
                             NEG_PEAK,NEG_PEAK,NEG_PEAK,NEG_PEAK,
                             NEG_PEAK,NEG_PEAK,NEG_PEAK,NEG_PEAK,NEG_PEAK);

{
 wavheader, 44 bajt, mono 44100 Hz-es wav fajl fejlec


 TVC "0" bit, 552 usec: 11 high 11 low
 TVC "1" bit, 388 usec: 8 high 8 low

 TVC pre sound, 470 usec, 9 high 9 low
 TVC syncrone, 736 usec, 14 hig 14 low
 -this was change to longer (16-16) to be comaptible with wav2cas

 TVC Headblock
 0) 2 sec silence
 1) 10240 pre sound
 2) 1 syncrone
 3) Head data
 4) 5 pre sound

 TVC Datablock
 0) 1 sec silence
 1) 5120 pre sound
 2) 1 syncrone
 3) Data data
 4) 5 pre sound

 1 sec silence =  44100 silence


}

var

  infile : file;
 outfile : file;
  wrtcnt : longint;
   pfind : 0..65520;
   bl_id : byte;
   bl_sz : word;
   bl_nr : word;
    perr : byte;
     whd : pointer;
    CCRC : word;
   zCRC, TCRC,dfsize,lof : word;
    lofname,bihs: integer;
    tvcname: string;
      vnum: byte;
    secnum: byte;
    typecas,casauto :byte;
    sizecas: word;

   inbuff : pmymem;

{$L wavhead.obj}
procedure wavheader; external;
{a fajlokban a $40 $1f (22khz) kicserelsre kerultet $44 $ac (44,1khz)}

{hexadecimalis atalakito fuggveny - ok}
function hex(x:byte):string;
begin
     hex:=hd[x shr 4]+hd[x and 15];
end;

{crc szamito rutin -direkt forditas - ok
z=0 v 1; hl=word}
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

procedure msg (s:string);
begin
 writeln(s);
 inc(perr);
end;

procedure write_tvc_silence;
var
 bf : array[0..11025] of byte;
begin
 if perr<>0 then exit;

 writeln('- writing 1 sec silence');

 fillchar(bf,sizeof(bf),SILENCE);
 blockwrite(outfile,bf,sizeof(bf)); {1 sec}
 blockwrite(outfile,bf,sizeof(bf));

 inc(wrtcnt,sizeof(bf));
 inc(wrtcnt,sizeof(bf));
end;


procedure write_bit(bt:byte);
begin
 case (bt and 1) of
 0:
   begin
    blockwrite(outfile,bt0,sizeof(bt0));
    inc(wrtcnt,sizeof(bt0));
    CCRC:=crcCalc(0,CCRC);
   end;
 1:
   begin
    blockwrite(outfile,bt1,sizeof(bt1));
    inc(wrtcnt,sizeof(bt1));
    CCRC:=crcCalc(1,CCRC);
   end;
 end;
end;

procedure write_pre(db:integer);
var i:integer;
begin
writeln('- writing out ',db,' intro/after pulses');
for i:=1 to db do
    begin
         blockwrite(outfile,pre,sizeof(pre));
         inc(wrtcnt,sizeof(pre));
    end;
end;

procedure write_tvc_syncrone;
begin
     blockwrite(outfile,syn,sizeof(syn));
     inc(wrtcnt,sizeof(syn));

end;

procedure write_byte(b:byte);
var
   x,i : byte;
begin
 x:=b;
 for i:=0 to 7 do
  begin

   write_bit(x);
   x:=x shr 1;
  end;
end;

procedure write_word(w:word);
begin
 write_byte(lo(w));
 write_byte(hi(w));
end;

procedure write_string(s:string);
var
   i : byte;
begin
 for i:=1 to length(s) do write_byte(ord(s[i]));
end;

procedure write_tvc_headpre;
begin
write_pre(10240);
end;

procedure write_tvc_datapre;
begin
write_pre(5120);
end;

procedure write_tvc_after;
begin
write_pre(5);
end;

function  get_next:byte;
begin
 get_next:=inbuff^[pfind];
 inc(pfind);
end;

function getbyte:byte;
var b:byte;
begin
 blockread(infile, b,1);
 getbyte:=b;
end;

procedure write_tvc_headblock;
var
   i: integer;
   zCRC: word;
begin

write_tvc_silence;
write_tvc_silence;

writeln;
writeln('= head block writing =');

write_tvc_headpre;

write_tvc_syncrone;

Write_byte(0);
CCRC:=0;          {clear calculated CRC}
write_byte($6a);
Writeln('- $00 $6A - standard start bytes');

write_byte($ff); {head tmb}
Writeln('- $FF - head tmb');

write_byte($11); {non puffered}
Writeln('- $11 - non puffered file');

write_byte(0);   {non writeprotected}
Writeln('- $00 - non writeprotected');

write_byte(1);   {1 sector in this tmb}
Writeln('- $01 - one sector in the head');

write_byte(secnum);   {sector number =0}
Writeln('- $',hex(secnum),' - sectornumber');

lofname:=length(tvcname);
bihs:=1+lofname+16;
lof:=dfsize;
{dont know why, but it is needed to create a good file size into the wav
if a wav2cas a file back, it is a difference}

write_byte(bihs); {bytes in this sector}
Writeln('- $',hex(bihs),' - bytes in head');

write_byte(lofname);
Writeln('- $',hex(lofname),' - length of filename');

write_string(tvcname);
Writeln('- "',tvcname,'" - filename in wav');

write_byte(0);
Writeln('- $00 - standard fill byte');

write_byte(typecas);
Writeln('- $',hex(typecas),' - file type');
write_word(lof);
Writeln('- $',hex(hi(lof)),hex(lo(lof)),'- length of file');

write_byte($00); {not autostarted}
Writeln('- $00 - program file is not autostarting');

for i:=6 to 15 do write_byte(0);
Writeln('- $00 .. $00 -standard filling bytes');
vnum:=0;
write_byte(vnum);
Writeln('- tvc file version number: $',hex(vnum));
write_byte($00); {not last sector}
Writeln('- $00 - this is not the last sector');
zCRC := CCRC;
write_byte(lo(zCRC));
write_byte(hi(zCRC));
write_tvc_after;
end;

procedure write_tvc_datahead;
var
   i: integer;
begin
write_tvc_silence;

writeln;
writeln('= data block head =');

write_tvc_datapre;
write_tvc_syncrone;

write_byte(0);
CCRC:=0;
write_byte($6a);
Writeln('- $00 $6A - standard start bytes');

write_byte(0); {data tmb}
Writeln('- $00 - data tmb');

write_byte($11); {non puffered}
Writeln('- $11 - non puffered file');

write_byte(0);   {non writeprotected}
Writeln('- $00 - non write protected');

write_byte((dfsize div 256)+1);   {sector in this tmb}
Writeln('- $',hex(((dfsize div 256)+1)),' - number of sectors in this tmb');
writeln;
end;

procedure write_tvc_datasec(size:byte);
var
   h,l : word;
   i : word;
begin
 if perr<>0 then exit;
 if secnum>1 then CCRC:=0;
 write_byte(secnum);
 write_byte(size);
 if size=0 then
           begin
                for i:=0 to 255 do write_byte(get_next);
                write_byte($00);

           end
 else
           begin
                for i:=0 to size-1 do write_byte(get_next);
                write_byte($ff);
           end;
 zCRC := CCRC;
 write_byte(lo(zCRC));
 write_byte(hi(zCRC));
end;

procedure write_tvc_file;
var
        b,bl,bh,bsl,bsh,brl,brh: byte;
        l : word;
        i,j : integer;
begin
 new(inbuff);

 perr:=0;

 b:=getbyte; {file id, must be $11}
 if b<>$11 then msg('! File ID error');
 b:=getbyte; { $00 - ignore }

 bsl := getbyte;
 bsh := getbyte;
 brl := getbyte;
 brh := getbyte;
 dfsize:=(bsl+bsh*256)*128 + (brl+brh*256);
 {cant get the real size, bu this is working, i dont understand why}
 Writeln('- Size stored at the start of CAS file: ',dfsize);
{file size from $80 blocks plus modulus}

 for i:=$05 to $7f do b:=getbyte;
 {seeking to $80}


 writeln('- File size stored at the head of the CAS file: $',hex(hi(dfsize)),hex(lo(dfsize)),' (',dfsize,')');
 dec(dfsize,$90);
{ inc(dfsize,30); }
 writeln('- Tape data bytes in CAS file, without header (-$90): $',hex(hi(dfsize)),hex(lo(dfsize)),' (',dfsize,')');
 writeln;

 typecas:=getbyte;
 writeln('- Casette type stored in CAS header: $',hex(typecas));
 bl := getbyte;
 bh := getbyte;
 sizecas:=bh*256+bl;
 writeln('- Casette size stored in CAS header: $',hex(hi(sizecas)),hex(lo(sizecas)),' (',sizecas,')');
 casauto:=getbyte;
 writeln('- Autostart byte stored in CAS header: $',hex(casauto));

 for i:=$85 to $8F do b:=getbyte;

 blockread(infile,inbuff^,dfsize); {read the entire tvc file (all databytes) }
 pfind:=0;

 secnum:=0;

 write_tvc_headblock;

 write_tvc_datahead;


 writeln;
 writeln('= data sectors =');

 secnum:=1;
 write_tvc_datasec(0); {first datasectors CRC includes head data CRC}
 writeln('- $',hex(secnum),' data sector writing.');

 for secnum:=2 to (dfsize div 256) do
 begin
      writeln('- $',hex(secnum),' data sector writing.');
      {writing out the full data sectors}
      write_tvc_datasec(0);
 end;

 {writing out the last data sector}
 inc(secnum,1);

 write_tvc_datasec(dfsize mod 256);
 writeln('- $',hex(secnum),' last, not full length data sector writing.');

 write_tvc_after; {putting out the last five signal}
 write_tvc_silence;
 write_tvc_silence;

 writeln;
 writeln('FILE write done. ($',hex(secnum),' (',secnum,') sectors)');

 dispose(inbuff);
end;

BEGIN

assign(output,'');
rewrite(output);

 wrtcnt:=0;
 if paramcount<2 then
  begin
   Writeln('TVC CAS file to WAV converter.');
   writeln('USE: cas2wav CAS-file WAV-file [-n]');
   Writeln;
   Writeln('     CAS-file: TVC emulator file');
   Writeln('     Wav-file: destination file');
   Writeln('     -n : you can specify the filename stored in WAV');
   Writeln;
   halt;
  end;

 assign( infile,paramstr(1));
 assign(outfile,paramstr(2));

 if paramstr(3)='-n' then begin
 Write('Please give the file name stored in the Wav file>');
 Readln(tvcname);
 tvcname:=Copy(tvcname,1,16);
 end
 else
 tvcname:=Copy(paramstr(2),1,(length(paramstr(2))-4));

 perr:=0;
 {$I-}
 reset(infile,1);
 if IOresult<>0 then msg('Input file open error');
 rewrite(outfile,1);
 if IOresult<>0 then msg('Output file creation error');
 {$I+}

 if perr<>0 then halt;

 whd:=@wavheader;
 blockwrite(outfile,whd^,44);

 wrtcnt:=0;

 write_tvc_file;

 Writeln('Writed pulses:',wrtcnt);
 Writeln('WAV file size should be:', wrtcnt+44);
 { correct wav size parameters }
 seek(outfile,40);
 blockwrite(outfile,wrtcnt,4); { data field size }
 seek(outfile,4);
 inc(wrtcnt,$24);
 blockwrite(outfile,wrtcnt,4); { RIFF field size }

 close(infile);
 close(outfile);

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
END. of program
