org	0x7c00			; address labels originates from here .. this is an offset, and CS is 0 at boottime
bits 	16

; start
start:
	;int	0x03		; debug
	cli
	cld			; clear DF flag for auto-increment SI in string operations
	mov	ax,0
	;mov	cs,ax
	mov	ds,ax		; clear segment registers
	mov	ss,ax		; set stack segment other than 0 before far calls, jmps etc... 
	mov	es,ax
	mov 	fs,ax
	mov 	gs,ax

	mov	ch, 0		; show box shaped cursor..
	mov	cl, 7
	mov 	ah, 1
	int	0x10		; interrupt 10h - video services

				; CLEAR SCREEN AND SET BACKGROUND COLOR..
	mov	ah,0x9		; write char and attribute 
	mov	cx,0x1000	; how many times 
	mov	al,0x20		; write char (0x20 = space)
	mov	bl,0x17		; attribute 17 = 0001 0111 a.k.a background (blue), and foreground (light gray)
	int	0x10		; interrupt 10h - video services
	jmp	main

;.insert_char
	
	;mov	al,0x42
	;mov	cx,0x10
	;int	0x10

	;jmp 	.halt
	;jmp	.insert_char

; key-press

; DISK OPERATIONS:
; read from floppy
;	int 13h / ah = 02h	read interrupt
;	inputs:
;	al 			numbers of sectors to read
;	ch			cylinder no 	(0-79)
;	cl			sector no 	(1-18)
;	dh			head no 	(0-1)
;	dl			drive no	(0-3)
;	es:bx			data buffer
;	outputs:
;	cf			set on error
;	cf			clear if success
;	ah			status 0 if success
;	al			no of sectors transferred
;	note:			each sector = 512 bytes
;diskops:
;	mov	ah,0		; do reset on drive
;	mov	dl,0		;
;	int	0x13		;
;.readdisk
;
;	mov	ah,0x02
;	mov	al,2		; read 1 sector (512 bytes)
;	mov	ch,0		; cylinder 	no 0    
;	mov	cl,2		; sector 	no 2	(2 while bootsector is 1
;				;			and data is placed directly after bootsector)
;	mov 	dh,0		; head 		no 0
;	mov	dl,0		; drive 	no 0 (1)
;	mov	bx,0
;	mov	es,bx		; set es = 0
;	mov	bx,0x7e00	; set bx = addr. (in effect ES:BX = 0:offset)
;	int	0x13
;
;	cmp	ah,0
;	jz	.diskreadok
;
;.diskreadok
;	mov	si,readok
;	call 	print
;
;	
;	jmp	0:0x7e00	; test jump to program

.printdata
	mov	ax,0x7e00
	mov	si,ax 
	call 	print

	mov	ax,0x7e00+512
	mov 	si,ax
	call print

misc:
	call 	enterstring

;	call 	halt

	jmp 	main		; forget main at this moment

	mov 	ah,0x0		; function code 'key-press'
	int	0x16		;

	call 	enterstring

	mov 	si,string

	call 	print


	mov	si,msg		; assign si address of msg 
	
	call	print			

	mov 	si, msg2

	call 	print

	call 	halt
; ***
; Main loop
; ***

main:
	
.loop
	mov 	si,prompt	; this prints the prompt
	call	print

	jmp 	.enterstring
	mov	ah,0x0		; wait for key-press
	int	0x16
	mov	ah,0x0e		; echo entered char
	int	0x10


	cmp	al,0x31		; compare for ascii char '1'
	jz	.enterstring

	cmp	al,0x71		; compare for ascii char 'q'
	jz 	halt
	
	mov	si,cr
	call 	print
	mov	si,menu
	call 	print

	;cmp	al,0x0d		; CR
	;jz	.cr
	
	call	crs

	jmp	.loop	
.enterstring
	call 	enterstring
	mov	si,string
	call 	print
	jmp 	.loop

	jmp 	halt		; exit
; *** 
; prints chars to screen one by one until 0 has been reached
; *** 
print:	
	lodsb
	or	al,al
	jz	.out
	mov	ah,0x0E		; function code print char
	int	0x10
	jmp	print

.out
	mov	[string],ax
 	ret
; enter string
enterstring:
	lea	di,[string]	; start clearing string-buffer, di points to start of string
	xor	ax,ax		; sets ax = 0
	mov	cx,64		; cx = 64 (used by rep stosw)
	rep 	stosw		; repeat store string word (ax) 64 times a word = 128 bytes are now zero
	mov 	si,string	; string index points to string buffer
.loop
	mov 	ah,0x0		; enter char (key-press), AH=scancode, AL=ASCII char
	int	0x16		; wait for key with scancode is pressed
	
	mov	dh,ah
	mov	dl,al

	cmp	al,0x1b		; check for ESC
	jz	.exit
	cmp	al,0x08		; check for backspace
	jz	.bs
	
	cmp 	al,0x0D		; CR
	jz 	.cr0
	
	cmp	al,0x00		; special keys 
	jz	.sk

	mov	[si],al		; move char to buffer
	inc	si		; increment string index

.echo				; echo char to screen
	mov	ah,0x0e		
	int	0x10		; write char to screen, advances cursor
	jmp	.loop
.sk
	mov	ah,0x3		; get current cursor pos.
	int	0x10
	cmp	dl,2		; if 2 then loop
	jz	.loop
	dec	dl
	
	mov	ah,0x2		; set cursor pos.
	int	0x10		
	jmp	.loop		; enter new char...

.bs
	; erase char at the left of cursor:
	; delete char from buffer
	; if cursor not at left of screen (at prompt), echo bs-char to screen otherwise sound error and do nothing
	; write chars from buffer at si to end (without moving cursor)
	mov	ah,0x3		; get current cursor pos.
	int	0x10
	cmp	dl,2		; if 2 then loop
	jz	.loop
	mov	ah,0x0e
	int	0x10
	jmp	.loop
.cr0
	mov	[si],al
	inc	si
	mov	ah,0x0e
	int	0x10		; echo char
	mov 	al,0x0a		
	mov	[si],al		; add line feed
	inc	si
	mov	ah,0x0e
	int	0x10
	;jmp	.echo
.exit
	ret

crs:
	mov	si,cr	
	call 	print
	ret
halt:
	mov	si,halted
	call 	print
	hlt
;	ascii codes:
;	0x0d = CR (carrige return)
;	0x0a = LF (line feed)
readok	db "read ok",0x0d,0x0a,0
cr:	db 0x0d,0x0a,0
halted:	db "System halted",0
msg:	db "Hello from Brians boot-sector",0x0D,0x0A,0
msg2:	db "Message no. 2...",0x0D,0x0A,0
menu:	db "1 for enter text, q for exit",0x0d,0x0a,0
prompt:	db "> ",0
bell:	db 0x07,0
procedure: db 0x0

string:	times	128 db 0	; string buffer




; write zeros the first 510 (or from end of program to 510) bytes
times 	510 - ($-$$)  db 0
; magic numbers written at 511, 512 respectively (boot sector = first 512 bytes)
dw	0x55AA


