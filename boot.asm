org	0x7c00
bits 	16

; start
start:
	cli
	cld			; clear DF flag for auto-increment SI in string operations
	mov	ax,0
	;mov	cs,ax
	mov	ds,ax		; clear segment registers
	mov	ss,ax
	mov	es,ax
	mov 	fs,ax
	mov 	gs,ax

	mov	ch, 0		; show box shaped cursor..
	mov	cl, 7
	mov 	ah, 1
	int	0x10
				; CLEAR SCREEN AND SET BACKGROUND COLOR..
	mov	ah,0x9		; write char and attribute 
	mov	cx,0x1000	; how many times 
	mov	al,0x20		; write char (0x20 = space)
	mov	bl,0x17		; attribute 17 = 0001 0111 a.k.a background (blue), and foreground (light gray)
	int	0x10		; interrupt 10h

	;jmp	main

;.insert_char
	
	;mov	al,0x42
	;mov	cx,0x10
	;int	0x10

	;jmp 	.halt
	;jmp	.insert_char

; key-press
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
reset:
; 				do reset on drive
	mov	ah,0
	mov	dl,0
	int	0x13
readdisk:

	mov	ah,0x02
	mov	al,2		; read 1 sector (512 bytes)
	mov	ch,0		; cylinder 	no 0    
	mov	cl,2		; sector 	no 2	(2 while bootsector is 1
				;			and data is placed directly after bootsector)
	mov 	dh,0		; head 		no 0
	mov	dl,0		; drive 	no 0 (1)
	mov	bx,0
	mov	es,bx		; set es = 0
	mov	bx,0x7e00	
	int	0x13

	cmp	ah,0
	jz	ok

ok:
	mov	si,readok
	call 	print

	mov	ax,0x7e00
	mov	si,ax
	call 	print

	mov	ax,0x7e00+512
	mov 	si,ax
	call print

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
 	ret
; enter string
enterstring:
	mov 	si,string
.loop
	mov 	ah,0x0		; enter char (key-press)
	int	0x16
	
	cmp	al,0x1b		; check for ESC
	jz	.exit
	
	cmp 	al,0x0D		; CR
	jz 	.cr0
.write
	mov	[si],al
	inc	si

	mov	ah,0x0e
	int	0x10

	jmp	.loop
.cr0
	mov	[si],al
	inc	si
	mov	ah,0x0e
	int	0x10
	mov	al,0x0a
	jmp	.write	
.exit
	ret

crs:
	mov	si,cr	
	call 	print
	ret
halt:
	;jmp	0x7e00	
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

string:	times	128 db 0	; string buffer




; write zeros the first 510 bytes
times 	510 - ($-$$)  db 0
; magic numbers written at 511, 512 respectively (boot sector = first 512 bytes)
dw	0x55AA


