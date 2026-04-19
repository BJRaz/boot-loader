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
	push	bp			; preserve base pointer
	mov	bp, sp			; set base pointer to current stack frame
	push	si			; preserve SI
	mov	si, [bp+4]		; get string pointer from stack
	call	print
	pop	si				; restore SI
	mov	sp, bp			; restore stack pointer
	pop	bp				; return to caller
	ret

%ifdef INCLUDE_PRINTF
	; printf: Print formatted string with %s, %c, and %x support
	; Parameters: return address, format string pointer, ... (args pushed in order)
	; Stack: [SP+0] = return address, [SP+2] = format string pointer, [SP+4+] = args
	; Clobbers: AX, BX, CX, DX, SI, DI

printf:
	push    bp
	mov     bp, sp
	push    si
	push    di

	mov     si, [bp+4]      ; SI = format string pointer
	lea     di, [bp+6]      ; DI = pointer to first argument

.next_char:
	lodsb                   ; AL = [SI], SI++
	or      al, al
	jz      .done

	cmp     al, '%'
	je      .format_spec
	cmp     al, 0x5C        ; backslash
	jne     .print_char

	; Handle escape sequence
	lodsb                   ; AL = next char after backslash
	cmp     al, 'n'
	je      .print_newline
	; Unknown escape, print backslash + char
	push    ax
	mov     ah, 0x0e
	mov     al, 0x5C        ; backslash
	int     0x10
	pop     ax
	jmp     .print_char

.print_newline:
	mov     ah, 0x0e
	mov     al, 13
	int     0x10
	mov     ah, 0x0e
	mov     al, 10
	int     0x10
	jmp     .next_char

.format_spec:
	; Handle format specifier
	lodsb                   ; AL = next char
	cmp     al, 's'
	je      .print_string
	cmp     al, 'c'
	je      .print_char_arg
	cmp     al, 'x'
	je      .print_hex
	cmp     al, 'd'
	je      .print_dec

	; Unknown specifier, just print as is
	mov     ah, 0x0e
	mov     al, '%'
	int     0x10
	mov     ah, 0x0e
	int     0x10
	jmp     .next_char

.print_string:
	mov     bx, [di]        ; get pointer to string argument
	push    si              ; preserve SI
	mov     si, bx
	call    print
	pop     si
	add     di, 2           ; advance to next argument
	jmp     .next_char

.print_char_arg:
	mov     al, [di]        ; get char argument
	mov     ah, 0x0e
	int     0x10
	inc     di              ; advance to next argument
	jmp     .next_char

.print_hex:
	mov     ax, [di]        ; get word argument to print as hex
	add     di, 2
	push    si
	mov     cx, 4           ; 4 hex digits for 16-bit value
	mov     si, hex_digits
.print_hex_loop:
	rol     ax, 4           ; high nibble to low nibble
	push    ax              ; save full rotated value
	xor     bx, bx
	mov     bl, al
	and     bl, 0x0f
	mov     al, [si + bx]
	mov     ah, 0x0e
	int     0x10
	pop     ax              ; restore rotated value (AH intact)
	loop    .print_hex_loop
	pop     si
	jmp     .next_char

.print_dec:
	mov     ax, [di]        ; get word argument
	add     di, 2
	push    si
	; Convert unsigned 16-bit AX to decimal digits on stack
	xor     cx, cx          ; digit count = 0
	mov     bx, 10
.dec_divide:
	xor     dx, dx
	div     bx              ; AX = quotient, DX = remainder
	push    dx              ; push digit (0-9)
	inc     cx
	test    ax, ax
	jnz     .dec_divide
	; Print digits from stack (most significant first)
.dec_print:
	pop     ax              ; digit value in AL
	add     al, '0'
	mov     ah, 0x0e
	int     0x10
	loop    .dec_print
	pop     si
	jmp     .next_char

.print_char:
	mov     ah, 0x0e
	int     0x10
	jmp     .next_char

.done:
	pop     di
	pop     si
	mov     sp, bp
	pop     bp
	ret

; Hex digit lookup table
hex_digits: db '0123456789ABCDEF'
%endif ; INCLUDE_PRINTF