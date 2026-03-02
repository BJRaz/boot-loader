# Project Structure

Refactored boot-loader project with organized directory layout.

## Directory Layout

```
boot-loader/
├── src/                          # Source assembly files
│   ├── boot.asm                 # Stage 1 bootloader (512 bytes, 0x7c00)
│   ├── boot2.asm                # Stage 2 bootloader (loaded at 0x8000)
│   └── program.asm              # Future: Main program
│
├── include/                      # Include files
│   ├── print.asm                # Print/println routines
│   └── interrupt.asm            # Interrupt handlers (future use)
│
├── build/                        # Build artifacts (generated)
│   └── obj/                      # Object files
│       ├── boot.bin             # Compiled stage 1
│       └── boot2.bin            # Compiled stage 2
│
├── tests/                        # Automated test suite
│   ├── run_all_tests.sh         # Test runner
│   ├── test_assembler.sh        # Assembler & build tests
│   ├── test_binary_structure.sh # Binary layout tests
│   └── test_code_quality.sh     # Code quality tests
│
├── docs/                         # Documentation
│   └── (future documentation)
│
├── Makefile                      # Build configuration
├── README.md                     # Project overview
├── TESTING.md                    # Testing guide
├── PROJECT_STRUCTURE.md          # This file
├── floppy.img                    # Bootable floppy image (1.44 MB)
├── CHANGELOG.md                  # Version history
├── linker.ld                     # Linker script (future use)
├── tags                          # Vim/editor tags
└── build_boot.sh                 # Legacy build script
```

## File Descriptions

### src/ Directory
- **boot.asm** - Primary bootloader stage 1
  - Loaded at 0x7c00 by BIOS
  - Size: exactly 512 bytes with 0x55AA signature
  - Tasks: Initialize hardware, setup video, read boot2 from disk, jump to 0x8000

- **boot2.asm** - Secondary bootloader stage 2
  - Loaded at 0x8000 by stage 1
  - Size: ~1KB, expandable
  - Tasks: Setup IDT, configure interrupts, initialize kernel

- **program.asm** - Reserved for future main program

### include/ Directory
- **print.asm** - Text output routines
  - `print` - Print null-terminated string
  - `println` - Print with return value handling
  - Used by both boot stages

- **interrupt.asm** - Reserved for interrupt definitions

### build/ Directory
- **obj/** - Generated object files
  - boot.bin - Assembled boot.asm
  - boot2.bin - Assembled boot2.asm
  - Automatically created during build
  - Safe to delete (will be rebuilt)

### tests/ Directory
- **run_all_tests.sh** - Master test runner
- **test_assembler.sh** - Syntax, assembly, and build validation (13 tests)
- **test_binary_structure.sh** - Memory layout and structure validation (14 tests)
- **test_code_quality.sh** - Code standards and best practices (10 tests)

Total: 37+ automated tests

### Root Level Files
- **Makefile** - Build rules and targets
  - `make` or `make all` - Build bootloader image
  - `make clean` - Remove build artifacts
  - `make test` - Run all tests
  - `make run-vbox` - Run in VirtualBox

- **README.md** - Project overview and quick start
- **TESTING.md** - Detailed testing guide
- **CHANGELOG.md** - Version history and changes
- **linker.ld** - Reserved for future linker configuration
- **build_boot.sh** - Legacy shell script (can be deprecated)
- **tags** - Ctags/editor tag file

## Build Process

### Compilation Flow
```
src/boot.asm  ─┐
               ├─→ [nasm -I include/] → build/obj/boot.bin
               │
include/*.asm  │
               │
src/boot2.asm ─┤
               └─→ [nasm -I include/] → build/obj/boot2.bin
                          ↓
                    [dd combine sectors]
                          ↓
                    floppy.img (1.44 MB)
```

### Build Artifacts
- **build/obj/boot.bin** - 512 bytes (stage 1)
- **build/obj/boot2.bin** - ~1KB (stage 2)
- **floppy.img** - 1.44 MB complete floppy image

## Key Design Features

### Modular Structure
- Separate source and include directories
- Include files can be reused across modules
- Build artifacts isolated in build/ directory

### Clean Separation
- **src/** - Standalone, runnable code
- **include/** - Reusable components
- **build/** - Temporary artifacts only
- **tests/** - Validation and verification

### Compiler Integration
- NASM configured with `-I include/` flag
- Allows `%include "print.asm"` without path prefixes
- Supports future nested includes

## Makefile Targets

| Target | Purpose |
|--------|---------|
| `make` / `make all` | Build bootloader image |
| `make clean` | Remove build artifacts |
| `make run-vbox` | Launch in VirtualBox |
| `make test` | Run all automated tests |
| `make test-asm` | Run assembler tests |
| `make test-binary` | Run binary structure tests |
| `make test-quality` | Run code quality tests |

## Naming Conventions

- **Assembly files** - `.asm` extension
- **Binary objects** - `.bin` extension
- **Include files** - Placed in `include/` without subdirectories
- **Source files** - Placed in `src/` without subdirectories
- **Build output** - Under `build/obj/`

## Dependencies

- NASM assembler (`nasm`)
- Make build tool (`make`)
- VirtualBox for testing (`VBoxManage`)
- Standard Unix tools: `dd`, `grep`, `xxd`, etc.

## Adding New Files

### New Source File
1. Create `src/newfile.asm`
2. Add to Makefile's OBJS variable if compilable
3. Update tests if needed

### New Include File
1. Create `include/newfile.asm`
2. Reference in source with `%include "newfile.asm"`
3. Ensure NASM finds it via `-I include/` flag

### New Test
1. Create `tests/test_newarea.sh`
2. Add to `run_all_tests.sh`
3. Follow test script conventions

## Future Considerations

- Separate documentation in `docs/`
- Potential subdirectories under `src/` for complex projects
- Automated build on GitHub Actions
- Cross-platform build support (Windows/Linux/macOS)
