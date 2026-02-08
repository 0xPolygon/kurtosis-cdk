#!/bin/bash
#
# Unit Test for Transaction Replay Script Generation
# Tests the generate-replay-script.sh with various transaction scenarios
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR=$(mktemp -d)

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Log function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Test function
test_case() {
    local test_name="$1"
    echo ""
    log "TEST: $test_name"
}

assert_success() {
    local test_name="$1"
    if [ $? -eq 0 ]; then
        log "  ✓ PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log "  ✗ FAIL: $test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local test_name="$2"
    if [ -f "$file" ]; then
        log "  ✓ PASS: $test_name (file exists: $file)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log "  ✗ FAIL: $test_name (file not found: $file)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_contains() {
    local file="$1"
    local pattern="$2"
    local test_name="$3"
    if grep -q "$pattern" "$file"; then
        log "  ✓ PASS: $test_name (pattern found)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log "  ✗ FAIL: $test_name (pattern not found: $pattern)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

log "=========================================="
log "Transaction Replay Script Test Suite"
log "=========================================="

# ============================================================================
# Test 1: Generate script with no transactions
# ============================================================================

test_case "Generate replay script with zero transactions"

TEST_DIR="$TEMP_DIR/test1"
mkdir -p "$TEST_DIR/artifacts"

# Create empty transactions.jsonl
touch "$TEST_DIR/artifacts/transactions.jsonl"

# Generate replay script
"$SCRIPT_DIR/scripts/generate-replay-script.sh" "$TEST_DIR" > /dev/null 2>&1
assert_success "Script generation with zero transactions"

assert_file_exists "$TEST_DIR/artifacts/replay-transactions.sh" "Replay script file created"

# Verify script has valid syntax
bash -n "$TEST_DIR/artifacts/replay-transactions.sh"
assert_success "Generated script has valid bash syntax"

# ============================================================================
# Test 2: Generate script with one transaction
# ============================================================================

test_case "Generate replay script with one transaction"

TEST_DIR="$TEMP_DIR/test2"
mkdir -p "$TEST_DIR/artifacts"

# Create transactions.jsonl with one transaction
cat > "$TEST_DIR/artifacts/transactions.jsonl" << 'EOF'
{"block":1,"tx_index":0,"raw_tx":"0xf86d8085174876e800825208940000000000000000000000000000000000000001880de0b6b3a764000080820a96a0c0d8c4d0f5e1b7a3d0b3c4d0f5e1b7a3d0b3c4d0f5e1b7a3d0b3c4d0f5e1b7a3a0c0d8c4d0f5e1b7a3d0b3c4d0f5e1b7a3d0b3c4d0f5e1b7a3d0b3c4d0f5e1b7a3"}
EOF

# Generate replay script
"$SCRIPT_DIR/scripts/generate-replay-script.sh" "$TEST_DIR" > /dev/null 2>&1
assert_success "Script generation with one transaction"

assert_file_exists "$TEST_DIR/artifacts/replay-transactions.sh" "Replay script file created"

# Verify script contains the transaction
assert_contains "$TEST_DIR/artifacts/replay-transactions.sh" "send_tx 1" "Script contains transaction 1"
assert_contains "$TEST_DIR/artifacts/replay-transactions.sh" "0xf86d8085174876e800825208940000000000000000000000000000000000000001880de0b6b3a764000080820a96a0c0d8c4d0f5e1b7a3d0b3c4d0f5e1b7a3d0b3c4d0f5e1b7a3d0b3c4d0f5e1b7a3a0c0d8c4d0f5e1b7a3d0b3c4d0f5e1b7a3d0b3c4d0f5e1b7a3d0b3c4d0f5e1b7a3" "Script contains raw transaction data"

# Verify script has valid syntax
bash -n "$TEST_DIR/artifacts/replay-transactions.sh"
assert_success "Generated script has valid bash syntax"

# ============================================================================
# Test 3: Generate script with multiple transactions
# ============================================================================

test_case "Generate replay script with 10 transactions"

TEST_DIR="$TEMP_DIR/test3"
mkdir -p "$TEST_DIR/artifacts"

# Create transactions.jsonl with 10 transactions
for i in {1..10}; do
    echo "{\"block\":$i,\"tx_index\":0,\"raw_tx\":\"0xf86d8085174876e800825208940000000000000000000000000000000000000001880de0b6b3a764000080820a96a0c0d8c4d0f5e1b7a3d0b3c4d0f5e1b7a3d0b3c4d0f5e1b7a3d0b3c4d0f5e1b7a3a0c0d8c4d0f5e1b7a3d0b3c4d0f5e1b7a3d0b3c4d0f5e1b7a3d0b3c4d0f5e1b7a$i\"}" >> "$TEST_DIR/artifacts/transactions.jsonl"
done

# Generate replay script
"$SCRIPT_DIR/scripts/generate-replay-script.sh" "$TEST_DIR" > /dev/null 2>&1
assert_success "Script generation with 10 transactions"

assert_file_exists "$TEST_DIR/artifacts/replay-transactions.sh" "Replay script file created"

# Verify script contains all transactions
for i in {1..10}; do
    assert_contains "$TEST_DIR/artifacts/replay-transactions.sh" "send_tx $i" "Script contains transaction $i"
done

# Verify script has valid syntax
bash -n "$TEST_DIR/artifacts/replay-transactions.sh"
assert_success "Generated script has valid bash syntax with 10 transactions"

# ============================================================================
# Test 4: Error handling - missing transactions.jsonl
# ============================================================================

test_case "Error handling: missing transactions.jsonl"

TEST_DIR="$TEMP_DIR/test4"
mkdir -p "$TEST_DIR/artifacts"

# Do not create transactions.jsonl

# Try to generate replay script (should fail)
if "$SCRIPT_DIR/scripts/generate-replay-script.sh" "$TEST_DIR" > /dev/null 2>&1; then
    log "  ✗ FAIL: Script should have failed with missing transactions.jsonl"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    log "  ✓ PASS: Script correctly failed with missing transactions.jsonl"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# ============================================================================
# Test 5: Script executability
# ============================================================================

test_case "Generated script is executable"

TEST_DIR="$TEMP_DIR/test5"
mkdir -p "$TEST_DIR/artifacts"

# Create transactions.jsonl with one transaction
echo '{"block":1,"tx_index":0,"raw_tx":"0xf86d"}' > "$TEST_DIR/artifacts/transactions.jsonl"

# Generate replay script
"$SCRIPT_DIR/scripts/generate-replay-script.sh" "$TEST_DIR" > /dev/null 2>&1
assert_success "Script generation"

# Check if script is executable
if [ -x "$TEST_DIR/artifacts/replay-transactions.sh" ]; then
    log "  ✓ PASS: Generated script is executable"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log "  ✗ FAIL: Generated script is not executable"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# ============================================================================
# Test 6: Parallel replay structure verification
# ============================================================================

test_case "Parallel replay structure (send all, then wait all)"

TEST_DIR="$TEMP_DIR/test6"
mkdir -p "$TEST_DIR/artifacts"

# Create transactions.jsonl with 5 transactions
for i in {1..5}; do
    echo "{\"block\":$i,\"tx_index\":0,\"raw_tx\":\"0xf86d8085174876e800825208940000000000000000000000000000000000000001880de0b6b3a764000080820a96a0c0d8c4d0f5e1b7a3d0b3c4d0f5e1b7a3d0b3c4d0f5e1b7a3d0b3c4d0f5e1b7a3a0c0d8c4d0f5e1b7a3d0b3c4d0f5e1b7a3d0b3c4d0f5e1b7a3d0b3c4d0f5e1b7a$i\"}" >> "$TEST_DIR/artifacts/transactions.jsonl"
done

# Generate replay script
"$SCRIPT_DIR/scripts/generate-replay-script.sh" "$TEST_DIR" > /dev/null 2>&1
assert_success "Script generation with 5 transactions"

assert_file_exists "$TEST_DIR/artifacts/replay-transactions.sh" "Replay script file created"

# Verify parallel replay structure
assert_contains "$TEST_DIR/artifacts/replay-transactions.sh" "Parallel Transaction Replay" "Script header mentions parallel replay"
assert_contains "$TEST_DIR/artifacts/replay-transactions.sh" "Phase 1: Sending all transactions" "Script has Phase 1 section"
assert_contains "$TEST_DIR/artifacts/replay-transactions.sh" "Phase 2: Waiting for all transactions to be mined" "Script has Phase 2 section"

# Verify both send and wait functions exist
assert_contains "$TEST_DIR/artifacts/replay-transactions.sh" "send_tx()" "Script has send_tx function"
assert_contains "$TEST_DIR/artifacts/replay-transactions.sh" "wait_for_tx()" "Script has wait_for_tx function"

# Verify transaction hash collection
assert_contains "$TEST_DIR/artifacts/replay-transactions.sh" "tx_hashes=" "Script collects transaction hashes"
assert_contains "$TEST_DIR/artifacts/replay-transactions.sh" "tx_numbers=" "Script collects transaction numbers"

# Verify waiting logic
assert_contains "$TEST_DIR/artifacts/replay-transactions.sh" "wait_for_tx" "Script calls wait_for_tx"

# Verify script has valid syntax
bash -n "$TEST_DIR/artifacts/replay-transactions.sh"
assert_success "Generated parallel replay script has valid bash syntax"

# ============================================================================
# Test Summary
# ============================================================================

echo ""
log "=========================================="
log "Test Results"
log "=========================================="
log "Passed: $TESTS_PASSED"
log "Failed: $TESTS_FAILED"

if [ $TESTS_FAILED -eq 0 ]; then
    log "All tests passed! ✓"
    exit 0
else
    log "Some tests failed! ✗"
    exit 1
fi
