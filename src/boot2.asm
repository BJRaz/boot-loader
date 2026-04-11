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

; **********************
; IO ports constants
; **********************
%define	PIC_EOI		0x20
%define PIC1_COMMAND	0x20
%define PIC2_COMMAND	0xa0
%define PIC1_DATA	0x21
%define PIC2_DATA	0xa1

; Ring buffer capacity (number of byte entries)
RB_SIZE		equ	50

section .text
	cli			; clear interrupt flag

	; Explicitly set es=0 for safe IVT access
	xor	ax, ax
	mov	es, ax

	; Initialize 8259A PICs before setting up IVT or enabling interrupts
	call	pic_init

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
	call	ring_buffer_init

;	call	enterstring
mainloop:
	;push	done
	;call	println
	;jmp	mainloop
	;call	halt
halt:
	mov	si, halted
	;call	print
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

; ************************************
; pic_init: Initialize 8259A PICs
;
; Reinitializes both PIC chips with
; the standard BIOS real-mode vector
; offsets (PIC1 -> INT 0x08..0x0f,
; PIC2 -> INT 0x70..0x77) and sets
; x86 mode.  Interrupts must be
; disabled (cli) before calling.
; ************************************
pic_init:
	; ICW1 - start init sequence, ICW4 required
	mov	al, 0x11
	out	PIC1_COMMAND, al
	out	PIC2_COMMAND, al

	; ICW2 - vector offsets (BIOS real-mode defaults)
	mov	al, 0x08	; PIC1: IRQ0-7  -> INT 0x08-0x0f
	out	PIC1_DATA, al
	mov	al, 0x70	; PIC2: IRQ8-15 -> INT 0x70-0x77
	out	PIC2_DATA, al

	; ICW3 - cascade wiring
	mov	al, 0x04	; master: slave connected to IRQ2
	out	PIC1_DATA, al
	mov	al, 0x02	; slave: cascade identity = 2
	out	PIC2_DATA, al

	; ICW4 - 8086/88 mode, normal EOI
	mov	al, 0x01
	out	PIC1_DATA, al
	out	PIC2_DATA, al

	ret

; ***********
; RING BUFFER
; ***********
;
; Circular byte buffer of RB_SIZE entries.
; rb_head: index of next write slot.
; rb_tail: index of next read slot.
; Buffer is empty when rb_head == rb_tail.
; Buffer is full when (rb_head + 1) mod RB_SIZE == rb_tail;
;   in that case the new entry is silently dropped.
;
ring_buffer_init:
	mov	[rb_head], word 0
	mov	[rb_tail], word 0
	ret

; ring_buffer_insert: append a byte to the ring buffer.
; Argument: byte value pushed on stack before call (low byte used).
ring_buffer_insert:
	push	bp
	mov	bp, sp
	push	ax
	push	bx
	push	cx
	push	dx

	; compute next_head = (rb_head + 1) mod RB_SIZE
	mov	bx, [rb_head]
	mov	ax, bx
	inc	ax
	mov	cx, RB_SIZE
	xor	dx, dx
	div	cx			; dx = remainder = next_head

	; if next_head == rb_tail the buffer is full; drop silently
	cmp	dx, [rb_tail]
	je	.done

	; store byte at current head position and advance head
	mov	al, byte [bp+4]		; low byte of argument
	mov	[rb + bx], al
	mov	[rb_head], dx		; advance head to next_head

.done:
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	pop	bp
	ret

; ring_buffer_get: remove and return the oldest byte from the ring buffer.
; Returns: al = byte value, ah = 0.  If empty, returns ax = 0.
ring_buffer_get:
	push	bx
	push	cx
	push	dx
	xor	ax, ax

	mov	bx, [rb_tail]
	cmp	bx, [rb_head]		; empty if tail == head
	je	.end

	; read byte at current tail BEFORE advancing
	mov	al, byte [rb + bx]
	push	ax			; save result

	; advance tail = (rb_tail + 1) mod RB_SIZE
	mov	ax, bx
	inc	ax
	mov	cx, RB_SIZE
	xor	dx, dx
	div	cx			; dx = new tail
	mov	[rb_tail], dx

	pop	ax			; restore read byte into ax
.end:
	pop	dx
	pop	cx
	pop	bx
	ret

; *********************
; INTERRUPT HANDLERS
; *********************

; --------------------------------
;	Custom software interrupt (0x80)
;	No PIC EOI needed: software interrupts do not use PIC in-service state.
interrupt:
	push	si
	mov	si, test
	call	print
	pop	si
	iret

; --------------------------------
;	Division By Zero Handler (CPU exception 0x00)
;	No PIC EOI needed: CPU exceptions do not drive the PIC.
divisionbyzero:
	push	si
	mov	si, div0
	call	print
	pop	si
	jmp	misc

; --------------------------------
;	Timer handler (INT 0x1c, called by BIOS INT 8 handler)
;	BIOS INT 8 already sends EOI to PIC1; no EOI needed here.
timer:
	push	si
	push	ax
	push	bx
	push	cx
	push	dx
	push	ds
	xor	ax, ax			; reset ax
	mov	ds, ax			; set ds to 0 for proper timer interrupt handling
	xor	bx, bx
	xor	dx, dx
	mov	bx, [ticks]
	inc	bx
	mov	ax, bx
	div	word [divisor]
	cmp	dx, 0
	jne	.end
	call	ring_buffer_get		; check for pending scancode
	cmp	al, 0
	je	.end
	push	si
	push	msg_rb_key		; print key indicator if scancode is pending
	call	println
	pop	cx
	pop	si
.end:
	mov	[ticks], bx
	pop	ds
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	pop	si
	iret

; --------------------------------
;	Keyboard handler (IRQ1, master PIC)
;	EOI only to PIC1 (master); keyboard is IRQ1 on the master PIC.
keyboard:
	push	ax
	push	bx
	push	si
	in	al, 0x60		; read scancode from keyboard controller
	mov	bl, al

	xor	ah, ah			; zero-extend scancode to 16 bits
	push	ax
	call	ring_buffer_insert
	pop	ax			; discard argument

	cmp	bl, 0x1e		; 'A' key scancode
	je	.a
	cmp	bl, 0x39		; 'space' key scancode
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
	mov	al, PIC_EOI		; EOI to PIC1 only (keyboard is IRQ1, master)
	out	PIC1_COMMAND, al
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
;	0x0d = CR (carriage return)
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
keydefault:		db 	"Another key pressed", 13, 10, 0
buffer:			times	128 db 0	; string buffer

; Debug string for ring buffer activity (NUL-terminated)
msg_rb_key:		db	"Key in buffer",13,10,0

; Ring buffer storage - placed after all string literals to prevent
; write-through corruption of adjacent NUL terminators.
rb:			times RB_SIZE db 0	; circular byte buffer
rb_head:		dw	0		; next write index (0..RB_SIZE-1)
rb_tail:		dw	0		; next read index  (0..RB_SIZE-1)

section	.bss
string:		resb	128
