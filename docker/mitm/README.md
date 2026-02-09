# Custom MITM Proxy Image

This directory contains a custom mitmproxy Docker image that extends the official `mitmproxy/mitmproxy:11.1.3` image with additional Python packages required for **intelligent transaction replay**.

## Purpose

The custom image adds `eth-account` and `eth-utils` packages, which enable the transaction capture addon (`scripts/mitm/tx_capture.py`) to:
- Extract sender addresses from raw transactions using `Account.recover_transaction`
- Enable intelligent balance polling during snapshot replay
- Improve transaction replay reliability by waiting for actual funding dependencies

## Building the Image

```bash
# Build with default name
./build.sh

# Or specify a custom image name
./build.sh my-registry/kurtosis-mitm:v1.0
```

## Using the Custom Image

1. **Build the image** (if not already built):
   ```bash
   cd docker/mitm
   ./build.sh
   ```

2. **Update Kurtosis configuration** in `src/package_io/constants.star`:
   ```python
   "mitm_image": "kurtosis-mitm:with-eth-account",
   ```

3. **Run Kurtosis with transaction capture**:
   ```bash
   kurtosis run --enclave my-enclave . '{"deploy_mitm": true, "mitm_capture_transactions": true}'
   ```

## What's Included

- **Base**: `mitmproxy/mitmproxy:11.1.3`
- **Added packages**:
  - `eth-account` - For transaction signature recovery
  - `eth-utils` - For Ethereum address utilities

## Benefits

With this custom image, transaction capture will:
- Store sender addresses alongside raw transactions in `transactions.jsonl`
- Enable intelligent retry logic that polls account balances
- Reduce wasted retry attempts on unfunded transactions
- Improve snapshot replay speed and reliability

## Alternative: Use Official Image

If you cannot use the custom image, the transaction capture addon will still work with the official `mitmproxy/mitmproxy:11.1.3` image. However, sender address extraction will fail gracefully and return "unknown", causing the replay script to fall back to blind retry logic instead of intelligent balance polling.
