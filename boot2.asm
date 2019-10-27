org	0x8000			; address labels originates from here .. this is an offset, and CS is 0 at boottime
bits 	16

section .text
misc:
	mov	si,prompt
	call 	print

	call 	enterstring

	call 	halt

%include "print.asm"

; enter string
enterstring:
	lea	di,[string]	; start clearing string-buffer, di points to start of string
	xor	ax,ax		; sets ax = 0
	mov	cl,0		; sets di = 0
	mov	cx,64		; cx = 64 (used by rep stosw)
	rep 	stosw		; repeat store string word (ax) 64 times a word = 128 bytes are now zero
	mov 	si,string	; string index points to string buffer
.loop
	mov 	ah,0x0		; enter char (key-press), AH=scancode, AL=ASCII char
	int	0x16		; wait for key with scancode is pressed
	
	cmp	al,0x1b		; check for ESC
	jz	.escape
	
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
	inc	cl		; increment di
	jmp	.loop
.sk
	
	cmp 	ah,0x4b		; left arrow
	jz	.leftarrow
	cmp	ah,0x4d		; right arrow
	jz	.rightarrow

	mov	ah,0x0e
	int	0x10
	 ; does nothing at this point
	jmp	.loop		; enter new char...
.leftarrow
	cmp 	cl,0		; if 2 then loop
	jz	.loop
	dec	cl
	mov	al,0x08		; insert backspace
	mov	ah,0x0e
	int	0x10
	jmp	.loop
.rightarrow
	push	cx
	mov	ah,0x03		; get cursor pos
	int	0x10
	inc	dl		; inc position by one
	mov	ah,0x02		; set new position
	int	0x10	
	pop	cx
	inc	cl
	jmp	.loop
.bs
	; erase char at the left of cursor:
	; delete char from buffer
	; if cursor not at left of screen (at prompt), echo bs-char to screen otherwise sound error and do nothing
	; write chars from buffer at si to end (without moving cursor)
	cmp	cl,0
	jz	.loop
	dec 	cl
	
	mov	al,0x08		; print backspace to screen
	mov	ah,0x0e
	int	0x10
	
	mov	al,' '		; print ' ' to screen (erases char) 
	mov	ah,0x0e
	int	0x10
	
	mov	al,0x08		; reprint backspace to screen
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
	cmp	cl,0
	jz	misc	
	mov	si,string
	call 	print
	jmp	misc	
.escape
	ret

crs:
	mov	si,cr	
	call 	print
	ret
halt:
	mov	si,halted
	call 	print
	hlt

section .data

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
