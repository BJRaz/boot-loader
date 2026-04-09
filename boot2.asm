org	0x8000			; address labels originates from here .. this is an offset, and CS is 0 at boottime
bits 	16			; sets 16 bit mode

%define	PIC_EOI			0x20
%define PIC1_COMMAND		0x20
%define PIC2_COMMAND		0xa0
%define PIC1_DATA		0x21
%define PIC2_DATA		0xa1

section .text
	cli			; clear interrupt flag

	; Explicitly set es=0 for safe IVT access
	xor	ax, ax
	mov	es, ax

	; Initialize 8259A PICs before enabling any interrupts
	call	pic_init

; *********************
; IVT setup
; *********************
	; Note:
	;	The PC bios normally maps the IRQ0-IRQ7 to an offset of 8 
	;	relative to the interrupt vector table (int 0x8 - int 0x0f), and the IRQ8-IRQ15 to an offset
	;	of 112 (int 70 - int int 77)
	;
	;	The index is multiplied by four, as the IVT has entries of 2 * 16bits (4 bytes)
	;	The index is mapped as an offset:segment starting from 0
	;
	
	mov	ax, divisionbyzero
	mov	[es:0x0<<2], ax		; add interrupt routine for division by zero 
	mov	[es:(0x0<<2)+2], cs	; internal intel mapped interrupt, index 0x0
					;  - , index 0x1 is not mapped
					;  - , index 0x2 is not mapped
					;  - , index 0x3 is not mapped
					;  - , index 0x4 is not mapped
					;  - , index 0x5 is not mapped
					;  - , index 0x6 is not mapped
					;  - , index 0x7 is not mapped
					; IRQ0, index 0x08: 	PIT
	mov	ax, keyboard 
	mov	[es:0x9*4],ax		; keyboard routine 
	mov	[es:0x9*4+2], cs	; IRQ1, index 0x09: 	Keyboard 
					; IRQ2, index 0xa:	8259A slave
					; IRQ3, index 0xb:	COM2 / COM4
					; IRQ4, index 0xc:	COM1 / COM3
					; IRQ5, index 0xd:	LPT2
					; IRQ6, index 0xe:	Floppy Controller
					; IRQ7, index 0xf:	LPT1
				
					; IRQ8, index 0x70:	RTC
					;  
					;
					;
	mov	ax, mouse		; IRQ12, index 0x74:	Mouse
	mov	[es:0x74*4], ax
	mov	[es:0x74*4+2],cs	

					; IRQ13, index 0x75:  	Math Coprocessor
					; IRQ14, index 0x76:	HDD controller 1
					; IRQ15, index 0x77:	HDD controller 2
	;mov	ax,timer		; (for scheduler)
	;mov	word [es:0x1c<<2], ax	; timer routine; 'listens' to timer ticks called from (irq 8) (RTC timer) 
	;mov	[es:(0x1c<<2)+2], cs	; interrupt vector index 0x1c (decimal 28) System Timer Tick

					; locally defined interrupt	
	
	mov	ax,interrupt 
	mov	[es:0x80<<2], ax	; se intel manual, 3-482. Vol 2A, INT n... REAL-ADDRESS-MODE 
	mov	[es:(0x80<<2)+2], cs	; intterupt vector index 0x80 (decimal 128) 
	

	sti	 			; restore interrupts
					; https://stackoverflow.com/questions/18879479/custom-irq-handler-in-real-mode
	int	0x80			; test: calls locally defined interrupt.

	jmp	mainloop

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
	; ICW1 - start init sequence:
	;   bit4=1  init command
	;   bit3=0  edge triggered
	;   bit1=0  cascade mode
	;   bit0=1  ICW4 will follow
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

; ****************
; initialize keybord controller (TODO)
; ****************


misc:
	mov	si,prompt
	call 	print
	call 	ring_buffer_init
	push	word [hest]
	call	ring_buffer_insert

	;call 	enterstring
mainloop:
	push	halted
	call 	println
halt:
	hlt
	jmp 	halt	

%include "print.asm"

; ****************
; enterstring
;
; function calls bios code handlers
; not to be used as interrupthandler
; ****************
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
; ***********
; RINGBUFFER
; ***********
ring_buffer_init:
	mov	[rb_head], word 0 
	mov	[rb_tail], word 0
	ret
ring_buffer_insert:
	push	bp
	mov	bp, sp
	push	ax
	push	bx
	
	mov 	ax, [bp+4]
	mov	bx, [rb_head]
	mov	[rb+bx], ax
	inc	word [rb_head]
	pop	bx
	pop	ax
	pop	bp
	ret
ring_buffer_get:
; TODO - not finished
	push	bp
	mov	bp, sp
	push	bx
	mov	ax, 0
	mov	bx, [rb_tail]	
	cmp	bx, [rb_head] 
	je	.end
	mov	ax, [rb+bx]
	inc	word [rb_tail]
.end:
	pop	bx
	pop	bp
	ret
	


; *********************
; INTERRUPT HANDLERS
; *********************
; -------------------------------
;	INTERRUPT HANDLER:
;

interrupt:
	push	si
	; do something.
	mov 	si,test
	call	print
	mov	al, PIC_EOI
	out	PIC1_COMMAND, al
	out	PIC2_COMMAND, al
	pop 	si
	iret
; --------------------------------
;	Dvivision By Zero Handler
;
divisionbyzero:
	mov	si,div0
	call 	print
	;mov	ah,0x0		; should handle exception by throwing to process (while it is the process fault what this happens)
	;int	0x3		; for example as POSIX does, throw this as a SIGFPE signal (and this should be handled)
	;iret
	mov	al, PIC_EOI
	out	PIC1_COMMAND, al
	out	PIC2_COMMAND, al
	;jmp	misc
	iret	
; --------------------------------	
;	Timer handler
;
timer:
	pusha			; push all gp registers etc.
	push	ds		; this routine (roughly) counts ticks (55 ms) and writes to screen for every second passed 
	xor 	ax,ax		; reset ax
	mov	ds,ax		; set ds to 0, while ds has value of 0x0040 for some reason
				; check why online !
	xor	bx, bx
	xor	dx, dx
	mov	bx, [ticks]
	inc	bx
	mov	ax, bx
	div	word [divisor]
	cmp	dx, 0		;
	jne	.end
	;mov	si, sched	;ticks	 sched
	push	sched		; TODO - use as debug only
	call	println
	pop	cx

	call	ring_buffer_get
	cmp	ax, 0
	je	.end
	push	hest		; TODO - use as debug only  
	call	println
	pop	cx
.end:
	mov	[ticks], bx
	pop	ds
	popa
	mov	al, PIC_EOI		; acknowledge to PIC (EOI)
	out	PIC1_COMMAND, al
	out 	PIC2_COMMAND, al
	iret
; ---------------------------------
;	Keyboard handler
;
keyboard:
	;push	bp	
	;mov	bp, sp
	push	ax
	push	bx
	push	dx
	push	si
	mov	dx, 0x1e
	in	al, 0x60		; read info from keyboard
	mov	bl, al
	xor	ah, ah
	push	ax
	call 	ring_buffer_insert
	pop	dx
	cmp	bl, 0x1e		; 'A'
	je	.a
	cmp	bl, 0x39		; 'space'
	je	.space
	push	hest2			; TODO - change back to	keydefault	
	call 	println		
	pop	cx	
.a:
	push	ax
	cmp	byte [display], 0
	je	.shift
	mov	ah, 0
	mov	al, 0x03
	int	0x10
	mov	byte [display], 0
	jmp	.end
.shift:	
	mov	ah, 0
	mov	al, 0x13
	int	0x10
	call	testvga
	mov	byte [display], 1
.end:
	pop	ax		
	push 	keyb	
	call 	println
	pop	ax
	jmp	.out
.space:
	int	0x80
	jmp	.out	
.out:
	mov	al, PIC_EOI		; acknowledge to PIC (EOI)
	out	PIC1_COMMAND, al
	out 	PIC2_COMMAND, al
	pop	si
	pop	dx
	pop	bx
	pop	ax
	
	iret
; -----------------------------------
; 	Mouse handler
;
mouse:
	push	ax
	mov	si, mousestr
	call	print
	mov	al, PIC_EOI		; acknowledge to PIC (EOI)
	out	PIC1_COMMAND, al
	out 	PIC2_COMMAND, al
	pop ax
	iret
crs:
	mov	si,cr	
	call 	print
	ret
; **********
; VGA tests
; **********
testvga:
	push	ax
	push	cx
	push	dx

	mov	cx, 160		; x value
	mov	dx, 100		; y value
	mov	al, 15		; pixel color white
	mov	ah, 0x0c	; write pixel at x,y
	int	0x10		; call bios graphics routine
	
	pop	dx
	pop	cx
	pop	ax
	ret

section .data

;	ascii codes:
;	0x0d = CR (carrige return)
;	0x0a = LF (line feed)
readok		db "read ok",0x0d,0x0a,0
cr:		db 0x0d,0x0a,0
halted:		db "System halted",0
msg:		db "Hello from Brians boot-sector",0x0D,0x0A,0
msg2:		db "Message no. 2...",0x0D,0x0A,0
menu:		db "1 for enter text, q for exit",0x0d,0x0a,0
prompt:		db "> ",0
bell:		db 0x07,0
procedure: 	db 0x0
test:		db	"Called from 0x80 interrupt (internal test)",13,10,0
div0:		db 	"Division by zero exception!",13,10,0
done:		db	"Interrupt done",13,10,0
result:	times 2	db	0
ticks:		dw	1
divisor:	dw	0x12	; 18
sched:		db	"Change task interrupt",13,10,0
keyb:		db	"Some key pressed",13,10,0
keydefault	db 	"Another key pressed", 13, 10 ,0
buffer:	times	128 db  0	; string buffer
hest:		db	"A"	
rb: times	50  db	0	; ring buffer
rb_size:	db	0
rb_head:	dw	0
rb_tail:	dw	0
hest2:		db	"B",0	
display:	db	0
mousestr:	db	"Mouse...", 13, 10, 0

section	.bss
string:		resb	128	

