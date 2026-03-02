org	0x8000			; address labels originates from here .. this is an offset, and CS is 0 at boottime
bits 	16

; **********************
; Macros
; **********************
%macro setup_interrupt 2
	mov	ax, %1
	mov	word [es:%2<<2], ax		; set offset
	mov	[es:(%2<<2)+2], cs		; set segment
%endmacro

; **********************
; Constants
; **********************
INT_DIVZERO	equ 0x00	; Division by zero interrupt vector
INT_KEYBOARD	equ 0x09	; Keyboard interrupt vector (IRQ 1)
INT_CUSTOM	equ 0x80	; Custom interrupt vector
INT_TIMER	equ 0x1c	; System timer tick interrupt vector

section .text
	cli			; clear interrupt flag

	; Debug: Print stage 2 initialized
	mov	si, msg_boot2_start
	call	print

; *********************
; IDT setup
; *********************
	mov	si, msg_idt_setup
	call	print

	setup_interrupt divisionbyzero, INT_DIVZERO
	setup_interrupt keyboard, INT_KEYBOARD
	setup_interrupt interrupt, INT_CUSTOM
	setup_interrupt timer, INT_TIMER

	mov	si, msg_idt_done
	call	print

	int	0x80			; test custom interrupt
	
	mov	si, done
	call	print
; ****************
; initialize keyboard controller (TODO)
; ****************

	mov	si, msg_interrupts_enabled
	call	print
	sti				; restore interrupts

misc:
	mov	si, prompt
	call	print

;	call	enterstring
mainloop:
	;push	done
	;call	println 	
	;jmp	mainloop
	;call	halt
halt:
	mov	si, halted
	call	print
	hlt
	jmp	halt		; loop back to "halt", needed if an exception returns with IRET
				; points to hlt + 1

%include "print.asm"

; enter string
enterstring:
	lea	di,[string]	; start by clearing string-buffer, di points to start of string
	xor	ax,ax		; sets ax = 0
	mov	cl,0		; sets cl = 0
	mov	cx,64		; cx = 64 (used by rep stosw)
	rep 	stosw		; repeat store string word (ax) 64 times a word = 128 bytes are now zero
	mov 	si,string	; string index points to string buffer
.loop:
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

.echo:				; echo char to screen
	mov	ah,0x0e		
	int	0x10		; write char to screen, advances cursor
	inc	cl		; increment di
	jmp	.loop
.sk:
	
	cmp 	ah,0x4b		; left arrow
	jz	.leftarrow
	cmp	ah,0x4d		; right arrow
	jz	.rightarrow

	mov	ah,0x0e
	int	0x10
	 ; does nothing at this point
	jmp	.loop		; enter new char...
.leftarrow:
	cmp 	cl,0		; if 2 then loop
	jz	.loop
	; test test test
	mov	dl,0
	mov	ax,1
	div	dl
	mov	[result], ax
	jmp	halt	
	dec	cl
	mov	al,0x08		; insert backspace
	mov	ah,0x0e
	int	0x10
	jmp	.loop
.rightarrow:
	push	cx
	mov	ah,0x03		; get cursor pos
	int	0x10
	inc	dl		; inc position by one
	mov	ah,0x02		; set new position
	int	0x10	
	pop	cx
	inc	cl
	jmp	.loop
.bs:
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
	mov	[si], word 0 
	dec	si
	mov	ah,0x0e
	int	0x10
	
	mov	al,0x08		; reprint backspace to screen
	mov	ah,0x0e
	int	0x10
	
	jmp	.loop

.cr0:
	mov	[si],al		; at this point al = 0x0D
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
.escape:
	int	0x80
	jmp	.loop
; *********************
; INTERRUPT HANDLERS
; *********************
interrupt:
	push	si
	mov	si, test
	call	print
	pop	si
	iret

divisionbyzero:
	push	si
	mov	si, div0
	call	print
	pop	si
	jmp	misc	

timer:
	push	si
	push	ax
	push	bx
	push	cx
	push	dx
	push	ds
	xor	ax, ax		; reset ax
	mov	ds, ax		; set ds to 0 for proper timer interrupt handling
	xor	bx, bx
	xor	dx, dx
	mov	bx, [ticks]
	inc	bx
	mov	ax, bx
	div	word [divisor]
	cmp	dx, 0
	jne	.end
	push	sched
	call	println
	pop	cx
.end:
	mov	[ticks], bx
	pop	ds
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	pop	si
	iret

keyboard:
	push	ax
	push	bx
	push	si
	in	al, 0x60		; read info from keyboard
	mov	bl, al
	cmp	bl, 0x1e		; 'A' key
	je	.a
	cmp	bl, 0x39		; 'space' key
	je	.space
	push	keydefault	
	call	println		
	pop	cx	
	jmp	.out
.a:
	push	keyb	
	call	println
	pop	ax
	jmp	.out
.space:
	int	0x80
	jmp	.out	
.out:
	mov	al, 0x20		; acknowledge to PIC (EOI - End Of Interrupt)
	out	0x20, al
	pop	si
	pop	bx
	pop	ax
	iret


crs:
	push	si
	mov	si, cr	
	call	print
	pop	si
	ret
section .data

;	ascii codes:
;	0x0d = CR (carrige return)
;	0x0a = LF (line feed)
msg_boot2_start:	db	"[BOOT2] Stage 2 initialized at 0x8000",13,10,0
msg_idt_setup:		db	"[BOOT2] Setting up interrupt handlers...",13,10,0
msg_idt_done:		db	"[BOOT2] IDT setup complete",13,10,0
msg_interrupts_enabled:	db	"[BOOT2] Interrupts enabled",13,10,0
readok:			db 	"read ok",0x0d,0x0a,0
cr:			db 	0x0d,0x0a,0
halted:			db 	"System halted",0
msg:			db 	"Hello from Brians boot-sector",0x0D,0x0A,0
msg2:			db 	"Message no. 2...",0x0D,0x0A,0
menu:			db 	"1 for enter text, q for exit",0x0d,0x0a,0
prompt:			db 	"> ",0
bell:			db	0x07,0
procedure: 		db 	0x0
test:			db	"Called from 0x80 interrupt (internal test)",13,10,0
div0:			db 	"Division by zero exception!",13,10,0
done:			db	"Interrupt done",13,10,0
result:			times 2	db	0
ticks:			dw	1
divisor:		dw	0x12	; 18
sched:			db	"Change task interrupt",13,10,0
keyb:			db	"Some key pressed",13,10,0
keydefault:		db 	"Another key pressed", 13, 10 ,0
buffer:			times	128 db 0	; string buffer

section	.bss
string:		resb	128	

