# Copilot instructions for `boot-loader`

## Project purpose and architecture
- This repo is a **two-stage 16-bit real-mode bootloader** assembled with NASM.
- Stage 1 is `src/boot.asm` (`org 0x7c00`), compiled to `build/obj/boot.bin`, written to sector 0.
- Stage 2 is `src/boot2.asm` (`org 0x8000`), compiled to `build/obj/boot2.bin`, written starting at sector 1.
- `include/print.asm` is shared via `%include "print.asm"`; `printf` is conditionally included via `%ifdef INCLUDE_PRINTF`.
- Stage 1 loads stage 2 with BIOS `int 0x13` (`SECTORS_TO_READ` in `src/boot.asm`) and then jumps to `BOOT2_ADDR`.
- Stage 2 currently hooks IRQ0 directly (`INT 0x08`) and performs PCB-based context switching between two demo processes.

## Build and artifact workflow (verified)
- Primary workflow is Makefile-driven:
  - `make clean && make`
- Build outputs:
  - `build/obj/boot.bin` (must remain boot-sector sized)
  - `build/obj/boot2.bin`
  - `floppy.img` (1.44MB image, 2880 sectors)
- Image layout is explicit in `Makefile`:
  - sector 0: `boot.bin`
  - sector 1+: `boot2.bin`
- Current Stage 1 read window is `SECTORS_TO_READ equ 4` (2048 bytes).
- Keep `build/obj/boot2.bin` size `<= SECTORS_TO_READ * 512` unless you also update stage1 read count.

## Run/debug workflow
- QEMU path: `make run` (runs `qemu-system-i386 -fda floppy.img`, falls back to a message if QEMU is missing).
- VirtualBox path: `make run-vbox` attaches `floppy.img` to VM `boot-loader`, enables GDB at `localhost:5037`, starts GUI VM.
- Expect BIOS-level debugging patterns: debug strings in assembly (`[BOOT]`, `[BOOT2]`) instead of high-level logging.
- For scheduler debugging, validate both register state and visible screen output; timer-driven task switching is easiest to observe in the VM display.

## MCP server tooling
- For MCP server implementation in this repo, use Python tooling explicitly with `python3` and `pip3` commands.
- Prefer `python3 -m pip ...` when installing/upgrading Python packages for MCP server work.
- Use Python-based scripts/tools for VirtualBox MCP workflows unless the task explicitly requires a different runtime.

## MCP client interaction
- The MCP server is designed to be launched by an MCP client (e.g., Claude Desktop, VS Code Copilot) and communicates over stdio.
- Do not run the MCP server directly from the command line; it is intended to be managed by an MCP client that handles its lifecycle and communication.
- Read the README.md in `mcp-server/` for details on how the server works and how to set up the environment for it.

## Current repo caveats to respect
- `Makefile` no longer exposes `test` targets; use `make clean && make` as the primary verification workflow.
- `build_boot.sh` is legacy and references old root-level paths (`boot.asm`); prefer `Makefile` commands.
- Stage 2 feature growth can silently exceed Stage 1 disk-read size if `SECTORS_TO_READ` is not updated.

## Assembly conventions used here
- Keep constants as `equ` near file top (see `src/boot.asm`, `src/boot2.asm`).
- Preserve 16-bit real-mode style (`bits 16`, BIOS interrupts, explicit segment setup).
- Reuse existing halt pattern for terminal/error paths: `halt_loop` with `cli`, `hlt`, and self-jump.
- Keep include paths compatible with `ASFLAGS=-f bin -I include/` (use `%include "print.asm"`, not hardcoded relative parent paths).
- Preserve boot signature at end of stage 1: `times 510-($-$$) db 0` then `dw 0x55aa`.
- In IRQ handlers, keep PIC EOI behavior correct for the hooked vector (`INT 0x08` must EOI PIC1 explicitly).
- Avoid BIOS output from inside the timer ISR; keep printing in process/mainline context.

## Change guidelines for agents
- Prefer minimal surgical edits in `src/boot.asm`, `src/boot2.asm`, and `include/print.asm`.
- Verify changes with `make clean && make` before concluding.
- If changing disk loading behavior, keep stage handoff contract intact: stage 1 loads stage 2 to `0x8000` and jumps there.
- If `boot2.bin` grows, update `SECTORS_TO_READ` in `src/boot.asm` (or add a Makefile size gate) as part of the same change.
