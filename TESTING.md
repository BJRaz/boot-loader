# Boot-Loader Automated Test Suite

## Overview
Comprehensive automated testing suite for the boot-loader project with three test categories:

1. **Assembler Tests** (`test_assembler.sh`)
2. **Binary Structure Tests** (`test_binary_structure.sh`)
3. **Code Quality Tests** (`test_code_quality.sh`)

## Running Tests

### Run all tests:
```bash
make test
```

### Run specific test suite:
```bash
make test-asm        # Assembler and build tests
make test-binary     # Binary structure tests
make test-quality    # Code quality tests
```

### Run individual test file directly:
```bash
bash tests/test_assembler.sh
bash tests/test_binary_structure.sh
bash tests/test_code_quality.sh
```

## Test Categories

### 1. Assembler Tests (test_assembler.sh)
Tests basic assembly, build process, and artifact generation:

- ✓ NASM assembler availability
- ✓ boot.asm syntax validation
- ✓ boot2.asm syntax validation
- ✓ print.asm inclusion check
- ✓ Clean build process
- ✓ boot.bin size (512 bytes - bootloader sector)
- ✓ boot2.bin size validation
- ✓ floppy.img size (1.44 MB)
- ✓ boot.bin signature (0x55AA)
- ✓ Debug messages in stage 1
- ✓ Debug messages in stage 2
- ✓ Interrupt macro definition
- ✓ Named constants in code

### 2. Binary Structure Tests (test_binary_structure.sh)
Validates memory layout and interrupt structure:

- ✓ Boot sector at offset 0x0000
- ✓ Boot2 sector at offset 0x0200 (sector 1)
- ✓ Boot signature (0x55AA) at offset 510-511
- ✓ Boot.bin sector boundary compliance
- ✓ Boot2.bin space allocation
- ✓ CLI instruction (interrupt disable)
- ✓ STI instruction (interrupt enable)
- ✓ IDT setup calls (4+ interrupt registrations)
- ✓ BIOS video interrupt (0x10) usage
- ✓ BIOS disk interrupt (0x13) usage
- ✓ Print routine definition
- ✓ Println routine definition
- ✓ IRET in interrupt handlers
- ✓ String null termination

### 3. Code Quality Tests (test_code_quality.sh)
Checks code standards and best practices:

- ✓ Proper section declarations (.text, .data)
- ✓ Origin address (org) definition
- ✓ 16-bit mode (bits 16) specification
- ✓ Label definitions
- ✓ Return instructions
- ✓ Named constants (EQU usage)
- ✓ Code comments
- ✓ Macro definitions
- ✓ Stack operations
- ✓ Register preservation (push/pop pairs)

**Warnings (non-blocking):**
- ⚠ Commented-out code sections
- ⚠ TODO markers in code

## Test Results

Sample output from `make test`:

```
╔════════════════════════════════════════╗
║   Boot-Loader Automated Test Suite     ║
╚════════════════════════════════════════╝

=== Boot-Loader Test Suite ===
Testing: NASM assembler available ... PASS
Testing: boot.asm syntax check ... PASS
Testing: boot2.asm syntax check ... PASS
...
=== Test Summary ===
Passed: 12
Failed: 0

=== Boot-Loader Code Quality Tests ===
...
Warnings: 2

All quality tests passed!
```

## Test Coverage

- **Syntax & Compilation:** 4 tests
- **Build Artifacts:** 5 tests
- **Binary Layout:** 8 tests
- **Code Structure:** 10 tests
- **Interrupt Handling:** 5 tests
- **BIOS Integration:** 2 tests
- **Code Quality:** 10 tests

**Total: 44 automated tests**

## Integration with CI/CD

The test suite can be integrated into CI/CD pipelines:

```bash
#!/bin/bash
make clean
make test
if [ $? -eq 0 ]; then
    echo "All tests passed!"
    make run-vbox  # or deploy
else
    echo "Tests failed!"
    exit 1
fi
```

## Adding New Tests

To add new tests, edit the appropriate test file and add a `run_test` call:

```bash
# Example
run_test "Test description" "test_command_that_exits_0_on_success"
```

Tests are collected automatically and counted in the summary.

## Troubleshooting

- **Tests fail on different systems:** Some tests use `stat -f` (macOS). For Linux, replace with `stat -c %s`.
- **Grep patterns fail:** Escape special characters or use `-F` flag for fixed strings.
- **Binary signature test fails:** Boot2 may exceed 512 bytes, pushing the signature beyond the first sector.

## Future Enhancements

- Automated VirtualBox VM testing
- Hardware testing on real floppy disks
- Performance benchmarking
- Memory layout validation
- Stack overflow detection
- Interrupt latency testing
