# tvctools
Videoton TV Computer (TVC) tape image converter (to and from wav, and a checksummer)

WAV2CAS
-------
Converts a 8 bit mono 44.1 KHz .WAV to .CAS file.
It can save only non-puffered TVC casette files, and can convert multiple files from a single WAV.
Use:
WAV2CAS file.wav speedcorrection
-file.wav: the WAV file you try to convert
-speedcorrection: value between 16 and 24 (optional) 
it is usable to correct the tape elongation
This program also checks WAV data for internal TVC ROM based CRC and structure. 

CAS2WAV
-------
This converts a .CAS TVC emulator file to WAV, which then possible to load or write back to a tape.

Use:
CAS2WAV file.cas file.wav
CAS2WAV letöltése

CRCCAS
------

Checks a file for blocks, internal CRC, and RAW CRC.

Use:
CRCCAS [-l] inputfile [inputfile] [inputfile...]

	 -inputfiles are .CAS files, also wilcard is supported
 	 -l: long info (optional)

Redirect the output to file with this: CRCCAS *.cas >example.txt

This program cheks files, for internal CRC, block structure, and generates RAW CRC.

RAW CRC is a check sum of all DATA bytes. Headings, and synchronization are not included in this checksum. If there is two version of a program and they have different size and they are not 
binary equal, these differences can come from the different block sizes. If the RAW CRC is equal, the programs are equal.
