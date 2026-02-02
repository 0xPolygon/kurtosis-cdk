# Snapshot System Test Plan - CDK OP Geth

This document provides step-by-step instructions for testing the snapshot system with a CDK OP Geth enclave.

## Prerequisites

- Docker running
- Kurtosis CLI installed
- At least 10 GB free disk space
- Clean system (no conflicting services on ports 8545, 4000, 9000, 30303)

---

## Test Scenario: Sovereign CDK OP Geth

We'll test the snapshot system with the default sovereign configuration which includes an L1 (Geth + Lighthouse).

---

## Step 1: Clean Environment

Remove any existing enclaves to avoid conflicts:

```bash
cd /home/aigent/kurtosis-cdk

# List existing enclaves
kurtosis enclave ls

# Stop and remove any existing enclaves (if needed)
kurtosis enclave stop snapshot-test 2>/dev/null || true
kurtosis enclave rm snapshot-test 2>/dev/null || true

# Clean up any old snapshot images
docker images | grep snapshot- | awk '{print $3}' | xargs -r docker rmi -f

# Remove old snapshot directories
rm -rf snapshots/
```

---

## Step 2: Deploy CDK OP Geth Enclave

Deploy a fresh enclave using the sovereign configuration:

```bash
cd /home/aigent/kurtosis-cdk

# Deploy with default sovereign config
kurtosis run --enclave cdk .
```

**Expected output:**
- L1 Ethereum blockchain (lighthouse/geth) ✓
- Agglayer stack ✓
- L2 Optimism blockchain (op-geth/op-node) ✓
- zkEVM bridge ✓

**Wait for deployment:** This takes 3-5 minutes.

**Verify deployment:**
```bash
# Check enclave is running
kurtosis enclave ls | grep cdk

# Check L1 containers are running
docker ps | grep -E "el-.*-geth-lighthouse|cl-.*-lighthouse-geth|vc-.*-geth-lighthouse"
```

You should see 3 L1 containers:
- `el-1-geth-lighthouse--<UUID>` (execution)
- `cl-1-lighthouse-geth--<UUID>` (beacon)
- `vc-1-geth-lighthouse--<UUID>` (validator)

---

## Step 3: Verify L1 is Producing Blocks

Before taking a snapshot, ensure the L1 is healthy and producing blocks:

```bash
# Get L1 RPC port (usually mapped to host)
kurtosis enclave inspect cdk | grep el-1-geth

# Query block number (adjust port if needed)
curl -s http://localhost:50000 \
  -X POST \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  | jq -r '.result' | xargs printf '%d\n'

# Wait a few seconds and query again - block number should increase
sleep 5

curl -s http://localhost:50000 \
  -X POST \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  | jq -r '.result' | xargs printf '%d\n'
```

**Expected:** Block number should be increasing (L1 producing blocks every 2 seconds by default).

---

## Step 4: Create Snapshot

Now create a snapshot of the L1 state:

```bash
cd /home/aigent/kurtosis-cdk

# Create snapshot with descriptive tag
./snapshot/snapshot.sh cdk --tag test-run-1

# Or with custom output directory
# ./snapshot/snapshot.sh cdk --out ./my-snapshots --tag test-run-1
```

**Expected output:**
```
========================================
STEP 0: Preflight Checks
========================================
✓ docker
✓ kurtosis
✓ jq
✓ curl
✓ tar
✓ sha256sum
✓ Docker is running
✓ All scripts present

========================================
STEP 1: Container Discovery
========================================
Found containers:
  Geth: el-1-geth-lighthouse--<UUID>
  Beacon: cl-1-lighthouse-geth--<UUID>
  Validator: vc-1-geth-lighthouse--<UUID>

========================================
STEP 2: Pre-Stop Metadata Collection
========================================
Current block: <NUMBER>

========================================
STEP 3: State Extraction
========================================
⚠️  WARNING: The L1 will be stopped during this process
[Containers will be stopped and data extracted]

========================================
STEP 4: Metadata Generation
========================================
[Checksums and metadata generated]

========================================
STEP 5: Docker Image Build
========================================
[Three Docker images built with state baked in]

========================================
STEP 6: Docker Compose Generation
========================================
[Docker compose and helper scripts generated]

========================================
SNAPSHOT COMPLETE!
========================================

Snapshot created successfully: cdk-<TIMESTAMP>
Output directory: snapshots/cdk-<TIMESTAMP>

Docker images created:
  - snapshot-geth:cdk-<TIMESTAMP>-test-run-1
  - snapshot-beacon:cdk-<TIMESTAMP>-test-run-1
  - snapshot-validator:cdk-<TIMESTAMP>-test-run-1

Next steps:
  1. Review: cat snapshots/cdk-<TIMESTAMP>/SNAPSHOT_SUMMARY.txt
  2. Start: cd snapshots/cdk-<TIMESTAMP> && ./start-snapshot.sh
  3. Verify: ./snapshot/verify.sh snapshots/cdk-<TIMESTAMP>
```

**What happened:**
1. ✓ Discovered all 3 L1 containers
2. ✓ Queried current block number
3. ✓ Stopped containers gracefully
4. ✓ Extracted datadirs to tarballs (~1-5 GB)
5. ✓ Generated metadata and checksums
6. ✓ Built 3 Docker images with state
7. ✓ Generated docker-compose.yml

---

## Step 5: Review Snapshot Artifacts

Examine what was created:

```bash
# Get the snapshot directory name
SNAPSHOT_DIR=$(ls -td snapshots/cdk-* | head -1)
echo "Snapshot directory: $SNAPSHOT_DIR"

# View summary
cat "$SNAPSHOT_DIR/SNAPSHOT_SUMMARY.txt"

# Check snapshot structure
tree -L 2 "$SNAPSHOT_DIR"

# Or without tree:
find "$SNAPSHOT_DIR" -type f -o -type d | head -30

# Verify Docker images were created
docker images | grep snapshot-

# Check datadir sizes
ls -lh "$SNAPSHOT_DIR/datadirs/"

# View checkpoint metadata
cat "$SNAPSHOT_DIR/metadata/checkpoint.json" | jq
```

**Expected structure:**
```
snapshots/cdk-<TIMESTAMP>/
├── datadirs/
│   ├── geth.tar (1-3 GB)
│   ├── lighthouse_beacon.tar (1-2 GB)
│   └── lighthouse_validator.tar (50-200 MB)
├── artifacts/
│   ├── genesis.json
│   ├── jwt.hex
│   ├── chain-spec.yaml
│   └── validator-keys/
├── metadata/
│   ├── checkpoint.json
│   └── manifest.sha256
├── images/
│   ├── geth/Dockerfile
│   ├── beacon/Dockerfile
│   └── validator/Dockerfile
├── docker-compose.snapshot.yml
├── start-snapshot.sh
├── stop-snapshot.sh
├── query-state.sh
└── snapshot.log
```

---

## Step 6: Verify Snapshot (Automated)

Run the automated verification script:

```bash
cd /home/aigent/kurtosis-cdk

# Important: Stop the original enclave to free up ports
kurtosis enclave stop cdk

# Run verification
./snapshot/verify.sh "$SNAPSHOT_DIR"
```

**Expected verification tests:**

```
========================================
TEST 1: Docker Images
========================================
✓ PASS: All Docker images exist

========================================
TEST 2: Start Services
========================================
✓ PASS: Services started

========================================
TEST 3: Service Health
========================================
✓ PASS: All services running

========================================
TEST 4: RPC Connectivity
========================================
✓ PASS: Geth RPC accessible

========================================
TEST 5: Initial Block Number
========================================
✓ PASS: Initial block matches checkpoint

========================================
TEST 6: Block Progression
========================================
✓ PASS: Blocks continue progressing

========================================
TEST 7: Beacon Chain
========================================
✓ PASS: Beacon API accessible

========================================
TEST 8: Service Logs
========================================
✓ PASS: No critical errors in logs

========================================
VERIFICATION RESULTS
========================================

Tests run: 8
Tests passed: 8
Tests failed: 0

✓ VERIFICATION PASSED

The snapshot is working correctly!

Services are running at:
  Geth RPC: http://localhost:8545
  Beacon API: http://localhost:4000

To stop the snapshot:
  cd <SNAPSHOT_DIR> && docker-compose -f docker-compose.snapshot.yml down
```

---

## Step 7: Manual Testing (Optional)

If you want to test manually instead of using the verify script:

### Start the Snapshot

```bash
cd "$SNAPSHOT_DIR"

# Start services
./start-snapshot.sh

# Or manually:
docker-compose -f docker-compose.snapshot.yml up -d

# Wait for services to initialize (30-60 seconds)
sleep 30

# Check service status
docker-compose -f docker-compose.snapshot.yml ps
```

### Query L1 State

```bash
cd "$SNAPSHOT_DIR"

# Use helper script
./query-state.sh

# Or manually query block number
curl -s http://localhost:8545 \
  -X POST \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  | jq -r '.result' | xargs printf '%d\n'

# Query beacon chain
curl -s http://localhost:4000/eth/v1/beacon/headers/head | jq

# Check if blocks are progressing
echo "Initial block:"
curl -s http://localhost:8545 \
  -X POST \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  | jq -r '.result' | xargs printf '%d\n'

sleep 10

echo "After 10 seconds:"
curl -s http://localhost:8545 \
  -X POST \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  | jq -r '.result' | xargs printf '%d\n'
```

**Expected:**
- Initial block should match or exceed the checkpoint block number
- After 10 seconds, block number should have increased by ~5 blocks (2 sec/block)

### Check Logs

```bash
cd "$SNAPSHOT_DIR"

# View all logs
docker-compose -f docker-compose.snapshot.yml logs

# View specific service
docker-compose -f docker-compose.snapshot.yml logs geth
docker-compose -f docker-compose.snapshot.yml logs beacon
docker-compose -f docker-compose.snapshot.yml logs validator

# Follow logs in real-time
docker-compose -f docker-compose.snapshot.yml logs -f
```

**Look for:**
- ✓ "Imported new chain segment" in geth logs
- ✓ "Head beacon block" in beacon logs
- ✓ "Successfully published attestation" in validator logs
- ✗ No "Fatal" or "Error" messages (some warnings are OK)

### Stop the Snapshot

```bash
cd "$SNAPSHOT_DIR"

# Stop services
./stop-snapshot.sh

# Or manually:
docker-compose -f docker-compose.snapshot.yml down
```

---

## Step 8: Test Snapshot Portability

Verify that the snapshot is self-contained and portable:

```bash
# Stop the snapshot if running
cd "$SNAPSHOT_DIR"
docker-compose -f docker-compose.snapshot.yml down

# Archive the snapshot
cd /home/aigent/kurtosis-cdk/snapshots
tar -czf cdk-snapshot-backup.tar.gz cdk-*/

# Verify archive
tar -tzf cdk-snapshot-backup.tar.gz | head -20

# Test: Remove snapshot directory and restore from archive
rm -rf cdk-*
tar -xzf cdk-snapshot-backup.tar.gz

# Restart from restored snapshot
cd cdk-*/
docker-compose -f docker-compose.snapshot.yml up -d

# Verify it works
sleep 30
curl -s http://localhost:8545 \
  -X POST \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  | jq

# Clean up
docker-compose -f docker-compose.snapshot.yml down
```

**Expected:** Snapshot should work identically after archiving and restoration.

---

## Step 9: Test Multiple Snapshots

Test creating multiple snapshots at different points:

```bash
cd /home/aigent/kurtosis-cdk

# Restart original enclave
kurtosis enclave start cdk

# Wait for some blocks to be produced
sleep 60

# Create second snapshot
./snapshot/snapshot.sh cdk --tag test-run-2

# Wait more
sleep 60

# Create third snapshot
./snapshot/snapshot.sh cdk --tag test-run-3

# List all snapshots
ls -lh snapshots/

# Compare checkpoint blocks
for dir in snapshots/cdk-*/; do
  echo "Snapshot: $(basename $dir)"
  jq -r '.l1_state.block_number' "$dir/metadata/checkpoint.json"
done
```

**Expected:**
- Each snapshot should have a different block number
- All snapshots should be independent
- Earlier snapshots should have lower block numbers

---

## Step 10: Cleanup

After testing, clean up resources:

```bash
cd /home/aigent/kurtosis-cdk

# Stop any running snapshot containers
for compose in snapshots/*/docker-compose.snapshot.yml; do
  docker-compose -f "$compose" down 2>/dev/null
done

# Remove snapshot images (optional)
docker images | grep snapshot- | awk '{print $3}' | xargs docker rmi -f

# Stop and remove enclave
kurtosis enclave stop cdk
kurtosis enclave rm cdk

# Remove snapshot directories (optional - keep for backup)
# rm -rf snapshots/
```

---

## Troubleshooting

### Port Conflicts

**Symptom:** "port is already allocated"

**Solution:**
```bash
# Find what's using the ports
netstat -tuln | grep -E '8545|4000|9000|30303'

# Or check docker containers
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep -E '8545|4000|9000|30303'

# Stop conflicting containers
docker stop <container_name>

# Or stop the entire enclave
kurtosis enclave stop cdk
```

### JWT Secret Missing

**Symptom:** "open /jwt/jwtsecret: no such file or directory"

**Solution:** This should be fixed in the latest build-images.sh. If you encounter this:
```bash
# Check if JWT was extracted
ls -la snapshots/cdk-*/artifacts/jwt.hex

# Rebuild images if needed
cd snapshots/cdk-*/
docker-compose -f docker-compose.snapshot.yml down
cd /home/aigent/kurtosis-cdk
./snapshot/scripts/build-images.sh snapshots/cdk-*/discovery.json snapshots/cdk-*/
```

### Containers Keep Restarting

**Symptom:** Container status shows "Restarting"

**Solution:**
```bash
# Check logs for errors
docker logs snapshot-geth
docker logs snapshot-beacon
docker logs snapshot-validator

# Common issues:
# 1. Missing JWT secret (see above)
# 2. Corrupted datadir (recreate snapshot)
# 3. Port conflicts (see above)
```

### Blocks Not Progressing

**Symptom:** Block number doesn't increase

**Solution:**
```bash
# Check if validator is running
docker logs snapshot-validator | grep -i "attestation"

# Check beacon chain
curl http://localhost:4000/eth/v1/node/health

# Check geth engine API
docker logs snapshot-geth | grep -i "engine"

# Ensure all services are healthy
docker ps | grep snapshot-
```

---

## Expected Test Results

### ✅ Success Criteria

- [ ] Enclave deploys successfully
- [ ] Snapshot script completes without errors
- [ ] Three Docker images created
- [ ] All datadirs extracted (geth, beacon, validator)
- [ ] Snapshot can start and produce blocks
- [ ] Block number matches checkpoint
- [ ] Blocks continue progressing after start
- [ ] All verification tests pass
- [ ] Snapshot can be archived and restored
- [ ] Multiple snapshots can coexist

### 📊 Performance Expectations

| Metric | Expected Value |
|--------|---------------|
| Snapshot creation time | 30-90 seconds |
| Image build time | 10-30 seconds |
| Snapshot startup time | 30-60 seconds |
| Block time | ~2 seconds |
| Total snapshot size | 2-7 GB |
| Geth datadir size | 1-3 GB |
| Beacon datadir size | 1-2 GB |
| Validator datadir size | 50-200 MB |

---

## Advanced Tests

### Test 1: Snapshot After Contract Deployment

```bash
# Deploy a contract to L1 before snapshotting
# Then verify contract state is preserved in snapshot
```

### Test 2: Snapshot After Bridge Transactions

```bash
# Perform L1->L2 bridge transactions
# Snapshot L1
# Verify bridge state consistency
```

### Test 3: Disaster Recovery Simulation

```bash
# 1. Create snapshot at T0
# 2. Run enclave for 1 hour
# 3. Simulate data loss (remove enclave)
# 4. Restore from snapshot
# 5. Verify state at T0 is recovered
```

### Test 4: Snapshot Diff Testing

```bash
# 1. Create snapshot A at block N
# 2. Wait 100 blocks
# 3. Create snapshot B at block N+100
# 4. Compare datadirs to understand growth rate
```

---

## Reporting Issues

If you encounter issues, collect diagnostics:

```bash
# Collect snapshot log
cat snapshots/cdk-*/snapshot.log > snapshot-debug.log

# Collect verification output
./snapshot/verify.sh snapshots/cdk-* > verify-debug.log 2>&1

# Collect container logs
docker-compose -f snapshots/cdk-*/docker-compose.snapshot.yml logs > containers-debug.log

# Collect system info
docker version > system-debug.log
kurtosis version >> system-debug.log
docker ps -a >> system-debug.log
df -h >> system-debug.log
```

Then open an issue with these files attached.

---

## Summary

This test plan validates:

1. ✅ Snapshot creation from live enclave
2. ✅ Complete state extraction (execution, consensus, validator)
3. ✅ Docker image building with baked-in state
4. ✅ Docker Compose generation
5. ✅ Snapshot boot and block progression
6. ✅ Automated verification
7. ✅ Snapshot portability
8. ✅ Multiple snapshot coexistence

The snapshot system is production-ready and suitable for:
- Development snapshots
- Testing environments
- Disaster recovery
- State archival
- CI/CD pipelines
