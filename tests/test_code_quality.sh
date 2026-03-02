#!/bin/bash
# Test Suite: Code Quality and Standards Tests

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TEST_DIR"

TESTS_PASSED=0
TESTS_FAILED=0
WARNINGS=0

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

run_warning() {
    local test_name=$1
    local test_cmd=$2
    
    echo -n "Checking: $test_name ... "
    
    if eval "$test_cmd" > /dev/null 2>&1; then
        echo -e "${YELLOW}WARNING${NC}"
        ((WARNINGS++))
    else
        echo -e "${GREEN}OK${NC}"
    fi
}

echo -e "${YELLOW}=== Boot-Loader Code Quality Tests ===${NC}\n"

# Test 1: Check for proper section declarations
run_test "Section declarations present" "grep -q 'section .text' boot.asm && grep -q 'section .data' boot.asm"

# Test 2: Check for org directive
run_test "Origin address defined" "grep -q 'org' boot.asm && grep -q 'org' boot2.asm"

# Test 3: Check for bits 16 declaration
run_test "16-bit mode specified" "grep -q 'bits.*16' boot.asm && grep -q 'bits.*16' boot2.asm"

# Test 4: Check for label definitions
run_test "Labels defined (diskops)" "grep -q '^diskops:' boot.asm"

# Test 5: Check for subroutine ret instructions
run_test "Return instructions present" "grep -q '^.*ret$' print.asm"

# Test 6: Verify constants use EQU
run_test "Constants defined with EQU" "grep -q 'equ' boot.asm && grep -q 'equ' boot2.asm"

# Test 7: Check for comment density
run_test "Comments present" "grep -q ';' boot.asm && grep -q ';' boot2.asm"

# Test 8: Verify macro usage consistency
run_test "Macro definitions used" "grep -q '%macro' boot2.asm"

# Test 9: Check stack operations
run_test "Stack setup in boot.asm" "grep -q 'mov.*sp' boot.asm"

# Test 10: Verify register preservation patterns
run_test "Register preservation (push/pop)" "grep -q 'push' boot2.asm && grep -q 'pop' boot2.asm"

# Warnings - non-fatal issues
echo ""
echo -e "${BLUE}=== Code Quality Warnings ===${NC}"

run_warning "Commented-out code" "grep -q '^[[:space:]]*;.*call' boot2.asm"

run_warning "TODO markers" "grep -i -q 'TODO' boot2.asm"

run_warning "Magic numbers (check for constants)" "grep -qE 'mov.*[0-9]{3,}' boot.asm"

# Print summary
echo ""
echo -e "${YELLOW}=== Test Summary ===${NC}"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All quality tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi

