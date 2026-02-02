# Snapshot System Troubleshooting Guide

Common issues and solutions for the Ethereum L1 snapshot system.

---

## Discovery Issues

### "Enclave not found"

**Error:**
```
ERROR: Enclave 'my-enclave' not found
```

**Cause:** Enclave name doesn't exist or is misspelled.

**Solution:**
```bash
# List available enclaves
kurtosis enclave ls

# Use exact name from the list
./snapshot/snapshot.sh <exact-enclave-name>
```

---

### "Geth execution client not found"

**Error:**
```
ERROR: Geth execution client not found
```

**Cause:** No Geth container found for the enclave.

**Solution:**
```bash
# Check if L1 containers are running
docker ps | grep -E "el-.*-geth-lighthouse"

# If not running, check enclave status
kurtosis enclave inspect <enclave-name>

# Restart enclave if needed
kurtosis enclave start <enclave-name>

# Wait for containers to start
sleep 30

# Try snapshot again
./snapshot/snapshot.sh <enclave-name>
```

---

### "Lighthouse validator not found (MANDATORY)"

**Error:**
```
ERROR: Lighthouse validator not found (MANDATORY)
Validators are required for snapshot creation
```

**Cause:** Validator container missing (by design, snapshots require validators).

**Solution:**

**Option 1:** Use an enclave that includes validators (recommended)
```bash
# Default CDK deployment includes validators
kurtosis run --enclave cdk .
```

**Option 2:** If validator is stopped, start it
```bash
# Find validator container
docker ps -a | grep "vc-.*-geth-lighthouse"

# Start it
docker start <validator-container-id>

# Wait and retry snapshot
sleep 10
./snapshot/snapshot.sh <enclave-name>
```

**Why mandatory?**
Validators contain critical `slashing_protection.sqlite` that prevents double-signing. Losing this file could result in slashing penalties on a real network.

---

## Extraction Issues

### "Failed to extract Geth datadir"

**Error:**
```
ERROR: Failed to extract Geth datadir
```

**Possible Causes:**
1. Insufficient disk space
2. Docker permissions issue
3. Container stopped unexpectedly

**Solution:**
```bash
# Check disk space
df -h

# Check if at least 10 GB free
# If not, free up space or use --out with a different disk

# Check Docker status
docker info

# Verify container exists
docker ps -a | grep el-1-geth-lighthouse

# Check container logs for errors
docker logs <geth-container-name> | tail -50

# Try manual extraction test
docker cp <geth-container>:/data/geth/execution-data /tmp/test-extract

# If successful, retry snapshot
rm -rf /tmp/test-extract
./snapshot/snapshot.sh <enclave-name>
```

---

### "Critical file missing: slashing_protection.sqlite"

**Error:**
```
ERROR: Critical file missing: slashing_protection.sqlite
Cannot proceed without slashing protection database
```

**Cause:** Validator datadir incomplete or corrupted.

**Solution:**
```bash
# Check if file exists in running container
docker exec <validator-container> ls -la /validator-keys/keys/slashing_protection.sqlite

# If missing, validator may be newly created (need to wait)
# Validators create this file on first run

# Wait for validator to initialize
sleep 60

# Check validator logs
docker logs <validator-container> | grep -i "slashing"

# Retry snapshot after initialization
./snapshot/snapshot.sh <enclave-name>
```

---

## Image Build Issues

### "Image build failed" - JWT Secret

**Error in logs:**
```
ERROR: failed to solve: failed to compute cache key
```

**Cause:** Missing JWT secret or Dockerfile syntax error.

**Solution:**

This should be fixed in the latest version. If you still encounter it:

```bash
# Check if JWT was extracted
ls -la snapshots/<snapshot-dir>/artifacts/jwt.hex

# If missing, extract manually
docker cp <geth-container>:/jwt/jwtsecret snapshots/<snapshot-dir>/artifacts/jwt.hex

# Or regenerate build with fixed script
cd snapshots/<snapshot-dir>
/home/aigent/kurtosis-cdk/snapshot/scripts/build-images.sh \
  discovery.json \
  .
```

---

### "Image build failed" - Tarball Extraction

**Error in logs:**
```
mv: cannot move 'beacon-data' to a subdirectory of itself
```

**Cause:** Incorrect mv command in Dockerfile (this should be fixed).

**Verification:**
```bash
# Check if fix is applied
grep -n "mv beacon-data beacon-data" \
  /home/aigent/kurtosis-cdk/snapshot/scripts/build-images.sh

# Should return nothing (line was removed)
```

If you find the bug, update your script from the repository.

---

## Compose Generation Issues

### "Services started" fails - Port Conflicts

**Error:**
```
ERROR: for geth  Cannot start service geth: driver failed programming external connectivity
Bind for 0.0.0.0:8545 failed: port is already allocated
```

**Cause:** Ports 8545, 8546, 4000, 9000, or 30303 are in use.

**Solution:**
```bash
# Find what's using the ports
netstat -tuln | grep -E '8545|8546|4000|9000|30303'

# Or check Docker containers
docker ps --format "table {{.Names}}\t{{.Ports}}" | \
  grep -E '8545|4000|9000|30303'

# Stop conflicting containers
docker stop <container-names>

# Or stop entire enclave
kurtosis enclave stop <enclave-name>

# Retry starting snapshot
cd snapshots/<snapshot-dir>
docker-compose -f docker-compose.snapshot.yml down
docker-compose -f docker-compose.snapshot.yml up -d
```

---

### "Container is unhealthy"

**Error:**
```
ERROR: for beacon  Container "abc123" is unhealthy.
```

**Cause:** Geth health check failing, beacon waiting for healthy geth.

**Solution:**
```bash
# Check geth container logs
docker logs snapshot-geth | tail -50

# Common issues:
# 1. JWT secret missing
# 2. Invalid datadir
# 3. Slow startup

# Wait longer for geth to become healthy
docker ps | grep snapshot-geth
# Should show "healthy" in status column after 30-60 seconds

# If "unhealthy" persists, check health check
docker inspect snapshot-geth | jq '.[0].State.Health'

# Manual health check test
docker exec snapshot-geth wget -q -O - http://localhost:8545

# If manual test works but container unhealthy, restart
docker restart snapshot-geth
sleep 30
docker-compose -f snapshots/<snapshot-dir>/docker-compose.snapshot.yml up -d
```

---

### "invalid command: geth" or "invalid command: lighthouse"

**Error in logs:**
```
invalid command: "geth"
invalid command: "lighthouse"
```

**Cause:** Docker Compose command syntax issue (multiline vs array).

**Solution:**

This should be fixed in the latest version. Verify:

```bash
# Check compose file uses array format
head -100 snapshots/<snapshot-dir>/docker-compose.snapshot.yml

# Should see:
#   command:
#     - "--http"
#     - "--http.addr=0.0.0.0"
#     ...

# NOT:
#   command: |
#     geth
#       --http
#       ...

# If incorrect, regenerate compose file
/home/aigent/kurtosis-cdk/snapshot/scripts/generate-compose.sh \
  snapshots/<snapshot-dir>/discovery.json \
  snapshots/<snapshot-dir>

# Restart
cd snapshots/<snapshot-dir>
docker-compose -f docker-compose.snapshot.yml down
docker-compose -f docker-compose.snapshot.yml up -d
```

---

## Runtime Issues

### Blocks Not Progressing

**Symptom:** Block number doesn't increase over time.

**Diagnosis:**
```bash
# Check if all services are running
docker ps | grep snapshot-

# All three should show "Up" status

# Check validator is attesting
docker logs snapshot-validator | grep -i "successfully published attestation"

# Check beacon is processing
docker logs snapshot-beacon | grep -i "head beacon block"

# Check geth is importing
docker logs snapshot-geth | grep -i "imported new chain segment"
```

**Common Causes:**

**1. Validator not loaded:**
```bash
# Check validator logs for errors
docker logs snapshot-validator | grep -i error

# Verify validator keys loaded
docker logs snapshot-validator | grep -i "voting keypairs"
# Should show: "Enabled validator voting keypairs count: <number>"
```

**2. Beacon not connected to execution:**
```bash
# Check beacon logs
docker logs snapshot-beacon | grep -i "execution"

# Should see: "Execution payload not received"
# This is OK if waiting for geth to sync

# Check JWT authentication
docker logs snapshot-beacon | grep -i "jwt"
docker logs snapshot-geth | grep -i "jwt"
```

**3. Fork choice issue:**
```bash
# Check beacon fork choice
docker logs snapshot-beacon | grep -i "fork choice"

# May need to wait for finalization
# Blocks should progress even if not finalizing
```

**Solution:**
```bash
# Restart all services
cd snapshots/<snapshot-dir>
docker-compose -f docker-compose.snapshot.yml restart

# Wait 60 seconds
sleep 60

# Check again
curl -s http://localhost:8545 \
  -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  | jq
```

---

### RPC Not Accessible

**Symptom:** Can't connect to http://localhost:8545

**Diagnosis:**
```bash
# Check if geth container is running
docker ps | grep snapshot-geth

# Check if port is bound
docker port snapshot-geth 8545

# Should show: 8545/tcp -> 0.0.0.0:8545

# Check if geth is listening
docker exec snapshot-geth netstat -tuln | grep 8545

# Should show LISTEN on port 8545

# Test connection inside container
docker exec snapshot-geth wget -q -O - http://localhost:8545
```

**Solutions:**

**If container not running:**
```bash
docker start snapshot-geth
```

**If port not bound:**
```bash
# Check docker-compose.yml has ports section
grep -A 10 "ports:" snapshots/<snapshot-dir>/docker-compose.snapshot.yml

# Should see:
#   ports:
#     - "8545:8545"

# Recreate if needed
cd snapshots/<snapshot-dir>
docker-compose -f docker-compose.snapshot.yml down
docker-compose -f docker-compose.snapshot.yml up -d
```

**If firewall issue:**
```bash
# Test from host
telnet localhost 8545

# If fails, check firewall
sudo iptables -L | grep 8545
# Or on systems with ufw
sudo ufw status
```

---

### High Memory Usage

**Symptom:** Docker consuming excessive memory (>8 GB per container).

**Cause:** Geth or Beacon consuming memory based on chain state.

**Solutions:**

**1. Monitor resource usage:**
```bash
# Check Docker stats
docker stats snapshot-geth snapshot-beacon snapshot-validator

# Should see reasonable values:
# geth: 1-3 GB
# beacon: 1-2 GB
# validator: 100-500 MB
```

**2. Adjust Docker limits (if needed):**
```bash
# Edit compose file to add resource limits
cd snapshots/<snapshot-dir>

# Add to each service:
#   deploy:
#     resources:
#       limits:
#         memory: 4G
#       reservations:
#         memory: 2G

# Restart
docker-compose -f docker-compose.snapshot.yml down
docker-compose -f docker-compose.snapshot.yml up -d
```

**3. Check for memory leaks:**
```bash
# Monitor over time
watch -n 5 'docker stats --no-stream snapshot-geth snapshot-beacon'

# If continuously increasing, may need to:
# - Restart services periodically
# - Use newer image versions
# - Investigate geth/lighthouse issues
```

---

## Verification Issues

### "Initial block matches checkpoint" fails

**Symptom:** Verification test fails because block number is behind checkpoint.

**Possible Causes:**
1. Snapshot restored to earlier state
2. Chain reorg occurred
3. Corrupted datadir

**Investigation:**
```bash
# Check expected block
cat snapshots/<snapshot-dir>/metadata/checkpoint.json | jq '.l1_state.block_number'

# Check current block
curl -s http://localhost:8545 \
  -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  | jq -r '.result' | xargs printf '%d\n'

# Check geth logs for any issues
docker logs snapshot-geth | grep -E "ERROR|WARN" | tail -20
```

**Solution:**

If current block is slightly behind (<10 blocks), this is normal - wait for sync:
```bash
# Wait 30 seconds
sleep 30

# Check again - should be at or past checkpoint
```

If significantly behind, datadir may be corrupted:
```bash
# Recreate snapshot
cd /home/aigent/kurtosis-cdk
./snapshot/snapshot.sh <enclave-name> --tag recreated
```

---

### "Blocks continue progressing" fails

**Symptom:** Block number doesn't increase after 10 seconds.

**See:** [Blocks Not Progressing](#blocks-not-progressing) above.

---

### "Beacon API accessible" fails

**Symptom:** Cannot connect to http://localhost:4000

**Diagnosis:**
```bash
# Check beacon container
docker ps | grep snapshot-beacon

# Check beacon health
docker exec snapshot-beacon wget -q -O - http://localhost:4000/eth/v1/node/health

# Check logs
docker logs snapshot-beacon | tail -50
```

**Solutions:**

**If beacon not ready:**
```bash
# Beacon takes longer to start than geth
# Wait 60 seconds
sleep 60

# Try again
curl http://localhost:4000/eth/v1/node/health
```

**If beacon error:**
```bash
# Check if connected to execution
docker logs snapshot-beacon | grep -i "execution"

# Should see successful connection messages

# Check if datadir valid
docker logs snapshot-beacon | grep -E "ERROR|Fatal"

# Restart if needed
docker restart snapshot-beacon
```

---

## Performance Issues

### Slow Snapshot Creation (>5 minutes)

**Normal times:**
- Discovery: 1-2 seconds
- Metadata collection: 1-2 seconds
- State extraction: 10-60 seconds (depends on datadir size)
- Metadata generation: 1-5 seconds
- Image build: 10-30 seconds per image
- Compose generation: 1-2 seconds
- **Total: 30-90 seconds typical**

**If slower:**

**1. Check disk I/O:**
```bash
# Monitor disk usage during snapshot
iostat -x 1

# Look for high %util or long await times

# If on slow disk (HDD), consider:
# - Using SSD
# - Using --out to target faster disk
```

**2. Check Docker performance:**
```bash
# Check Docker storage driver
docker info | grep "Storage Driver"

# overlay2 is recommended
# If using aufs or devicemapper, may be slower

# Check available space
df -h /var/lib/docker
```

**3. Large datadirs:**
```bash
# Check datadir sizes in source containers
docker exec <geth-container> du -sh /data/geth/execution-data
docker exec <beacon-container> du -sh /data/lighthouse/beacon-data

# If very large (>10 GB each):
# - This is expected for long-running chains
# - Snapshot time will be proportional to size
# - Consider snapshotting earlier in chain lifecycle
```

---

### Slow Image Build (>2 minutes per image)

**Diagnosis:**
```bash
# Check Docker build cache
docker system df

# Check available disk space
df -h

# Monitor during build
docker system events --since '5m' --filter 'type=image'
```

**Solutions:**

**1. Clear Docker cache (if excessive):**
```bash
# WARNING: This removes ALL unused images/containers
docker system prune -a

# Or more selective:
docker image prune -a --filter "until=24h"
```

**2. Use faster storage:**
```bash
# Move Docker data directory to SSD
# (requires Docker restart and reconfiguration)
```

---

## Data Integrity Issues

### Checksum Verification Fails

**Symptom:** SHA256 mismatch when verifying datadirs.

**Check:**
```bash
cd snapshots/<snapshot-dir>

# Verify checksums
cd datadirs
sha256sum -c ../metadata/manifest.sha256

# Should output:
# geth.tar: OK
# lighthouse_beacon.tar: OK
# lighthouse_validator.tar: OK
```

**If mismatch:**
```bash
# Tarballs may be corrupted

# Check tar files are valid
tar -tzf geth.tar | head
tar -tzf lighthouse_beacon.tar | head
tar -tzf lighthouse_validator.tar | head

# If corrupted, recreate snapshot
cd /home/aigent/kurtosis-cdk
./snapshot/snapshot.sh <enclave-name> --tag recovered
```

---

## System Issues

### "Docker is not running"

**Error:**
```
ERROR: Docker is not running or not accessible
```

**Solution:**
```bash
# Check Docker status
docker info

# If not running, start Docker daemon
sudo systemctl start docker
# Or on Mac: start Docker Desktop

# Verify
docker ps

# Retry snapshot
./snapshot/snapshot.sh <enclave-name>
```

---

### "Command not found: jq"

**Error:**
```
ERROR: Required command 'jq' not found
```

**Solution:**
```bash
# Install jq
# Ubuntu/Debian:
sudo apt-get install jq

# macOS:
brew install jq

# CentOS/RHEL:
sudo yum install jq

# Verify installation
jq --version

# Retry snapshot
./snapshot/snapshot.sh <enclave-name>
```

---

### Out of Disk Space

**Error:**
```
ERROR: No space left on device
```

**Solution:**
```bash
# Check disk usage
df -h

# Clean up Docker
docker system prune -a --volumes

# Remove old snapshots
rm -rf snapshots/old-snapshot-*

# Remove unused Docker images
docker images | grep snapshot- | awk '{print $3}' | xargs docker rmi

# Use different output directory with more space
./snapshot/snapshot.sh <enclave-name> --out /mnt/large-disk/snapshots
```

---

## Getting Help

If you encounter an issue not covered here:

### 1. Collect Diagnostics

```bash
# Create diagnostic bundle
mkdir snapshot-diagnostics

# Snapshot log
cp snapshots/<snapshot-dir>/snapshot.log snapshot-diagnostics/

# Container logs
docker-compose -f snapshots/<snapshot-dir>/docker-compose.snapshot.yml logs \
  > snapshot-diagnostics/containers.log 2>&1

# System info
docker version > snapshot-diagnostics/system.txt
docker info >> snapshot-diagnostics/system.txt
kurtosis version >> snapshot-diagnostics/system.txt
df -h >> snapshot-diagnostics/system.txt
docker ps -a >> snapshot-diagnostics/system.txt

# Compress
tar -czf snapshot-diagnostics.tar.gz snapshot-diagnostics/
```

### 2. Check Documentation

- `snapshot/README.md` - Technical details
- `snapshot/QUICKSTART.md` - Usage examples
- `snapshot/TEST_PLAN.md` - Testing procedures

### 3. Review Logs

```bash
# Main snapshot log
cat snapshots/<snapshot-dir>/snapshot.log

# Specific script logs (if available)
tail -100 snapshots/<snapshot-dir>/snapshot.log | grep "ERROR"

# Container logs
docker logs snapshot-geth 2>&1 | tail -50
docker logs snapshot-beacon 2>&1 | tail -50
docker logs snapshot-validator 2>&1 | tail -50
```

### 4. Test Manually

Run individual scripts to isolate the issue:

```bash
cd /home/aigent/kurtosis-cdk

# Test discovery
./snapshot/scripts/discover-containers.sh <enclave-name> /tmp/discovery.json
cat /tmp/discovery.json | jq

# Test extraction (will stop containers!)
# ./snapshot/scripts/extract-state.sh /tmp/discovery.json /tmp/test-snapshot

# Test metadata
# ./snapshot/scripts/generate-metadata.sh /tmp/discovery.json /tmp/test-snapshot

# Test image build
# ./snapshot/scripts/build-images.sh /tmp/discovery.json /tmp/test-snapshot

# Test compose generation
# ./snapshot/scripts/generate-compose.sh /tmp/discovery.json /tmp/test-snapshot
```

---

## Prevention Tips

### Best Practices

1. **Check disk space before snapshotting:**
   ```bash
   df -h | grep -E 'Filesystem|/$'
   # Ensure at least 10 GB free
   ```

2. **Stop other Docker containers if low on resources:**
   ```bash
   docker ps --format "{{.Names}}" | grep -v -E "(el-|cl-|vc-)" | xargs docker stop
   ```

3. **Use descriptive tags:**
   ```bash
   ./snapshot/snapshot.sh cdk --tag "pre-deployment-$(date +%Y%m%d)"
   ```

4. **Keep snapshots organized:**
   ```bash
   ./snapshot/snapshot.sh cdk --out /backups/snapshots/$(date +%Y-%m)
   ```

5. **Test snapshots immediately after creation:**
   ```bash
   ./snapshot/snapshot.sh cdk --tag test-123
   ./snapshot/verify.sh snapshots/cdk-*-test-123/
   ```

6. **Document important snapshots:**
   ```bash
   echo "Snapshot taken after contract deployment XYZ" \
     > snapshots/cdk-20260202-120000/NOTES.txt
   ```

---

## Common Patterns

### Snapshot Before Major Changes

```bash
# Before deployment
./snapshot/snapshot.sh cdk --tag pre-deployment

# Deploy contracts
kurtosis run --enclave cdk .
# ... deploy ...

# After deployment
./snapshot/snapshot.sh cdk --tag post-deployment

# If deployment fails, restore from pre-deployment snapshot
```

### Regular Backup Schedule

```bash
# Daily snapshot script
#!/bin/bash
TAG="daily-$(date +%Y%m%d)"
./snapshot/snapshot.sh cdk --tag "$TAG" --out /backups/daily/

# Clean old snapshots (keep 7 days)
find /backups/daily -name "cdk-*" -mtime +7 -exec rm -rf {} \;
```

### CI/CD Integration

```bash
# In your CI pipeline
- name: Create test snapshot
  run: |
    kurtosis run --enclave ci-test .
    sleep 60  # Wait for initialization
    ./snapshot/snapshot.sh ci-test --tag "ci-${GITHUB_RUN_ID}"

- name: Verify snapshot
  run: |
    ./snapshot/verify.sh snapshots/ci-test-*-ci-${GITHUB_RUN_ID}/

- name: Cleanup
  run: |
    kurtosis enclave rm ci-test
    docker images | grep snapshot- | awk '{print $3}' | xargs docker rmi -f
```

---

This troubleshooting guide covers the most common issues. For additional help, check the main README or create an issue with your diagnostic bundle.
