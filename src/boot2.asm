org	0x8000			; address labels originates from here .. this is an offset, and CS is 0 at boottime
bits 	16

%include "constants.asm"
%include "interrupts.asm"
%include "pic.asm"
%include "pcb.asm"

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

	; fall through to main initialization
misc:
	mov	si, prompt
	call	print
	call	ring_buffer_init

	; Initialize process table
	call	pcb_init

halt:
.idle:
	hlt			; low-power idle; timer IRQ wakes us
	jmp	halt

; **********************
; pcb_init: set up PCB entries for process 0 and process 1
; **********************
pcb_init:
	; Process 0: process1 entry point
	mov	si, proc_table
	mov	byte  [si + PCB_STATE], 1	; ready
	mov	word  [si + PCB_IP],    process1
	mov	word  [si + PCB_CS],    0x0000
	mov	word  [si + PCB_FLAGS], 0x0202	; IF set
	mov	word  [si + PCB_SP],    PROC0_STACK_TOP
	mov	word  [si + PCB_SS],    0x0000
	mov	word  [si + PCB_AX],    0
	mov	word  [si + PCB_BX],    0
	mov	word  [si + PCB_CX],    0
	mov	word  [si + PCB_DX],    0
	mov	word  [si + PCB_SI],    0
	mov	word  [si + PCB_DI],    0
	mov	word  [si + PCB_BP],    PROC0_STACK_TOP
	mov	word  [si + PCB_DS],    0x0000
	mov	word  [si + PCB_ES],    0x0000

	; Process 1: process2 entry point
	add	si, PCB_SIZE
	mov	byte  [si + PCB_STATE], 1	; ready
	mov	word  [si + PCB_IP],    process2
	mov	word  [si + PCB_CS],    0x0000
	mov	word  [si + PCB_FLAGS], 0x0202	; IF set
	mov	word  [si + PCB_SP],    PROC1_STACK_TOP
	mov	word  [si + PCB_SS],    0x0000
	mov	word  [si + PCB_AX],    0
	mov	word  [si + PCB_BX],    0
	mov	word  [si + PCB_CX],    0
	mov	word  [si + PCB_DX],    0
	mov	word  [si + PCB_SI],    0
	mov	word  [si + PCB_DI],    0
	mov	word  [si + PCB_BP],    PROC1_STACK_TOP
	mov	word  [si + PCB_DS],    0x0000
	mov	word  [si + PCB_ES],    0x0000

	; 0xFF = sentinel: no process running yet, first switch loads process 0
	mov	byte [current_process], 0xFF
	ret

; **********************
; PROCESSES
; Each process prints once then halts. The timer always resets
; IP and SP to the entry point when switching in, so the process
; runs fresh each time-slice (~1 second).
; **********************
process1:
	mov	si, hest
	call	print
.idle:
	hlt
	jmp	.idle

process2:
	mov	si, fest
	call	print
.idle:
	hlt
	jmp	.idle

; --------------------------------
;	Timer handler (INT 0x08 — IRQ 0, hooked directly)
;
;	On entry the CPU pushed:  [SP]=IP  [SP+2]=CS  [SP+4]=FLAGS
;
;	Strategy: push ALL registers immediately so nothing is lost,
;	then save from known stack positions into the current PCB.
timer:
	; ---- Save every register ----
	push	ax
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	bp
	push	ds
	push	es

	; DS = 0 so we can access our data labels
	xor	ax, ax
	mov	ds, ax

	; ---- Tick counter ----
	mov	bx, word [ticks]
	inc	bx
	mov	word [ticks], bx
	mov	ax, bx
	xor	dx, dx
	div	word [divisor]		; dx = ticks mod 18
	test	dx, dx
	jnz	.no_switch

	; =====================================================
	; Context switch
	; =====================================================
	mov	bp, sp			; BP = base of our saved-register frame

	; Check if this is the first switch (sentinel 0xFF = idle, no save)
	cmp	byte [current_process], 0xFF
	je	.first_switch

	; ---- Compute pointer to current PCB in SI ----
	xor	ah, ah
	mov	al, byte [current_process]
	mov	bl, PCB_SIZE
	mul	bl			; AX = index * PCB_SIZE  (DX safe: 8-bit mul)
	add	ax, proc_table
	mov	si, ax

	; ---- Save interrupted context from stack into current PCB ----
	mov	ax, [bp + STK_AX]
	mov	word [si + PCB_AX], ax
	mov	ax, [bp + STK_BX]
	mov	word [si + PCB_BX], ax
	mov	ax, [bp + STK_CX]
	mov	word [si + PCB_CX], ax
	mov	ax, [bp + STK_DX]
	mov	word [si + PCB_DX], ax
	mov	ax, [bp + STK_SI]
	mov	word [si + PCB_SI], ax
	mov	ax, [bp + STK_DI]
	mov	word [si + PCB_DI], ax
	mov	ax, [bp + STK_BP]
	mov	word [si + PCB_BP], ax
	mov	ax, [bp + STK_DS]
	mov	word [si + PCB_DS], ax
	mov	ax, [bp + STK_ES]
	mov	word [si + PCB_ES], ax

	; Save iret frame
	mov	ax, [bp + STK_IP]
	mov	word [si + PCB_IP], ax
	mov	ax, [bp + STK_CS]
	mov	word [si + PCB_CS], ax
	mov	ax, [bp + STK_FLAGS]
	mov	word [si + PCB_FLAGS], ax

	; Save interrupted SP: original SP before CPU pushed iret frame
	mov	ax, bp
	add	ax, STK_FRAME		; skip our 9 pushes + 3 iret words
	mov	word [si + PCB_SP], ax
	mov	ax, ss
	mov	word [si + PCB_SS], ax

	mov	byte [si + PCB_STATE], 1	; mark old process as ready

	; ---- Select next process (round-robin) ----
	mov	al, byte [current_process]
	xor	al, 1
	mov	byte [current_process], al
	jmp	.load_process

.first_switch:
	; First switch from idle: load process 0, don't save idle context
	mov	byte [current_process], 0
	mov	al, 0

.load_process:
	; ---- Compute pointer to next PCB in SI ----
	xor	ah, ah
	mov	bl, PCB_SIZE
	mul	bl
	add	ax, proc_table
	mov	si, ax

	mov	byte [si + PCB_STATE], 2	; mark new process as running

	; Reset IP and SP to entry point so the process starts fresh
	; Process 0 entry = process1, Process 1 entry = process2
	mov	al, byte [current_process]
	test	al, al
	jnz	.load_p1
	mov	word [si + PCB_IP], process1
	mov	word [si + PCB_SP], PROC0_STACK_TOP
	mov	word [si + PCB_BP], PROC0_STACK_TOP
	jmp	.do_load
.load_p1:
	mov	word [si + PCB_IP], process2
	mov	word [si + PCB_SP], PROC1_STACK_TOP
	mov	word [si + PCB_BP], PROC1_STACK_TOP
.do_load:

	; ---- Switch to new process's stack ----
	; Set SS:SP to the saved values, then push an iret frame + regs
	mov	ax, [si + PCB_SS]
	mov	ss, ax
	mov	sp, [si + PCB_SP]

	; Build iret frame on new stack
	push	word [si + PCB_FLAGS]
	push	word [si + PCB_CS]
	push	word [si + PCB_IP]

	; Build register frame on new stack (same order as our pushes)
	push	word [si + PCB_AX]
	push	word [si + PCB_BX]
	push	word [si + PCB_CX]
	push	word [si + PCB_DX]
	; SI must be pushed before we lose the PCB pointer
	push	word [si + PCB_SI]
	push	word [si + PCB_DI]
	push	word [si + PCB_BP]
	push	word [si + PCB_DS]
	push	word [si + PCB_ES]

	; ---- Send EOI before restoring regs ----
	mov	al, PIC_EOI
	out	PIC1_COMMAND, al

	; ---- Restore all registers and iret ----
	pop	es
	pop	ds
	pop	bp
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	iret

.no_switch:
	; No context switch — just send EOI and return
	mov	al, PIC_EOI
	out	PIC1_COMMAND, al
	pop	es
	pop	ds
	pop	bp
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax
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

; **********************
; Strings
; **********************
cr:			db	0x0d,0x0a,0
prompt:			db	"> ",0
test:			db	"Called from 0x80 interrupt (internal test)",13,10,0
div0:			db	"Division by zero exception!",13,10,0
keyb:			db	"Some key pressed",13,10,0
keydefault:		db	"Another key pressed",13,10,0
hest:			db	"[P1] Hello from process 1",13,10,0
fest:			db	"[P2] Hello from process 2",13,10,0

; **********************
; Scheduler state
; **********************
ticks:			dw	1
divisor:		dw	0x12		; 18 (~18.2 ticks/sec)
current_process:	db	0		; index of running process (0 or 1); 0xFF = idle sentinel

; Process table: NUM_PROCS entries of PCB_SIZE bytes each
proc_table:		times (NUM_PROCS * PCB_SIZE) db 0

; **********************
; Ring buffer storage
; Placed after string literals to prevent write-through corruption.
; **********************
rb:			times RB_SIZE db 0
rb_head:		dw	0
rb_tail:		dw	0

; **********************
; Used by enterstring (kept for future use)
; **********************
result:			dw	0

section	.bss
string:		resb	128
