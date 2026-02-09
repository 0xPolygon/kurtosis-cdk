# Snapshot System Troubleshooting Guide

This guide helps diagnose and fix common issues with the Kurtosis CDK snapshot system.

## Table of Contents

- [Snapshot Creation Issues](#snapshot-creation-issues)
- [Init Container Issues](#init-container-issues)
- [Geth Issues](#geth-issues)
- [Lighthouse Issues](#lighthouse-issues)
- [Chain Operation Issues](#chain-operation-issues)

---

## Snapshot Creation Issues

### Error: "debug_dumpBlock does not exist/is not available"

**Symptom**: Snapshot creation fails with:
```
Error: debug_dumpBlock failed
```

**Cause**: Debug namespace not enabled on source geth.

**Solution**: Enable debug API on the source Kurtosis enclave.

In your Kurtosis params file:
```yaml
participants:
  - el_type: geth
    el_extra_params:
      - "--http.api=eth,net,web3,debug,txpool"
```

Then restart the enclave:
```bash
kurtosis clean -a
kurtosis run --enclave my-enclave . --args-file params.yaml
```

### Error: "Enclave not found"

**Symptom**:
```
Error: Enclave 'my-enclave' not found
```

**Solution**: Check enclave name and status:
```bash
kurtosis enclave ls
```

Use the exact enclave name shown in the list.

### Error: "Could not discover geth RPC endpoint"

**Symptom**:
```
Error: Could not discover geth RPC endpoint
```

**Cause**: Service name or port ID doesn't match the enclave.

**Solution**: Override with environment variables:
```bash
# List services to find correct name
kurtosis enclave inspect my-enclave

# Use custom service name
GETH_SVC=my-geth-service PORT_ID=http ./snapshot/snapshot.sh my-enclave
```

Common service names:
- `el-1-geth-lighthouse`
- `el-geth-1`
- `geth`

Common port IDs:
- `rpc`
- `http`
- `http-rpc`

### Error: "Failed to get chainId/block number"

**Symptom**: RPC calls fail during snapshot creation

**Cause**: Geth not responding or not fully synced

**Solution**:
1. Verify geth is running:
   ```bash
   kurtosis service inspect my-enclave el-1-geth-lighthouse
   ```

2. Test RPC manually:
   ```bash
   GETH_RPC=$(kurtosis port print my-enclave el-1-geth-lighthouse rpc)
   cast block-number --rpc-url $GETH_RPC
   ```

3. Wait for chain to produce blocks (at least 1-2 minutes after enclave start)

### Error: "State dump too large"

**Symptom**: `debug_dumpBlock` takes very long or fails

**Cause**: Chain has large state (many accounts, contracts, storage)

**Solution**:
- Increase timeout in snapshot script
- Use earlier block number: `cast rpc debug_dumpBlock 100` instead of latest
- Consider creating snapshot earlier (less state accumulation)

---

## Init Container Issues

### Error: "Init container exited with code 1"

**Symptom**:
```bash
docker-compose ps
# Shows: snapshot-init ... exited (1)
```

**Diagnosis**: Check init logs:
```bash
docker-compose logs init
```

Common causes:

#### 1. Missing eth2-testnet-genesis binary

**Error in logs**:
```
/init.sh: line X: eth2-testnet-genesis: command not found
```

**Solution**: Rebuild init image:
```bash
docker rmi kurtosis-cdk-snapshot-init:latest
cd /path/to/kurtosis-cdk
docker build -t kurtosis-cdk-snapshot-init:latest -f snapshot/Dockerfile.init snapshot/
```

#### 2. Invalid genesis template

**Error in logs**:
```
jq: parse error
```

**Solution**: Check genesis template is valid JSON:
```bash
jq empty snapshot-dir/el/genesis.template.json
```

If invalid, re-run snapshot creation.

#### 3. CL genesis generation failed

**Error in logs**:
```
Error generating genesis.ssz
```

**Solution**: Check config.yaml format:
```bash
cat snapshot-dir/cl/config.yaml
```

Ensure all required fields present:
- `PRESET_BASE`
- `SECONDS_PER_SLOT`
- `DEPOSIT_CHAIN_ID`
- `DEPOSIT_NETWORK_ID`

#### 4. Validator keystore generation failed

**Error in logs**:
```
eth2-val-tools: command not found
```

**Solution**: Rebuild init image (same as #1 above).

### Init succeeds but runtime directory empty

**Symptom**: Init exits 0 but `runtime/` directory is empty

**Cause**: Volume mount issue

**Solution**:
1. Check docker-compose.yml volumes:
   ```yaml
   volumes:
     - ./runtime:/runtime:rw
   ```

2. Check permissions:
   ```bash
   ls -la runtime/
   # Should be writable
   ```

3. Recreate runtime directory:
   ```bash
   rm -rf runtime
   mkdir runtime
   docker-compose up --force-recreate
   ```

---

## Geth Issues

### Error: "Geth not starting"

**Symptom**: Geth container exits immediately

**Diagnosis**:
```bash
docker-compose logs geth
```

Common causes:

#### 1. Genesis init failed

**Error in logs**:
```
Fatal: Failed to write genesis block
```

**Solution**: Check genesis file:
```bash
jq empty runtime/el_genesis.json
```

Verify timestamp is integer (not string):
```bash
jq '.timestamp' runtime/el_genesis.json
# Should be: 1234567890 (number)
# Not: "1234567890" (string) or "0x..." (hex)
```

#### 2. Data directory issue

**Error in logs**:
```
Failed to open database
```

**Solution**: Geth uses ephemeral `/tmp/geth-data`. If this fails, try:
```bash
docker-compose down -v
docker-compose up --force-recreate
```

### Error: "Geth healthy but no blocks"

**Symptom**: Geth RPC responds but `cast block-number` returns 0

**Cause**: Mining not enabled or validator not producing

**Solution**:
1. Check geth is mining:
   ```bash
   docker-compose logs geth | grep -i mining
   ```

2. Check lighthouse validator is running:
   ```bash
   docker-compose ps | grep lighthouse-vc
   ```

3. Check validator has keys:
   ```bash
   docker-compose logs lighthouse-vc | grep -i "Initialized validators"
   ```

### Error: "Geth healthcheck failing"

**Symptom**:
```bash
docker-compose ps
# Shows: geth ... (unhealthy)
```

**Diagnosis**:
```bash
docker-compose exec geth wget -q -O - http://localhost:8545
```

**Solution**:
- If connection refused: Geth crashed, check logs
- If timeout: Geth starting slow, wait longer
- If error response: Check RPC is enabled in command

---

## Lighthouse Issues

### Error: "Lighthouse beacon not syncing"

**Symptom**: Beacon logs show "Execution client not synced"

**Diagnosis**:
```bash
docker-compose logs lighthouse-bn | tail -50
```

Common causes:

#### 1. JWT mismatch

**Check**:
```bash
cat runtime/jwt.hex
# Should be 64 hex characters
```

**Solution**: Regenerate:
```bash
docker-compose down
rm runtime/jwt.hex
./up.sh
```

#### 2. Engine API not accessible

**Check**:
```bash
docker-compose exec lighthouse-bn curl http://geth:8551
```

**Solution**: Verify geth is healthy:
```bash
docker-compose ps geth
```

#### 3. Genesis mismatch

**Error in logs**:
```
Genesis state mismatch
```

**Solution**: Ensure genesis.ssz generated with same timestamp as geth:
```bash
# Check EL genesis time
jq '.timestamp' runtime/el_genesis.json

# Check CL genesis.ssz exists
ls -la runtime/cl/genesis.ssz
```

Regenerate if mismatch:
```bash
docker-compose down
rm -rf runtime/*
./up.sh
```

### Error: "Lighthouse validator not attesting"

**Symptom**: No blocks being produced after 2+ minutes

**Diagnosis**:
```bash
docker-compose logs lighthouse-vc
```

Common causes:

#### 1. No validators loaded

**Error in logs**:
```
No validators initialized
```

**Solution**: Check keystores:
```bash
ls -la runtime/val/validators/
ls -la runtime/val/secrets/
```

Should show keystore-*.json files and corresponding secrets.

If empty, check init logs:
```bash
docker-compose logs init | grep -i keystore
```

#### 2. Beacon not synced

**Error in logs**:
```
Beacon node not synced
```

**Solution**: Wait for beacon to sync (check beacon logs). Validator won't attest until beacon is synced.

#### 3. Clock skew

**Error in logs**:
```
Validator duty at slot X but current slot is Y
```

**Solution**: System clock may be off. Check:
```bash
date
# Should match current time
```

If in container/VM, sync clock:
```bash
sudo ntpdate -s time.nist.gov  # Or your NTP server
```

---

## Chain Operation Issues

### Chain produces blocks slowly

**Symptom**: Blocks produced every 10+ seconds instead of 1-2s

**Cause**: Slow validator or beacon sync lag

**Check slot time**:
```bash
cat snapshot-dir/cl/config.yaml | grep SECONDS_PER_SLOT
```

Should be 1 or 2.

**Check beacon sync**:
```bash
docker-compose logs lighthouse-bn | grep -i "synced"
```

Should show "Execution client synced".

### Chain stops after a few blocks

**Symptom**: Blocks produced initially, then stops

**Diagnosis**:
```bash
# Check all services still running
docker-compose ps

# Check for errors
docker-compose logs --tail=50
```

Common causes:
- Geth crashed (out of memory, panic)
- Validator crashed (slashing protection issue)
- Network partition (containers can't talk)

**Solution**: Check logs for errors and restart:
```bash
docker-compose down
./up.sh
```

### Can't connect to RPC

**Symptom**:
```bash
cast block-number --rpc-url http://localhost:8545
Error: connection refused
```

**Check port binding**:
```bash
docker-compose ps
# Should show: 0.0.0.0:8545->8545/tcp
```

**Check geth is running**:
```bash
docker-compose logs geth | tail
```

**Try from within network**:
```bash
docker-compose exec lighthouse-bn curl http://geth:8545
```

If internal works but external doesn't, firewall issue.

### Blocks have wrong timestamps

**Symptom**: Block timestamps don't match current time

**Cause**: Genesis timestamp not set correctly

**Check**:
```bash
# Get current time
date +%s

# Get genesis time
jq '.timestamp' runtime/el_genesis.json

# Get latest block time
cast block latest --rpc-url http://localhost:8545 | grep timestamp
```

**Solution**: Regenerate with fresh timestamp:
```bash
docker-compose down
rm -rf runtime/*
./up.sh
```

---

## Performance Issues

### Init takes very long (>5 minutes)

**Cause**: Large alloc (many accounts) or slow genesis generation

**Solution**:
- Normal for large state dumps (>10k accounts)
- Consider optimizing alloc (remove empty accounts)
- Increase init timeout in docker-compose.yml:
  ```yaml
  init:
    deploy:
      resources:
        limits:
          memory: 4G  # Increase if needed
  ```

### Snapshot uses too much disk space

**Cause**: Large state dump

**Check size**:
```bash
du -sh snapshot-dir/el/state_dump.json
du -sh snapshot-dir/el/alloc.json
```

**Solution**:
- Snapshot earlier (less state)
- Prune empty accounts from alloc
- Compress snapshot directory for transfer:
  ```bash
  tar czf snapshot.tar.gz snapshot-dir/
  ```

---

## Getting Help

If you're stuck:

1. **Collect logs**:
   ```bash
   docker-compose logs > snapshot-logs.txt
   ```

2. **Check metadata**:
   ```bash
   cat snapshot-dir/metadata.json
   ```

3. **Verify environment**:
   ```bash
   docker --version
   docker-compose --version
   cast --version
   python3 --version
   ```

4. **Open GitHub issue** with:
   - Error message
   - Logs (snapshot-logs.txt)
   - Metadata (metadata.json)
   - Environment info

---

## Quick Reference

### Useful Commands

```bash
# Check service status
docker-compose ps

# Follow all logs
docker-compose logs -f

# Follow specific service
docker-compose logs -f geth

# Restart everything
docker-compose down && ./up.sh

# Force clean restart
docker-compose down -v && rm -rf runtime/* && ./up.sh

# Check block number
cast block-number --rpc-url http://localhost:8545

# Check latest block details
cast block latest --rpc-url http://localhost:8545

# Check beacon sync status
curl http://localhost:5052/eth/v1/node/syncing

# Execute command in container
docker-compose exec geth geth attach /tmp/geth-data/geth.ipc
```

### File Locations

- Genesis template: `snapshot-dir/el/genesis.template.json`
- CL config: `snapshot-dir/cl/config.yaml`
- Validator mnemonic: `snapshot-dir/val/mnemonics.yaml`
- Init script: `snapshot-dir/tools/init.sh`
- Runtime genesis: `snapshot-dir/runtime/el_genesis.json`
- JWT secret: `snapshot-dir/runtime/jwt.hex`
- CL genesis: `snapshot-dir/runtime/cl/genesis.ssz`
- Validator keys: `snapshot-dir/runtime/val/validators/`

### Common Patterns

**Full restart with clean state**:
```bash
docker-compose down -v
rm -rf runtime/*
./up.sh
```

**Check if chain is producing blocks**:
```bash
cast block-number --rpc-url http://localhost:8545
sleep 10
cast block-number --rpc-url http://localhost:8545
# Should increase
```

**Verify init completed successfully**:
```bash
docker-compose ps init
# Should show: exited (0)

ls runtime/
# Should show: jwt.hex, el_genesis.json, cl/, val/
```

**Check validator is loaded**:
```bash
docker-compose logs lighthouse-vc | grep "Initialized validators"
# Should show: Initialized validators: 1
```
