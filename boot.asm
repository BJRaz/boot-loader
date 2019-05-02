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

	mov	si,msg		; assign si address of msg 

	call print			

	mov 	si, msg2

	call print

	jmp halt		; exit

; *** 
; prints chars to screen one by one until 0 has been reached
; *** 
print:	
	lodsb
	or	al,al
	jz	out
	mov	ah,0x0E
	int	0x10
	jmp	print

out:
 	ret

halt:	hlt

msg:	db "Hello from Brians boot-sector",0x0D,0x0A,0
msg2:	db "Message no. 2...",0x0D,0x0A,0





; write zeros the first 510 bytes
times 	510 - ($-$$)  db 0
; magic numbers written at 511, 512 respectively (boot sector = first 512 bytes)
dw	0x55AA


