; *** 
; prints chars to screen one by one until 0 has been reached
; *** 
; reads a byte buffer pointed to by SI, and if not 0 (zero)
; prints to screen and continues

print:	
	lodsb
	or	al,al
	jz	.out
	mov	ah,0x0e		; function code print char
	int	0x10
	jmp	print
.out:
 	ret
	
println:
	push	word bp
	mov 	bp, sp
	push	si
	mov	si, [bp+4]
	call	print

	pop	si
	mov	sp, bp
	pop	word bp
	ret
