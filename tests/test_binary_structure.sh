#!/bin/bash
# Test Suite: Binary Structure Tests

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TEST_DIR"

TESTS_PASSED=0
TESTS_FAILED=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

run_test() {
    local test_name=$1
    local test_cmd=$2
    
    echo -n "Testing: $test_name ... "
    
    if eval "$test_cmd" > /dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}FAIL${NC}"
        ((TESTS_FAILED++))
    fi
}

echo -e "${YELLOW}=== Boot-Loader Binary Structure Tests ===${NC}\n"

# Test 1: Boot sector starts at offset 0
run_test "Boot sector at offset 0x0000" "dd if=floppy.img bs=1 count=1 skip=0 2>/dev/null | xxd -p | grep -qE '[0-9a-f]{2}'"

# Test 2: Boot2 sector starts at offset 512
run_test "Boot2 sector at offset 0x0200" "dd if=floppy.img bs=1 count=1 skip=512 2>/dev/null | xxd -p | grep -qE '[0-9a-f]{2}'"

# Test 3: Boot signature at offset 510-511
run_test "Boot signature (0x55AA) at offset 510" "dd if=floppy.img bs=1 count=2 skip=510 2>/dev/null | xxd -p | grep -q '55aa'"

# Test 4: Verify boot.bin doesn't overflow 512 bytes
run_test "Boot.bin fits in sector" "[ $(stat -f%z bin/boot.bin) -le 512 ]"

# Test 5: Verify boot2.bin doesn't exceed sector boundary
run_test "Boot2.bin fits in allocated space" "[ $(stat -f%z bin/boot2.bin) -le 512 ]"

# Test 6: Check for CLI instruction in boot.asm (interrupt disabling)
run_test "CLI (interrupt disable) in boot.asm" "grep -q 'cli' boot.asm"

# Test 7: Check for STI instruction in boot2.asm (interrupt enabling)
run_test "STI (interrupt enable) in boot2.asm" "grep -q 'sti' boot2.asm"

# Test 8: Verify IDT setup calls in boot2.asm
run_test "IDT setup calls exist" "grep -c 'setup_interrupt' boot2.asm | grep -qE '[4-9]|[0-9]{2}'"

# Test 9: Check for BIOS video interrupt calls
run_test "BIOS video interrupt (0x10) calls" "grep -q 'int.*0x10' boot.asm"

# Test 10: Check for BIOS disk interrupt calls
run_test "BIOS disk interrupt (0x13) calls" "grep -q 'int.*0x13' boot.asm"

# Test 11: Verify print routine exists
run_test "Print routine defined" "grep -q '^print:' print.asm"

# Test 12: Verify println routine exists
run_test "Println routine defined" "grep -q '^println:' print.asm"

# Test 13: Check for proper interrupt handler structure
run_test "Interrupt handlers have IRET" "grep -q 'iret' boot2.asm"

# Test 14: Verify string termination (null bytes)
run_test "String terminations (0x00) present" "grep -q ',0$' boot2.asm"

echo ""
echo -e "${YELLOW}=== Test Summary ===${NC}"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All binary structure tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi

