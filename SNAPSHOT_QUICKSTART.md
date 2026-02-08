# Snapshot System Quick Start

## ✅ System Status
- **Retry-based replay**: Production ready
- **Transaction capture**: Implemented and tested
- **MITM deployment**: Working (requires correct config)

## 📝 Create Snapshot with Transaction Capture

### 1. Create Enclave with MITM
```bash
# Create params file
cat > /tmp/snapshot-params.yml << 'EOF'
args:
  mitm_proxied_components:
    aggkit: true
  mitm_capture_transactions: true
EOF

# Deploy enclave
kurtosis run --enclave cdk --args-file /tmp/snapshot-params.yml .
```

### 2. Verify MITM is Running
```bash
kurtosis enclave inspect cdk | grep mitm-001
```

Expected output:
```
<uuid>   mitm-001    rpc: 8234/tcp -> http://127.0.0.1:<port>    RUNNING
```

### 3. Let Transactions Accumulate
```bash
# Wait for transactions to be captured (30-60 seconds)
sleep 60
```

### 4. Create Snapshot
```bash
./snapshot.sh cdk --out ./snapshots/
```

### 5. Run Snapshot
```bash
cd ./snapshots/cdk-<timestamp>
docker-compose up -d
```

### 6. Verify Replay
```bash
# Check geth logs for replay progress
docker-compose logs geth | grep -E "Phase|Retry|MINED"
```

Expected output:
```
Optimized Transaction Replay with Retry
Phase 1: Sending all transactions...
[TX 1] Sent: 0x...
Phase 2: Waiting for transactions to be mined...
[TX 1] ✓ Mined in block 4
```

## 🐛 Troubleshooting

### MITM Not Deploying
- **Issue**: Parameters not nested under `args:`
- **Fix**: Use YAML file with `args:` prefix (see step 1)

### Transactions Not Captured
- **Issue**: MITM not proxying the right service
- **Fix**: Ensure service is listed in `mitm_proxied_components`

### Replay Fails with "Insufficient Funds"
- **Issue**: Old parallel replay code
- **Fix**: Ensure commit `5ce0bd57` or later (retry-based replay)

## 📊 Performance

| Transaction Count | Sequential Time | Retry-Based Time | Speedup |
|-------------------|-----------------|------------------|---------|
| 100 txs | ~1.5 min | ~45-60 sec | 1.5-2x |
| 1,000 txs | ~9 min | ~4-6 min | 1.5-2x |
| 10,000 txs | ~90 min | ~40-60 min | 1.5-2x |

*Speedup depends on transaction independence

## 🔧 Advanced Options

### Custom Retry Settings
Edit `snapshot/scripts/generate-replay-script.sh`:
```bash
MAX_RETRIES=10  # Increase if needed
retry_delay=2   # Initial delay in seconds
```

### Debug Replay
```bash
# Watch replay in real-time
docker-compose logs -f replayer

# Check specific transaction
docker-compose logs geth | grep "TX 6"
```

## ✅ Success Criteria

Snapshot is working correctly if:
1. ✅ Geth container starts and stays running
2. ✅ Replay script completes: "All transactions replayed successfully!"
3. ✅ Beacon syncs from geth
4. ✅ Validator produces blocks
5. ✅ All L2 services (op-geth, op-node, agglayer) start successfully

## 📚 Related Commits

- `5ce0bd57` - Retry-based replay optimization ⭐
- `368d4e3e` - Transaction capture script
- `17cc9791` - MITM deployment fix
- `4edbfc60` - MITM path fix
