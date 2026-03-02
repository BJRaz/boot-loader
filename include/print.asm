; ***
; prints chars to screen one by one until 0 has been reached
; ***
; reads a byte buffer pointed to by SI, and if not 0 (zero)
; prints to screen and continues
; Preserves: AX (except AL which gets loaded from buffer)
; Note: This is a low-level routine, register preservation is minimal by design

print:	
	lodsb				; load [SI] into AL, increment SI
	or	al, al			; test if AL is zero
	jz	.out
	mov	ah, 0x0e		; function code: print char
	int	0x10			; BIOS video interrupt
	jmp	print
.out:
	ret

; println: Print string with parameters passed on stack
; Parameters: return address, string pointer (2 bytes, offset from stack)
; Stack: [SP+0] = return address, [SP+2] = string pointer

println:
	push	bp
	mov	bp, sp
	push	si			; preserve SI
	mov	si, [bp+4]		; get string pointer from stack
	call	print
	pop	si			; restore SI
	mov	sp, bp
	pop	bp
	ret
