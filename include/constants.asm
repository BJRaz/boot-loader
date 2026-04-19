; **********************
; Shared constants — memory map, video, BIOS services
; **********************

; Memory map
BOOT2_ADDR	equ 0x8000			; stage-2 load address
STACK_TOP	equ 0x7c00 - 1			; main stack (grows downward from boot code)
PROC0_STACK_TOP	equ 0x7800			; process 0 stack: 0x7700-0x7800
PROC1_STACK_TOP	equ 0x7600			; process 1 stack: 0x7500-0x7600

; Video / display
VIDEO_MODE	equ 0x03			; 80x25 text mode
CURSOR_START	equ 0x00			; cursor start scanline
CURSOR_END	equ 0x07			; cursor end scanline
VRAM_ATTR	equ 0x17			; background blue, foreground light gray (0001 0111b)
SCREEN_SIZE	equ 0x1000			; number of iterations for screen clear
SPACE_CHAR	equ 0x20			; space character

; BIOS service interrupt numbers
BIOS_VIDEO_SERVICE	equ 0x10		; BIOS video services
BIOS_DISK_SERVICE	equ 0x13		; BIOS disk services
BIOS_KEYBOARD_SERVICE	equ 0x16		; BIOS keyboard services
