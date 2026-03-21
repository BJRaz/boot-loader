# Copilot instructions for `boot-loader`

## Project purpose and architecture
- This repo is a **two-stage 16-bit real-mode bootloader** assembled with NASM.
- Stage 1 is `src/boot.asm` (`org 0x7c00`), compiled to `build/obj/boot.bin`, written to sector 0.
- Stage 2 is `src/boot2.asm` (`org 0x8000`), compiled to `build/obj/boot2.bin`, written starting at sector 1.
- `include/print.asm` is shared via `%include "print.asm"` and provides `print`/`println` BIOS text output helpers.
- Stage 1 loads stage 2 with BIOS `int 0x13` and then jumps to `BOOT2_ADDR`.

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

## Run/debug workflow
- QEMU path: `make run` (runs `qemu-system-i386 -fda floppy.img`, falls back to a message if QEMU is missing).
- VirtualBox path: `make run-vbox` attaches `floppy.img` to VM `boot-loader`, enables GDB at `localhost:5037`, starts GUI VM.
- Expect BIOS-level debugging patterns: debug strings in assembly (`[BOOT]`, `[BOOT2]`) instead of high-level logging.

## Current repo caveats to respect
- `make test` currently points to `tests/run_all_tests.sh`, but `tests/` is missing in the current tree; do not assume tests are runnable.
- `build_boot.sh` is legacy and references old root-level paths (`boot.asm`); prefer `Makefile` commands.

## Assembly conventions used here
- Keep constants as `equ` near file top (see `src/boot.asm`, `src/boot2.asm`).
- Preserve 16-bit real-mode style (`bits 16`, BIOS interrupts, explicit segment setup).
- Reuse existing halt pattern for terminal/error paths: `halt_loop` with `cli`, `hlt`, and self-jump.
- Keep include paths compatible with `ASFLAGS=-f bin -I include/` (use `%include "print.asm"`, not hardcoded relative parent paths).
- Preserve boot signature at end of stage 1: `times 510-($-$$) db 0` then `dw 0x55aa`.

## Change guidelines for agents
- Prefer minimal surgical edits in `src/boot.asm`, `src/boot2.asm`, and `include/print.asm`.
- Verify changes with `make clean && make` before concluding.
- If changing disk loading behavior, keep stage handoff contract intact: stage 1 loads stage 2 to `0x8000` and jumps there.
