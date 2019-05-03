org	0x7c00
bits 	16

; start
start:
	cli
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
;.insert_char
	
	;mov	al,0x42
	;mov	cx,0x10
	;int	0x10

	;jmp 	.halt
	;jmp	.insert_char

; key-press

	jmp 	main

	mov 	ah,0x0		; function code 'key-press'
	int	0x16		;

	call 	enterstring

	mov 	si,string

	call 	print


	mov	si,msg		; assign si address of msg 
	
	call	print			

	mov 	si, msg2

	call 	print
; ***
; Main loop
; ***

main:
	
.loop
	mov 	si,prompt
	call	print

	mov	ah,0x0		; key-press
	int	0x16
	; echo char
	mov	ah,0x0e
	int	0x10


	cmp	al,0x31		; compare for 1
	jz	.enterstring

	cmp	al,0x71		; compare for 'q'
	jz 	halt
	
	mov	si,cr
	call 	print
	mov	si,menu
	call 	print

	;cmp	al,0x0d		; CR
	;jz	.cr
	
	jmp	.cr

	;jmp	.loop	
.enterstring
	call 	enterstring
	mov	si,string
	call 	print
	jmp 	.loop

	jmp 	halt		; exit
.cr
	mov	si,cr	
	call 	print
	jmp	.loop
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
	
	cmp	al,0x0d		; check for CR
	jz	.exit

	mov	[si],al
	inc	si

	mov	ah,0x0e
	int	0x10

	jmp	.loop
.exit
	ret
	
halt:	
	mov	si,halted
	call 	print
	hlt

cr:	db 0x0d,0x0a,0
halted:	db "System halted",0
msg:	db "Hello from Brians boot-sector",0x0D,0x0A,0
msg2:	db "Message no. 2...",0x0D,0x0A,0
menu:	db "1 for enter text, q for exit",0x0d,0x0a,0
prompt:	db ">",0

string:	times	16 db 0	; string buffer




; write zeros the first 510 bytes
times 	510 - ($-$$)  db 0
; magic numbers written at 511, 512 respectively (boot sector = first 512 bytes)
dw	0x55AA


