; **********************
; Interrupt vector numbers
; **********************

; CPU exceptions (vectors 0x00-0x07)
INT_DIVZERO		equ 0x00	; Division by zero interrupt vector (CPU fault 0)
INT_DEBUG		equ 0x01	; Debug exception vector             (CPU trap/fault 1)
INT_NMI			equ 0x02	; Non-maskable interrupt vector      (CPU NMI 2)
INT_BREAKPOINT		equ 0x03	; Breakpoint interrupt vector        (CPU trap 3)
INT_OVERFLOW		equ 0x04	; Overflow interrupt vector          (CPU trap 4)
INT_BOUND		equ 0x05	; BOUND range exceeded               (CPU fault 5)
INT_INVALIDOP		equ 0x06	; Invalid opcode interrupt vector    (CPU fault 6)
INT_DEVICE_NOT_AVAILABLE equ 0x07	; Device not available               (CPU fault 7)

; Hardware IRQs (PIC1: vectors 0x08-0x0F, PIC2: vectors 0x70-0x77)
INT_INTERVAL_TIMER	equ 0x08	; System timer tick (IRQ 0)
INT_KEYBOARD		equ 0x09	; Keyboard          (IRQ 1)
INT_CASCADE		equ 0x0a	; Cascade (internal) (IRQ 2)
INT_COM2		equ 0x0b	; COM2              (IRQ 3)
INT_COM1		equ 0x0c	; COM1              (IRQ 4)
INT_LPT2		equ 0x0d	; LPT2              (IRQ 5)
INT_FLOPPY		equ 0x0e	; Floppy disk       (IRQ 6)
INT_LPT1		equ 0x0f	; LPT1              (IRQ 7)
INT_CMOS		equ 0x70	; CMOS RTC          (IRQ 8)
INT_FREE1		equ 0x71	; Free              (IRQ 9)
INT_FREE2		equ 0x72	; Free              (IRQ 10)
INT_FREE3		equ 0x73	; Free              (IRQ 11)
INT_MOUSE		equ 0x74	; PS/2 mouse        (IRQ 12)
INT_FPU			equ 0x75	; FPU               (IRQ 13)
INT_PRIMARY_ATA		equ 0x76	; Primary ATA       (IRQ 14)
INT_SECONDARY_ATA	equ 0x77	; Secondary ATA     (IRQ 15)

; BIOS / software
INT_TIMER		equ 0x1c	; System timer tick (BIOS handler for IRQ 0)
INT_CUSTOM		equ 0x80	; Custom interrupt vector
