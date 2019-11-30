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
	
	mov	ax,interrupt 

	mov	word [es:0x80<<2], ax	; se intel manual, 3-462. Vol 2A, INT n... REAL-ADDRESS-MODE 
	mov	[es:(0x80<<2)+2], ds	; bit-shifting by 2 equals *4 (times 4) 
	; https://stackoverflow.com/questions/18879479/custom-irq-handler-in-real-mode

	sti			; set interrupt flag

	call 	diskops

	int 	0x80

	mov	si,done
	call	print
	;mov	[0x80], byte 0x10
	
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

.diskreadok:
	mov	si,readok
	call 	print
	ret

%include "print.asm"

interrupt:
	; do something.
	mov 	si,test
	call	print
	iret

;section .data
readok:		db 	"Disk read ok",13,10,0
done:		db	"Interrupt done",13,10,0
databuffer:	dw	0
test:		db	"This is test-text",13,10,0

times		510 - ($-$$)	db 0
dw	0x55aa
