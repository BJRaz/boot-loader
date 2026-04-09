# boot-loader

x86 real-mode two-stage boot loader written in NASM assembly. Targets QEMU and VirtualBox (1.44 MB floppy image).

## Build

```bash
make          # build floppy.img
make run      # launch in QEMU (qemu-system-i386)
make run-vbox # attach to VirtualBox VM "boot-loader" and start with GDB on localhost:5037
make clean    # remove build artifacts and floppy.img
```

## Architecture

| Stage | File | Load address | Size |
|-------|------|-------------|------|
| Stage 1 | `src/boot.asm` | `0x7c00` | exactly 512 bytes |
| Stage 2 | `src/boot2.asm` | `0x8000` | ~1 KB |

- Assembler: NASM, flat binary (`-f bin`), 16-bit real mode (`bits 16`)
- Includes: `include/print.asm` (BIOS teletype print routines)
- Stage 1 reads Stage 2 from floppy sector 1 (CHS 0/0/2) via `int 0x13` and jumps to `0x8000`
- Stage 2 sets up a custom IDT (division-by-zero, keyboard IRQ1, timer, software int 0x80) and provides interactive keyboard input

## Tests

```bash
cd mcp-server && .venv/bin/python -m pytest ../tests/ -v
```

The venv must exist first — create it once with:

```bash
cd mcp-server && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
```

## Key conventions

- Boot signature is `dw 0xaa55` at line 161 of `src/boot.asm` — this produces bytes `0x55 0xAA` at offsets 510–511 as required by the BIOS. Do **not** write `dw 0x55aa` (reversed byte order).
- All screen output uses BIOS teletype (`int 0x10, ah=0x0e`). There is no serial output — `-nographic` in QEMU will suppress all visible output.
- Do not change the `org` addresses (`0x7c00` / `0x8000`) without updating the corresponding disk read target in Stage 1.
