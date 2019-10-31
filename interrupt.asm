; test interrupt rutine (0x80)

org	0x8000
bits	16

	mov	[0x9090],word 0xFFFF
	iret


