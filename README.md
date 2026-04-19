# boot-loader

A two-stage 16-bit real-mode bootloader written in NASM as a learning project.

## Overview

- **Stage 1**: `src/boot.asm` (`org 0x7c00`)
	- Builds to `build/obj/boot.bin` (boot sector)
	- Initializes basic runtime state
	- Reads stage 2 from disk using BIOS `int 0x13`
	- Jumps to stage 2 at `0x8000`

- **Stage 2**: `src/boot2.asm` (`org 0x8000`)
	- Builds to `build/obj/boot2.bin`
	- Sets up IVT handlers (including direct IRQ0 timer hook on `INT 0x08`)
	- Demonstrates simple PCB-based task switching between two processes

- **Shared print helpers**: `include/print.asm`
	- Always provides: `print`, `println`
	- Conditionally provides `printf` via `%ifdef INCLUDE_PRINTF`

## Build

Use the Makefile-driven workflow:

```bash
make clean && make
```

Build outputs:

- `build/obj/boot.bin`
- `build/obj/boot2.bin`
- `floppy.img` (1.44MB, 2880 sectors)

Image layout:

- Sector 0: `boot.bin`
- Sector 1+: `boot2.bin`

## Run

### QEMU

```bash
make run
```

### VirtualBox

```bash
make run-vbox
```

This attaches `floppy.img` to VM `boot-loader`, enables debug provider `gdb`, and starts the VM GUI.

## Stage 2 size vs Stage 1 read window

Stage 1 currently uses:

- `SECTORS_TO_READ equ 4` in `src/boot.asm`

That means stage 1 loads **2048 bytes** max from stage 2 (`4 * 512`).

If `boot2.bin` grows beyond this limit, update `SECTORS_TO_READ` (or add a build-time size gate) or stage 2 will be truncated at boot.

## Current scheduler behavior

- Timer IRQ (`INT 0x08`) is hooked directly.
- Timer ISR sends EOI to PIC1.
- Scheduler tracks process state in a manual PCB table (no NASM `struc`).
- Two demo processes print visible lines alternately.

## `printf` support

When `INCLUDE_PRINTF` is defined before `%include "print.asm"`, `printf` supports:

- `%s` string
- `%c` character
- `%x` 16-bit hex
- `%d` unsigned decimal
- `\n` newline escape (CR/LF)

## Notes

- Prefer `make clean && make` for verification.
- `build_boot.sh` is legacy; use Makefile targets instead.

