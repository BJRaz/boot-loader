#!/bin/bash
# Master Test Runner - Runs all test suites

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TEST_DIR"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TOTAL_PASSED=0
TOTAL_FAILED=0

echo -e "${BLUE}"
echo "╔════════════════════════════════════════╗"
echo "║   Boot-Loader Automated Test Suite     ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# Run each test suite
for test_file in tests/test_*.sh; do
    if [ -f "$test_file" ]; then
        echo -e "${YELLOW}Running: $(basename $test_file)${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        if bash "$test_file"; then
            echo ""
        else
            echo ""
        fi
    fi
done

echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Test execution complete!${NC}"
echo ""
