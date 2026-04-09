org	0x7c00			; address labels originates from here .. this is an offset, and CS is 0 at boottime
bits 	16

; **********************
; Constants
; **********************
BOOT2_ADDR	equ 0x8000		; boot2 stage load address
STACK_TOP	equ 0x7c00 - 1		; stack grows downward from boot code
VIDEO_MODE	equ 0x03		; 80x25 text mode
CURSOR_START	equ 0x00		; cursor start scanline
CURSOR_END	equ 0x07		; cursor end scanline
VRAM_ATTR	equ 0x17		; background blue, foreground light gray (0001 0111b)
SCREEN_SIZE	equ 0x1000		; number of iterations for screen clear
SPACE_CHAR	equ 0x20		; space character

; Disk operation constants
SECTORS_TO_READ	equ 2
CYLINDER		equ 0
SECTOR			equ 2			; sector 2 (boot sector is 1)
HEAD			equ 0
DRIVE			equ 0

section .text


; start
start:
	;int	0x03		; debug
	cli			; clear interrupt flag
	cld			; clear DF flag for auto-increment SI in string operations

	xor	ax, ax		; clear AX to set segment registers to 0
	mov	ds, ax		; clear segment registers
	mov	ss, ax		
	mov	es, ax
	mov	fs, ax
	mov	gs, ax

	mov	sp, STACK_TOP	; setup stack, stack grows downward, 
						; TODO: theres no fixed size, just need to ensure it doesn't overlap with code or data	
	mov	bp, sp			; set base pointer for stack frame (optional, but good practice)		

	; Debug: Print bootloader initialized message
	mov	si, msg_boot_start
	call	print
; **********************
;	SET VIDEO MODE
; **********************
	mov	ah, 0			; SET VIDEO MODE
	mov	al, VIDEO_MODE		; 80x25 text mode
	int	0x10			; set video mode

	; Debug: Print video mode set
	mov	si, msg_video_set
	call	print

	mov	ch, CURSOR_START	; show box shaped cursor
	mov	cl, CURSOR_END
	mov	ah, 1
	int	0x10			; interrupt 10h - video services

	; Debug: Print cursor set
	mov	si, msg_cursor_set
	call	print

				; CLEAR SCREEN using BIOS
	mov	ah, 0x9		; write char and attribute 
	mov	cx, SCREEN_SIZE	; how many times 
	mov	al, SPACE_CHAR	; write space character
	mov	bl, VRAM_ATTR	; background blue, foreground light gray
	int	0x10			; interrupt 10h - video services
	
	mov	[databuffer], word BOOT2_ADDR
				; http://staff.ustc.edu.cn/~xyfeng/research/cos/resources/BIOS/Resources/assembly/int1c.html
	sti			; set interrupt flag

	call	diskops

	jmp	BOOT2_ADDR		; jump to boot2 stage

	jmp	halt_loop

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
	mov	ah, 0		; reset drive
	mov	dl, DRIVE
	int	0x13

	; Debug: Print disk reset done
	mov	si, msg_disk_reset
	call	print

.readdisk:
	mov	ah, 0x02		; read sector function
	mov	al, SECTORS_TO_READ
	mov	ch, CYLINDER	; cylinder/track number
	mov	cl, SECTOR	; sector number (2 - boot sector is 1)
	mov	dh, HEAD	; head/side number
	mov	dl, DRIVE	; drive number
	mov	bx, 0
	mov	es, bx		; set es = 0
	mov	bx, [databuffer]; set bx = address (ES:BX = 0:offset)
	int	0x13

	cmp	ah, 0
	jz	.diskreadok

	; Debug: Print disk read error
	mov	si, msg_disk_error
	call	print
	jmp	halt_loop

.diskreadok:
	; Debug: Print disk read success
	mov	si, msg_disk_ok
	call	print

	; Debug: Print boot2 jump message
	mov	si, msg_boot2_jump
	call	print

	push	readok
	call	println
	pop	cx
	ret

halt_loop:
	cli
.hang:
	hlt
	jmp	.hang

%include "print.asm"

;section .data
msg_boot_start:		db	"[BOOT] Stage 1 initialized",13,10,0
msg_video_set:		db	"[BOOT] Video mode set (80x25)",13,10,0
msg_cursor_set:		db	"[BOOT] Cursor configured",13,10,0
msg_disk_reset:		db	"[BOOT] Disk reset complete",13,10,0
msg_disk_ok:		db	"[BOOT] Boot2 loaded successfully",13,10,0
msg_disk_error:		db	"[BOOT] ERROR: Failed to read disk!",13,10,0
msg_boot2_jump:		db	"[BOOT] Jumping to stage 2 at 0x8000...",13,10,0
readok:			db 	"Disk read ok",13,10,0
databuffer:		dw	0	
times			510 - ($-$$)	db 0
dw	0x55aa
