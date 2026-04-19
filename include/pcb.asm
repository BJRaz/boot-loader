; **********************
; Process Control Block layout (manual struct)
; **********************

PCB_STATE	equ	0	; byte: 0=unused, 1=ready, 2=running
PCB_IP		equ	1	; word: saved IP
PCB_CS		equ	3	; word: saved CS
PCB_FLAGS	equ	5	; word: saved FLAGS
PCB_SP		equ	7	; word: saved SP
PCB_SS		equ	9	; word: saved SS
PCB_AX		equ	11	; word: saved AX
PCB_BX		equ	13	; word: saved BX
PCB_CX		equ	15	; word: saved CX
PCB_DX		equ	17	; word: saved DX
PCB_SI		equ	19	; word: saved SI
PCB_DI		equ	21	; word: saved DI
PCB_BP		equ	23	; word: saved BP
PCB_DS		equ	25	; word: saved DS
PCB_ES		equ	27	; word: saved ES
PCB_SIZE	equ	29	; total bytes per entry
NUM_PROCS	equ	2

; **********************
; ISR stack frame offsets (after pusha-style push sequence)
; **********************

STK_ES		equ	0
STK_DS		equ	2
STK_BP		equ	4
STK_DI		equ	6
STK_SI		equ	8
STK_DX		equ	10
STK_CX		equ	12
STK_BX		equ	14
STK_AX		equ	16
STK_IP		equ	18
STK_CS		equ	20
STK_FLAGS	equ	22
STK_FRAME	equ	24

; **********************
; Macro: install handler into real-mode IVT
; **********************
%macro setup_interrupt 2
	mov	ax, %1
	mov	word [es:%2<<2], ax		; set offset
	mov	[es:(%2<<2)+2], cs		; set segment
%endmacro
