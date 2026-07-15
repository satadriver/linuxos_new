.386p
.model Tiny

TEMP_BUFFER_SEG			EQU 5000h
MBR_BUFFER_SEG 			EQU 6000H
NEWMBR_BUFFER_SEG 		EQU 6200H
FLAG_SECTOR_SEG			EQU 6400H
FONT_SECTOR_SEG			EQU 6600H
KERNEL_BUFFER_SEG		equ 7000h
LOADER_BUFFER_SEG 		EQU 8000H

DOS_READ_FILE_MAX		EQU 8000H

SETUP_SECTOR_LIMIT		EQU 0ffffffffH

INSTALL_FLAG			EQU 00474a4ch

BAKMBR_SECTOR_OFFSET	EQU 1
BAKMBR2_SECTOR_OFFSET	EQU 2
FONT_SECTOR_OFFSET		EQU 3
LOADER_SECTOR_OFFSET	EQU 5

SECTOR_SIZE				equ 512



code segment para use16
assume cs:code

start:
mov ax,0b800h
mov fs,ax
mov gs,ax

;find empty sectors,fat12 or fat16,fat32
mov dword ptr cs:[freesecno],80000h		;2^9 * 2 ^ 20 = 2^29 = 512M
jmp __FindPrevOS

__ReadDiskBlock:
cmp dword ptr cs:[freesecno],SETUP_SECTOR_LIMIT
jae __NoFreeSector

mov eax,TEMP_BUFFER_SEG
mov ecx,128
mov edx,dword ptr cs:[freesecno]
call __readSector

inc dword ptr cs:[freesecno]

mov ax,TEMP_BUFFER_SEG
mov ds,ax
mov eax,dword ptr ds:[0]
cmp eax,INSTALL_FLAG
jnz _checkSectors

mov word ptr cs:[installedTag],1
jmp __FindPrevOS

_checkSectors:
cld
mov ecx,4000h
mov esi,0
mov ax,TEMP_BUFFER_SEG
mov ds,ax
_checkDwordZero:
lodsd
cmp eax,0
jnz __ReadDiskBlock
loop _checkDwordZero

__FindPrevOS:
mov eax,cs:[freesecno]
lea ecx,sectorNumber
call __i2strhex
mov ax,cs
mov ds,ax
mov ax,900h
lea dx,showFirstSector
int 21h

;read files
lea ax,mbr_filename
mov dx,NEWMBR_BUFFER_SEG
call __readWholeFile
mov dword ptr cs:[newmbrfs],eax

lea ax,loader_fn
mov dx,LOADER_BUFFER_SEG
call __readWholeFile
mov dword ptr cs:[loaderfs],eax

lea ax,kernel_fn
mov dx,KERNEL_BUFFER_SEG
call __readWholeFile
mov dword ptr cs:[kernelfs],eax

lea ax,font_fn
mov dx,FONT_SECTOR_SEG
call __readWholeFile
mov dword ptr cs:[fontfs],eax

mov word ptr fs:[160],3131h

;make first info sector
MOV ax,FLAG_SECTOR_SEG
mov es,ax
mov al,'L'
mov byte ptr es:[0],al
mov al,'J'
mov byte ptr es:[1],al
mov al,'G'
mov byte ptr es:[2],al
mov al,0
mov byte ptr es:[3],al

mov eax,dword ptr cs:[loaderfs]
call __fs2SectorTotal
mov word ptr es:[4],ax
mov word ptr cs:[loadersc],ax
mov eax,dword ptr cs:[freesecno]
add eax,LOADER_SECTOR_OFFSET
mov dword ptr es:[6],eax

mov eax,dword ptr cs:[kernelfs]
call __fs2SectorTotal
mov word ptr es:[10],ax
mov word ptr cs:[kernelsc],ax
movzx eax,word ptr es:[4]
add eax,dword ptr es:[ 6]
mov dword ptr es:[12],eax
mov cs:[kernelsn],eax

mov eax,cs:[freesecno]
add eax,BAKMBR_SECTOR_OFFSET
mov dword ptr es:[ 16],eax
mov eax,cs:[freesecno]
add eax,BAKMBR2_SECTOR_OFFSET
mov dword ptr es:[ 20],eax

mov eax,cs:[freesecno]
add eax,FONT_SECTOR_OFFSET
mov dword ptr es:[ 26],eax
mov eax,2
mov word ptr es:[ 24],ax

mov word ptr fs:[320],3232h

movzx edi,word ptr es:[ 24]
mov eax,dword ptr es:[ 26]
add edi,eax
mov dword ptr es:[32],edi
lea ax,kerneldll_fn
mov dx,TEMP_BUFFER_SEG
call __readWriteFile
mov dword ptr cs:[kerneldllfs],eax
call __fs2SectorTotal
mov word ptr cs:[kerneldllsc],ax
mov word ptr es:[ 30],ax

mov edi,dword ptr es:[ 32]
movzx eax,word ptr es:[ 30]
add edi,eax
mov dword ptr es:[ 38],edi
lea ax,maindll_fn
mov dx,TEMP_BUFFER_SEG
call __readWriteFile
mov dword ptr cs:[maindllfs],eax
call __fs2SectorTotal
mov word ptr cs:[maindllsc],ax
mov word ptr es:[ 36],ax

mov word ptr fs:[480],3333h

;write info sector
mov eax,FLAG_SECTOR_SEG
mov ecx,1
mov edx,cs:[freesecno]
call __writeSector

;read mbr
mov eax,MBR_BUFFER_SEG
mov ecx,1
mov edx,0
call __readSector

cmp word ptr cs:[installedTag],0
jnz _skipWriteNewMbr

;write mbr into bak
mov eax,MBR_BUFFER_SEG
mov ecx,1
mov edx,cs:[freesecno]
add edx,BAKMBR_SECTOR_OFFSET
call __writeSector

;write mbr into bak2
mov eax,MBR_BUFFER_SEG
mov ecx,1
mov edx,cs:[freesecno]
add edx,BAKMBR2_SECTOR_OFFSET
call __writeSector

;copy hpt and write my mbr into mbr
mov ax,NEWMBR_BUFFER_SEG
mov es,ax
mov ax,MBR_BUFFER_SEG
mov ds,ax
mov edi,1bah
mov eax,cs:[freesecno]
cld
stosd
mov esi,1beh
mov ecx,66
rep movsb

mov eax,NEWMBR_BUFFER_SEG
mov ecx,1
mov edx,0
call __writeSector

_skipWriteNewMbr:

mov word ptr fs:[640],3434h

;write font into sectors
mov eax,FONT_SECTOR_SEG
mov ecx,2
mov edx,cs:[freesecno]
add edx,FONT_SECTOR_OFFSET
call __writeSector

;write loader into sectors
mov eax,LOADER_BUFFER_SEG
movzx ecx,cs:[loadersc]
mov edx,cs:[freesecno]
add edx,LOADER_SECTOR_OFFSET
call __writeSector

;write kernel into sectors
mov eax,KERNEL_BUFFER_SEG
movzx ecx,cs:[kernelsc]
mov edx,cs:[kernelsn]
call __writeSector

mov ax,cs
mov ds,ax
mov ax,900h
lea dx ,completeMsg
int 21h
MOV AH,4CH
INT 21H

__NoFreeSector:
mov ax,cs
mov ds,ax
mov ax,900h
lea dx ,noFreeSectorErr
int 21h
MOV AH,4CH
INT 21H



; ax:filename
; dx:seg
; edi: sector offset
__readWriteFile proc 
push ebp
mov ebp,esp

push bx
push si
push di
push ds
push es

sub esp,100h

mov word ptr ss:[ebp - 20h],dx
mov dword ptr ss:[ebp - 24h],edi

mov dx,ax

mov ax,cs
mov ds,ax
;al = 0:read,al = 3:read/write, al=1:write
mov ax,3d00h
int 21h
cmp ax,0
jbe _readWriteFileError

mov cs:[handle],ax
mov bx,ax
;al = 0:front,al = 2:end, al=1:current
mov ax,4202h
mov cx,0
mov dx,0
int 21h
mov cs:[filesize],ax
mov cs:[fileSizeHigh],dx

mov ax,4200h
mov bx,cs:[handle]
mov cx,0
mov dx,0
int 21h

mov ax,word ptr ss:[ebp - 20h]
mov ds,ax

movzx ecx,word ptr cs:[fileSizeHigh]
shl ecx,16
mov cx,cs:[filesize]
mov dword ptr ss:[ebp - 28h],ecx

mov dword ptr ss:[ebp - 2ch],0

cmp ecx,DOS_READ_FILE_MAX
jb _readFileLeast
__readFileBlock:
push ecx
push ds

mov ax,3f00h
mov dx,0
mov bx,cs:[handle]
mov cx,DOS_READ_FILE_MAX
int 21h

add dword ptr ss:[ebp - 2ch],DOS_READ_FILE_MAX

mov byte ptr cs:[patlen],10h
mov byte ptr cs:[reserved],0
mov ax,40h
mov word ptr cs:[seccnt],ax
xor eax,eax
mov ax,ds
shl eax,16
mov ax,0
mov cs:[segoff],eax
mov eax,dword ptr ss:[ebp - 24h]
add dword ptr ss:[ebp - 24h],40h
mov dword ptr cs:[secofflow],eax
mov dword ptr cs:[secoffhigh] ,0
mov ax,cs
mov ds,ax
lea si,patlen
mov ah,43h
mov al,0
mov dx,80h
int 13h

mov eax,dword ptr ss:[ebp - 2ch]
lea ecx,progressdb
call __i2strhex
mov ax,900h
lea dx,showProgress
int 21h
pop ds

pop ecx
sub ecx,DOS_READ_FILE_MAX
cmp ecx,DOS_READ_FILE_MAX
jg __readFileBlock
jz __closeFileHandle

mov dword ptr ss:[ebp - 28h],ecx

_readFileLeast:
mov ax,3f00h
mov dx,0
mov ecx,dword ptr ss:[ebp - 28h]
add dword ptr ss:[ebp - 2ch],ecx
mov bx,cs:[handle]
int 21h

push ds
mov eax,dword ptr ss:[ebp - 28h]
call __fs2SectorTotal
mov word ptr cs:[seccnt],ax
mov byte ptr cs:[patlen],10h
mov byte ptr cs:[reserved],0
mov eax,0
mov ax,ds
shl eax,16
mov ax,0
mov cs:[segoff],eax
mov eax,dword ptr ss:[ebp - 24h]
add dword ptr ss:[ebp - 24h],40h
mov dword ptr cs:[secofflow],eax
mov dword ptr cs:[secoffhigh] ,0
mov ax,cs
mov ds,ax
lea si,patlen
mov ah,43h
mov al,0
mov dx,80h
int 13h

mov eax,dword ptr ss:[ebp - 2ch]
lea ecx,progressdb
call __i2strhex
mov ax,900h
lea dx,showProgress
int 21h
pop ds

__closeFileHandle:
mov ax,3e00h
mov bx,cs:[handle]
int 21h

movzx eax,word ptr cs:[fileSizeHigh]
shl eax,16
mov ax,cs:[filesize]

add esp,100h
pop es
pop ds
pop di
pop si
pop bx
mov esp,ebp
pop ebp
ret

_readWriteFileError:
mov ax,cs
mov ds,ax
mov ax,900h
lea dx ,writeFileErr
int 21h
MOV AH,4CH
INT 21H
ret
__readWriteFile endp




__fs2SectorTotal proc
mov edx,0
mov ecx,SECTOR_SIZE
div ecx
cmp edx,0
jz _fsAligned
inc eax
_fsAligned:
ret
__fs2SectorTotal endp



;eax:seg
;ecx:sector count
;edx:sec offset
__writeSector proc
push bx
push si
push di
push ds
push es

mov byte ptr cs:[patlen],10h
mov byte ptr cs:[reserved],0
mov word ptr cs:[seccnt],cx
shl eax,16
mov ax,0
mov cs:[segoff],eax

mov dword ptr cs:[secofflow],edx
mov dword ptr cs:[secoffhigh] ,0
mov ax,cs
mov ds,ax
lea si,patlen
mov ah,43h
mov al,0
mov dx,80h
int 13h
cmp ah,0
jnz _w_sector_err

pop es
pop ds
pop di
pop si
pop bx
ret

_w_sector_err:
mov ax,cs
mov ds,ax
mov ax,900h
lea dx ,rwSectorErr
int 21h
MOV AH,4CH
INT 21H
__writeSector endp



;eax:seg
;edx:sec offset
;ecx:sector count
__readSector proc
push bx
push si
push di
push ds
push es

mov byte ptr cs:[patlen],10h
mov byte ptr cs:[reserved],0
mov word ptr cs:[seccnt],cx
shl eax,16
mov ax,0
mov cs:[segoff],eax

mov dword ptr cs:[secofflow],edx
mov dword ptr cs:[secoffhigh] ,0
mov ax,cs
mov ds,ax
lea si,patlen
mov ah,42h
mov al,0
mov dx,80h
int 13h
cmp ah,0
jnz _r_sector_err

pop es
pop ds
pop di
pop si
pop bx
ret

_r_sector_err:
mov ax,cs
mov ds,ax
mov ax,900h
lea dx ,rwSectorErr
int 21h
MOV AH,4CH
INT 21H
__readSector endp




; ax: filename
; dx: read buffer seg
__readWholeFile proc near
push bx
push si
push di
push ds
push es

mov si,dx
mov dx,ax

mov ax,cs
mov ds,ax

;al = 0:read,al = 3:read/write, al=1:write
mov ax,3d00h
int 21h
cmp ax,0
jbe _readWholeFileError

mov cs:[handle],ax
mov bx,ax
;al = 0:front,al = 2:end, al=1:current
mov ax,4202h
mov cx,0
mov dx,0
int 21h
mov cs:[filesize],ax
mov cs:[fileSizeHigh],dx

mov ax,4200h
mov bx,cs:[handle]
mov cx,0
mov dx,0
int 21h

mov ax,si
mov ds,ax

mov ax,3f00h
mov bx,cs:[handle]
mov cx,cs:[filesize]
mov dx,0
int 21h

mov ax,3e00h
mov bx,cs:[handle]
int 21h

movzx eax,cs:[fileSizeHigh]
shl eax,16
mov ax,word ptr cs:[filesize]

pop es
pop ds
pop di
pop si
pop bx
ret

_readWholeFileError:
mov ax,cs
mov ds,ax
mov ax,900h
lea dx ,readFileErr
int 21h
MOV AH,4CH
INT 21H
__readWholeFile endp



__ch2strhex proc  near
cmp al,9
jae _ch2str
add al,30h
ret
_ch2str:
add al,55
ret 
__ch2strhex endp

;eax: value
;ecx: format buffer
__i2strhex proc near
push ebx

mov ebx,ecx

mov edx,eax
shr eax,28
and al,0fh
call __ch2strhex
mov byte ptr cs:[ebx],al

mov eax,edx
shr eax,24
and al,0fh
call __ch2strhex
mov byte ptr cs:[ebx+1],al

mov eax,edx
shr eax,20
and al,0fh
call __ch2strhex
mov byte ptr cs:[ebx+2],al

mov eax,edx
shr eax,16
and al,0fh
call __ch2strhex
mov byte ptr cs:[ebx+3],al

mov eax,edx
shr eax,12
and al,0fh
call __ch2strhex
mov byte ptr cs:[ebx+4],al

mov eax,edx
shr eax,8
and al,0fh
call __ch2strhex
mov byte ptr cs:[ebx+5],al

mov eax,edx
shr eax,4
and al,0fh
call __ch2strhex
mov byte ptr cs:[ebx+6],al

mov eax,edx
shr eax,0
and al,0fh
call __ch2strhex
mov byte ptr cs:[ebx+7],al

pop ebx
ret
__i2strhex endp

freesecno		dd 0

installedTag	dw 0

newmbrfs		dd 0

fontfs			dd 0
fontsc			dw 0

kernelsn		dd 0
kernelsc		dw 0
kernelfs		dd 0

loadersc		dw 0
loaderfs		dd 0

kerneldllsc		dw 0
kerneldllfs		dd 0

maindllsc		dw 0
maindllfs		dd 0

handle 			dw 0
fileSizeHigh	dw 0
filesize 		dw 0

mbr_filename 	db 'mbr.com',0
loader_fn		db 'loader.com',0
kernel_fn		db 'kernel.exe',0
font_fn			db 'font.db',0
kerneldll_fn	db 'kernel.dll',0
maindll_fn		db 'main.dll',0

flagstr 		db 'LJG',0

completeMsg		db 'Install LIUNUXOS complete!$',0dh,0ah,'$',0
readFileErr		db 'read file error$',0dh,0ah,'$',0
writeFileErr	db 'write file error$',0dh,0ah,'$',0
noFreeSectorErr db 'not enough space on disk,more free sectors needed!$',0dh,0ah,'$',0
rwSectorErr		db 'read or write sector error!$',0dh,0ah,'$',0

showFirstSector	db 'Get first free sector number:0x'
sectorNumber	db 8 dup (0)
				db 0dh,0ah,'$',0


showProgress	db 'read/write file data:0x'
progressdb		db 8 dup (0)
				db 0dh,0ah,'$',0

align 		16
patlen 		db 0
reserved 	db 0
seccnt 		dw 0
segoff		dd 0
secofflow 	dd 0
secoffhigh 	dd 0

code ends

end start