#!/bin/bash
# Test Suite: Assembler and Build Tests

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TEST_DIR"

TESTS_PASSED=0
TESTS_FAILED=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test function
run_test() {
    local test_name=$1
    local test_cmd=$2
    local expected_code=${3:-0}
    
    echo -n "Testing: $test_name ... "
    
    if eval "$test_cmd" > /dev/null 2>&1; then
        actual_code=0
    else
        actual_code=$?
    fi
    
    if [ $actual_code -eq $expected_code ]; then
        echo -e "${GREEN}PASS${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}FAIL${NC} (expected: $expected_code, got: $actual_code)"
        ((TESTS_FAILED++))
    fi
}

# Test function with output check
run_test_output() {
    local test_name=$1
    local test_cmd=$2
    local expected_output=$3
    
    echo -n "Testing: $test_name ... "
    
    output=$(eval "$test_cmd" 2>&1)
    
    if echo "$output" | grep -q "$expected_output"; then
        echo -e "${GREEN}PASS${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}FAIL${NC}"
        echo "  Expected to find: $expected_output"
        echo "  Got: $output"
        ((TESTS_FAILED++))
    fi
}

echo -e "${YELLOW}=== Boot-Loader Test Suite ===${NC}\n"

SRCDIR="$TEST_DIR/src"
INCDIR="$TEST_DIR/include"

# Test 1: Check if assembler is available
run_test "NASM assembler available" "which nasm"

# Test 2: Verify boot.asm syntax
run_test "boot.asm syntax check" "nasm -f bin -I $INCDIR $SRCDIR/boot.asm -o /tmp/boot_test.bin"

# Test 3: Verify boot2.asm syntax
run_test "boot2.asm syntax check" "nasm -f bin -I $INCDIR $SRCDIR/boot2.asm -o /tmp/boot2_test.bin"

# Test 4: Verify print.asm can be assembled (included in boot2)
run_test "print.asm inclusion check" "grep -q '%include \"print.asm\"' $SRCDIR/boot2.asm"

# Test 5: Clean build succeeds
run_test "Clean build succeeds" "make -C $TEST_DIR clean && make -C $TEST_DIR"

# Test 6: Verify boot.bin exists and is 512 bytes
run_test "boot.bin size (512 bytes)" "[ -f $TEST_DIR/build/obj/boot.bin ] && [ $(stat -f%z $TEST_DIR/build/obj/boot.bin) -eq 512 ]"

# Test 7: Verify boot2.bin exists and is under 1024 bytes
run_test "boot2.bin size (< 1024 bytes)" "[ -f $TEST_DIR/build/obj/boot2.bin ] && [ $(stat -f%z $TEST_DIR/build/obj/boot2.bin) -lt 1024 ]"

# Test 8: Verify floppy.img is 1.44 MB
run_test "floppy.img size (1.44 MB)" "[ -f $TEST_DIR/floppy.img ] && [ $(stat -f%z $TEST_DIR/floppy.img) -eq 1474560 ]"

# Test 9: Verify boot signature in boot.bin
run_test "boot.bin has valid signature" "tail -c 2 $TEST_DIR/build/obj/boot.bin | xxd -p | grep -q '55aa'"

# Test 10: Check for debug messages in boot.asm
run_test "Debug messages in boot.asm" "grep -q 'msg_boot_start' $SRCDIR/boot.asm"

# Test 11: Check for debug messages in boot2.asm
run_test "Debug messages in boot2.asm" "grep -q 'msg_boot2_start' $SRCDIR/boot2.asm"

# Test 12: Check interrupt macro is defined
run_test "Interrupt setup macro defined" "grep -q 'setup_interrupt' $SRCDIR/boot2.asm"

# Test 13: Check constants are defined
run_test "Constants defined in boot.asm" "grep -q 'BOOT2_ADDR' $SRCDIR/boot.asm"

# Print summary
echo ""
echo -e "${YELLOW}=== Test Summary ===${NC}"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

# Exit with appropriate code
if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi

