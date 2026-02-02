# Op-Node Healthcheck Fix

## Problem

The op-node healthcheck was not working properly in generated snapshots, which prevented aggkit from starting because aggkit depends on op-node being healthy (`condition: service_healthy`).

### Root Cause

The healthcheck configuration in `generate-compose.sh` had multiple issues:

1. **Used `wget` instead of `curl`**: The op-node container doesn't have `wget` installed, causing healthchecks to fail
2. **Improper test command**: The test didn't make a proper RPC call to validate the service was actually working
3. **Affected aggkit startup**: Since aggkit has `depends_on: op-node-$prefix: condition: service_healthy`, it would never start

### Example of Broken Healthcheck

```yaml
healthcheck:
  test: ["CMD", "sh", "-c", "wget -q -O - http://localhost:8547 2>&1 | grep -q . || exit 1"]
```

Problems:
- `wget` not available in container → healthcheck always fails
- Doesn't validate actual RPC functionality
- aggkit waits forever for op-node to become healthy

## Solution

### Changes Made

Three files were modified to fix healthchecks across all services:

#### 1. Fixed op-node Healthcheck (Critical)

**File**: `/home/aigent/kurtosis-cdk/snapshot/scripts/generate-compose.sh` (line ~386-391)

**Before (Broken)**:
```yaml
healthcheck:
  test: ["CMD", "sh", "-c", "wget -q -O - http://localhost:8547 2>&1 | grep -q . || exit 1"]
  interval: 10s
  timeout: 5s
  retries: 5
  start_period: 120s
```

**After (Fixed)**:
```yaml
healthcheck:
  test: ["CMD", "curl", "-sf", "-X", "POST", "-H", "Content-Type: application/json", "--data", "{\"jsonrpc\":\"2.0\",\"method\":\"optimism_syncStatus\",\"params\":[],\"id\":1}", "http://localhost:8547"]
  interval: 10s
  timeout: 5s
  retries: 5
  start_period: 120s
```

Benefits:
- Uses `curl` which is available in op-node container
- Makes proper JSON-RPC call to `optimism_syncStatus` method
- Actually validates the service is responding correctly
- aggkit can now start once op-node is healthy

#### 2. Fixed aggkit Healthcheck

**File**: `/home/aigent/kurtosis-cdk/snapshot/scripts/generate-compose.sh` (line ~430-435)

**Before**:
```yaml
healthcheck:
  test: ["CMD", "wget", "-q", "-O", "-", "http://localhost:5577/health"]
```

**After**:
```yaml
healthcheck:
  test: ["CMD", "curl", "-sf", "http://localhost:5577/health"]
```

#### 3. Fixed agglayer Healthcheck

**File**: `/home/aigent/kurtosis-cdk/snapshot/scripts/generate-compose.sh` (line ~235-240)

**Before**:
```yaml
healthcheck:
  test: ["CMD", "wget", "-q", "-O", "-", "http://localhost:9092/metrics"]
```

**After**:
```yaml
healthcheck:
  test: ["CMD", "curl", "-sf", "http://localhost:9092/metrics"]
```

#### 4. Added Healthcheck Verification Script

**File**: `/home/aigent/kurtosis-cdk/snapshot/scripts/verify-healthchecks.sh` (new)

Automatically validates that:
- All critical services have healthchecks defined
- Healthchecks use `curl` (not `wget`)
- op-node services use proper RPC endpoint checks

#### 5. Integrated Verification into Snapshot Generation

**File**: `/home/aigent/kurtosis-cdk/snapshot/snapshot.sh`

Added automatic healthcheck verification after compose generation:
```bash
# Verify healthchecks are properly configured
log "Verifying healthcheck configurations..."

if ! "$SCRIPT_DIR/scripts/verify-healthchecks.sh" "$OUTPUT_DIR" >> "$LOG_FILE" 2>&1; then
    log_error "Healthcheck verification failed"
    log_error "See log file for details: $LOG_FILE"
    exit 1
fi
```

## Testing

### Test 1: Verify Healthcheck Configuration (Static)

Run the verification script on a generated snapshot:

```bash
# After generating a snapshot
./snapshot/scripts/verify-healthchecks.sh ./snapshots/cdk-<timestamp>
```

Expected output:
```
[VERIFY] Verifying healthchecks in: ./snapshots/cdk-<timestamp>/docker-compose.yml

=== Checking Critical Services ===
[VERIFY] Checking geth healthcheck...
[VERIFY] ✓ geth: Healthcheck uses 'curl'
...
[VERIFY] Checking op-node-001 healthcheck...
[VERIFY] ✓ op-node-001: Healthcheck uses 'curl'
[VERIFY] ✓ op-node-001: Uses proper health endpoint (optimism_syncStatus or metrics)

=== Healthcheck Verification Summary ===
[VERIFY] ✓ All critical healthchecks are properly configured
[VERIFY] Healthcheck verification PASSED
```

### Test 2: Assert op-node Health at Runtime

Run the assertion script after starting a snapshot:

```bash
# Navigate to snapshot directory
cd ./snapshots/cdk-<timestamp>

# Start the snapshot
docker compose up -d

# Assert op-node-001 becomes healthy
../../snapshot/assert-op-node-health.sh
```

Expected output:
```
[ASSERT] Found op-node-001 service in docker-compose.yml
[ASSERT] Container cdk-<timestamp>-op-node-001 is running
[ASSERT] Waiting for op-node-001 healthcheck to complete...
[ASSERT] ✓ op-node-001 is HEALTHY!

Healthcheck details:
  Last check: 2026-02-02T...
  Exit code: 0
  Output: ...

=== ASSERTION PASSED ===
✓ op-node-001 healthcheck is working correctly
✓ aggkit services can now start (if configured)
```

### Test 3: Full Snapshot Generation Test

Test the complete workflow with a new snapshot:

```bash
# Run the comprehensive test (creates new snapshot and validates)
./snapshot/test-op-node-healthcheck.sh <enclave-name>
```

This script:
1. Creates a new snapshot from the specified enclave
2. Validates healthcheck configuration in docker-compose.yml
3. Starts the snapshot with `docker compose up -d`
4. Waits for op-node-001 to become healthy
5. Validates healthcheck command works manually
6. Reports success/failure

## Verification Checklist

When generating a new snapshot, verify:

- [ ] `verify-healthchecks.sh` passes during snapshot generation
- [ ] docker-compose.yml contains no `wget` commands
- [ ] op-node services use `optimism_syncStatus` in healthcheck
- [ ] After `docker compose up -d`, op-node-001 becomes healthy
- [ ] aggkit services start successfully (if configured)
- [ ] `docker compose ps` shows all services as "healthy"

## Benefits

1. **op-node healthcheck works correctly**: Uses proper tools and methods
2. **aggkit can start**: No longer blocked by failed op-node healthcheck
3. **Consistent healthchecks**: All services use `curl` instead of `wget`
4. **Automatic validation**: Snapshots are verified during generation
5. **Better debugging**: Clear healthcheck logs when issues occur
6. **Proper RPC validation**: op-node healthcheck actually tests the service

## Files Modified

1. `/home/aigent/kurtosis-cdk/snapshot/scripts/generate-compose.sh`
   - Line ~386-391: Fixed op-node healthcheck
   - Line ~430-435: Fixed aggkit healthcheck
   - Line ~235-240: Fixed agglayer healthcheck

2. `/home/aigent/kurtosis-cdk/snapshot/scripts/verify-healthchecks.sh` (new)
   - Validates healthcheck configuration in generated snapshots

3. `/home/aigent/kurtosis-cdk/snapshot/snapshot.sh`
   - Added healthcheck verification step after compose generation
   - Updated SCRIPTS array to include verify-healthchecks.sh

4. `/home/aigent/kurtosis-cdk/snapshot/assert-op-node-health.sh` (new)
   - Runtime assertion script for op-node healthcheck

5. `/home/aigent/kurtosis-cdk/snapshot/test-op-node-healthcheck.sh` (new)
   - Comprehensive test script for healthcheck functionality

## Docker Compose Dependencies

The fix ensures this dependency chain works correctly:

```
L1 (geth, beacon) → healthy
    ↓
op-geth-001 → healthy
    ↓
op-node-001 → healthy  ← FIXED: Now properly reports healthy status
    ↓
aggkit-001 → can now start! ✓
```

Without the fix, op-node-001 would never become "healthy", so aggkit-001 would never start.

## Existing Snapshots

Snapshots generated before this fix will still have broken healthchecks. Options:

1. **Recommended**: Regenerate snapshots using the fixed scripts
   ```bash
   ./snapshot/snapshot.sh <enclave-name>
   ```

2. **Manual fix**: Edit the docker-compose.yml in existing snapshots:
   - Replace `wget` with `curl` in all healthcheck commands
   - For op-node, use the proper JSON-RPC healthcheck shown above

## Related Documentation

- Network fix: `NETWORK_FIX_SUMMARY.md` - Fixed docker network label issues
- Main snapshot README: `../README.md` - General snapshot documentation
- Usage guide: Generated in each snapshot as `USAGE.md`

## Additional Notes

- All healthchecks now use consistent tooling (`curl`)
- The `optimism_syncStatus` method is the recommended way to check op-node health
- Start period of 120s gives op-node time to sync with L1 before checking health
- The fix is backward compatible - old snapshots continue to work (just regenerate for the fix)
