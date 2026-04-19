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
INT_DIVZERO		equ 0x00	; Division by zero interrupt vector (CPU fault 0)
INT_DEBUG		equ 0x01	; Debug exception vector 			(CPU trap/fault 1)
INT_NMI			equ 0x02	; Non-maskable interrupt vector 	(CPU NMI 2)
INT_BREAKPOINT	equ 0x03	; Breakpoint interrupt vector 		(CPU trap 3)
INT_OVERFLOW	equ 0x04	; Overflow interrupt vector 		(CPU trap 4)
INT_BOUND		equ 0x05	; BOUND range exceeded interrupt vector 	(CPU fault 5)
INT_INVALIDOP	equ 0x06	; Invalid opcode interrupt vector 	(CPU fault 6)
INT_DEVICE_NOT_AVAILABLE	equ 0x07	; Device not available interrupt vector (CPU fault 7)
INT_INTERVAL_TIMER	equ 0x08	; System timer tick interrupt vector (IRQ 0)
INT_KEYBOARD	equ 0x09	; Keyboard interrupt vector 		(IRQ 1)	
INT_CASCADE	equ 0x0a	; Cascade interrupt vector (used internally by PICs) (IRQ 2)
INT_COM2		equ 0x0b	; COM2 interrupt vector (IRQ 3)
INT_COM1		equ 0x0c	; COM1 interrupt vector (IRQ 4)
INT_LPT2		equ 0x0d	; LPT2 interrupt vector (IRQ 5)
INT_FLOPPY		equ 0x0e	; Floppy disk interrupt vector (IRQ 6)
INT_LPT1		equ 0x0f	; LPT1 interrupt vector (IRQ 7)
INT_CMOS		equ 0x70	; CMOS RTC interrupt vector (IRQ 8)
INT_FREE1		equ 0x71	; Free for peripherals (IRQ 9)
INT_FREE2		equ 0x72	; Free for peripherals (IRQ 10)
INT_FREE3		equ 0x73	; Free for peripherals (IRQ 11)
INT_MOUSE		equ 0x74	; PS/2 mouse interrupt vector (IRQ 12)
INT_FPU			equ 0x75	; FPU interrupt	vector (IRQ 13)
INT_PRIMARY_ATA	equ 0x76	; Primary ATA hard disk interrupt vector (IRQ 14)
INT_SECONDARY_ATA	equ 0x77	; Secondary ATA hard disk interrupt vector (IRQ 15)
INT_TIMER		equ 0x1c	; System timer tick interrupt vector (BIOS handler for IRQ 0)
INT_CUSTOM		equ 0x80	; Custom interrupt vector

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
	cli				; disable interrupts during setup
	; Explicitly set es=0 for safe IVT access
	xor	ax, ax
	mov	es, ax

	; Initialize 8259A PICs before setting up IVT or enabling interrupts
	call	pic_init

; *********************
; IVT setup
; *********************
	; The IVT entry for interrupt N is at physical address N*4:
	;   [N*4+0..1] = handler offset (IP)
	;   [N*4+2..3] = handler segment (CS)
	; ES is already 0 (set above) for flat IVT access.

	setup_interrupt	divisionbyzero,	INT_DIVZERO	; INT 0x00 - Division by zero (CPU fault)
	setup_interrupt	keyboard,	INT_KEYBOARD	; INT 0x09 - Keyboard (IRQ 1, master PIC)
	setup_interrupt	timer,		INT_INTERVAL_TIMER	; INT 0x08 - Timer tick (IRQ 0, hooked directly)
	setup_interrupt	interrupt,	INT_CUSTOM	; INT 0x80 - Custom software interrupt

	sti				; enable interrupts
	int	0x80			; test: call custom interrupt handler

	jmp	misc

misc:
	mov	si, prompt
	call	print
	call	ring_buffer_init

;	call	enterstring
mainloop:
	; jmp 	[process_control_table+16]	; jump to IP of first PCB (PID 0, unused)
	;push	done
	;call	println
	;jmp	mainloop
	;call	halt
halt:
	
.idle:
	jmp	halt

processtable:
	times 8 dw 0		; space for 8 process control blocks (16 bytes each)

; PROCESSES
; TEMP solution: For simplicity we just have two processes that print different characters in an infinite loop.
process1:
	push [procedure]
	push hest
	call printf 		; print -> calls BIOS int 0x10.
	; jmp	process1	; this will cause process1 to print 'H' repeatedly, never returning to main loop to allow process2 to run. We will fix this in the next stage by implementing a simple scheduler that switches between processes on timer interrupts.
	; some how exit this process and return to main loop, which will then jump to process2
	jmp halt
process2:
	mov	si, fest
	call	print
	; jmp	process2	; this will cause process2 to print 'F' repeatedly, never returning to main loop to allow process1 to run again. We will fix this in the next stage by implementing a simple scheduler that switches between processes on timer interrupts.
	jmp halt

; --------------------------------
;	Timer handler (INT 0x08 — IRQ 0, hooked directly)
;	We replace the BIOS INT 0x08 handler entirely.
;	We must send EOI to PIC1 ourselves before iret.
;
;	Stack frame on entry (16-bit real mode, iret frame pushed by CPU):
;	  [SP+0] = IP   (interrupted code)
;	  [SP+2] = CS   (interrupted code)
;	  [SP+4] = FLAGS (interrupted code)
;
;	To task-switch we rewrite IP/CS in the iret frame so that
;	iret resumes at the target process entry point.
timer:
	push	bp
	mov	bp, sp			; bp+2=IP, bp+4=CS, bp+6=FLAGS (iret frame)
	push	ax
	push	bx
	push	dx
	push	ds
	xor	ax, ax
	mov	ds, ax			; ds=0: labels are absolute from org 0x8000

	mov	bx, word [ticks]
	inc	bx
	mov	ax, bx
	xor	dx, dx
	div	word [divisor]		; dx = ticks mod 18
	test	dx, dx
	jnz	.end

	; ~1 second elapsed: switch task by rewriting the iret frame
	; Toggle current_process between 0 and 1
	mov	al, byte [current_process]
	xor	al, 1
	mov	byte [current_process], al

	; Set IP in iret frame to the target process entry point
	test	al, al
	jz	.set_p2
	mov	word [bp+2], process1	; IP = process1
	jmp	.set_cs
.set_p2:
	mov	word [bp+2], process2	; IP = process2
.set_cs:
	mov	word [bp+4], 0x0000	; CS = 0 (matches org 0x8000 flat layout)
	; FLAGS at [bp+6] preserved from interrupted context (includes IF)

.end:
	mov	word [ticks], bx
	; Send EOI to master PIC (required — we hooked INT 0x08 directly)
	mov	al, PIC_EOI
	out	PIC1_COMMAND, al
	pop	ds
	pop	dx
	pop	bx
	pop	ax
	pop	bp
	iret



%define INCLUDE_PRINTF
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
	cli
	push	si
	mov	si, test
	call	print
	pop	si
	sti
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

process_control_table: dw 0x500 	;times 8 dw 0		; space for 8 process control blocks (16 bytes each)	

;	ascii codes:
;	0x0d = CR = 13 (carriage return)
;	0x0a = LF = 10 (line feed)
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
procedure: 		dw 	0x0
test:			db	"Called from 0x80 interrupt (internal test)",13,10,0
div0:			db 	"Division by zero exception!",13,10,0
done:			db	"Interrupt done",13,10,0
result:			times 2	db	0
ticks:			dw	1
divisor:		dw	0x12	; 18
sched_flag:		db	0		; set to 1 by timer ISR, polled by main loop
current_process:	db	0		; 0 = process2 next, 1 = process1 next
sched:			db	"Change task interrupt",13,10,0
timermsg:		db	"Timer interrupt",13,10,0
keyb:			db	"Some key pressed",13,10,0
keydefault:		db 	"Another key pressed", 13, 10, 0
hest:			db	"H 0x%x",0
fest:			db	"F",0
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
