org	0x7c00			; address labels originates from here .. this is an offset, and CS is 0 at boottime
bits 	16


section .text


; start
start:
	;int	0x03		; debug
	cli			; clear interrupt flag
	cld			; clear DF flag for auto-increment SI in string operations
	mov	ax,0
	;mov	cs,ax
	mov	ds,ax		; clear segment registers
	mov	ss,ax		; set stack segment other than 0 before far calls, jmps etc... 
	mov	es,ax
	mov 	fs,ax
	mov 	gs,ax

	mov	sp,0x7b00	; setup stack
	mov	bp,sp

	mov	ah, 0		; SET VIDEO MODE
	mov	al, 0x0d	; 640x480x16 (vga)
	; int	0x10		; set video mode does not work in VBox ?!

	mov	ch, 0		; show box shaped cursor..
	mov	cl, 7
	mov 	ah, 1
	int	0x10		; interrupt 10h - video services

				; CLEAR SCREEN AND SET BACKGROUND COLOR..
	mov	ah,0x9		; write char and attribute 
	mov	cx,0x1000	; how many times 
	mov	al,0x20		; write char (0x20 = space)
	mov	bl,0x17		; attribute 17 = 0001 0111 a.k.a background (blue), and foreground (light gray)
	int	0x10		; interrupt 10h - video services

	mov	[databuffer], word 0x8000
	
	mov	ax,timer		; - reinstate if needed.... (for scheduler)
	mov	word [es:0x1c<<2], ax	; 'listens' to timer ticks called from INT 8 (timer) 
	mov	[es:(0x1c<<2)+2], cs	; int 1c (28) System Timer Tick
					; https://www.shsu.edu/csc_tjm/spring2001/cs272/interrupt.html
	

		
	sti			; set interrupt flag

	call 	diskops

	jmp	0:0x8000	; jump to boot2 stage

	hlt

; DISK OPERATIONS:
; read from floppy
;	int 13h / ah = 02h	read interrupt
;	inputs:
;	al 			numbers of sectors to read
;	ch			cylinder(track) no 	(0-79)
;	cl			sector 		no 	(1-18)
;	dh			head(side) 	no 	(0-1)
;	dl			drive 		no	(0-3)
;	es:bx			data buffer
;	outputs:
;	cf			set on error
;	cf			clear if success
;	ah			status 0 if success
;	al			no of sectors transferred
;	note:			each sector = 512 bytes
diskops:
	mov	ah,0		; do reset on drive
	mov	dl,0		;
	int	0x13		;
.readdisk:
	mov	ah,0x02
	mov	al,2		; read 2 sectors (2 * 512 bytes)
	mov	ch,0		; cylinder no 0    
	mov	cl,2		; sector 	  no 2	(2 while bootsector is 1
				;			and data is placed directly after bootsector)
	
	mov 	dh,0		; head 		  no 0
	mov	dl,0		; drive 	  no 0 (1)
	mov	bx,0
	mov	es,bx		; set es = 0
	mov	bx,[databuffer]	; set bx = addr. (in effect ES:BX = 0:offset)
	int	0x13

	cmp	ah,0
	jz	.diskreadok
	hlt	
.diskreadok:
	mov	si,readok
	call 	print
	ret

%include "print.asm"

timer:
	push	si
	push 	ax
	push	ds
	xor 	ax,ax
	mov	ds,ax		; set ds to 0, while ds has value of 0x0040 for some reason
				; check why online !
	mov	si, sched
	call	print
	pop	ds
	pop	ax
	pop	si
	iret

;section .data
readok:		db 	"Disk read ok",13,10,0
sched:		db	"Change task interrupt",13,10,0
databuffer:	dw	0
times		510 - ($-$$)	db 0
dw	0x55aa
