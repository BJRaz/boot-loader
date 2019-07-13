org 	0x7e00
bits 	16

start:
				; CLEAR SCREEN AND SET BACKGROUND COLOR..
	;mov	ah,0x9		; write char and attribute 
	;mov	cx,0x10		; how many times 
	;mov	al,0x42		; write char (0x42 = 'B')
	;mov	bl,0x17		; attribute 17 = 0001 0111 a.k.a background (blue), and foreground (light gray)
	;int	0x10		; interrupt 10h

	jmp	0:0x7c48

	hlt


	
