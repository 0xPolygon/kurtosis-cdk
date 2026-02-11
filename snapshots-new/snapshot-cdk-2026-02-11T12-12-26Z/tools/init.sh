#!/bin/bash
set -euo pipefail

echo "===== Snapshot Init ====="

# Fresh timestamp (integer, not hex)
GENESIS_TIME=$(date +%s)
echo "Genesis time: $GENESIS_TIME"

# JWT secret
echo "Generating JWT secret..."
openssl rand -hex 32 > /runtime/jwt.hex

# Patch EL genesis timestamp (as INTEGER)
echo "Patching L1 EL genesis timestamp..."
jq --arg ts "$GENESIS_TIME" '.timestamp = ($ts | tonumber)' \
  /snapshot/el/genesis.template.json > /runtime/el_genesis.json

# Patch L2 genesis timestamp if OP stack is present
if ls /snapshot/op/genesis-*.json >/dev/null 2>&1; then
  echo "Patching L2 genesis timestamp..."
  mkdir -p /runtime/op
  for l2_genesis in /snapshot/op/genesis-*.json; do
    l2_basename=$(basename "$l2_genesis")
    jq --arg ts "$GENESIS_TIME" '.timestamp = ($ts | tonumber)' "$l2_genesis" > "/runtime/op/${l2_basename}"
  done
  echo "✅ L2 genesis patched"
fi

# Copy CL config and metadata (no patching - eth2-testnet-genesis uses --eth1-timestamp)
echo "Copying CL config and metadata..."
mkdir -p /runtime/cl
cp /snapshot/cl/config.yaml /runtime/cl/config.yaml
cp /snapshot/cl/deposit_contract_block.txt /runtime/cl/ 2>/dev/null || true
cp /snapshot/cl/deposit_contract_block_hash.txt /runtime/cl/ 2>/dev/null || true
cp /snapshot/cl/deposit_contract.txt /runtime/cl/ 2>/dev/null || true

# Generate CL genesis.ssz using eth-genesis-state-generator (reads timestamp from genesis.json)
echo "Generating CL genesis.ssz with timestamp=$GENESIS_TIME..."
eth-genesis-state-generator beaconchain \
  --config=/snapshot/cl/config.yaml \
  --eth1-config=/runtime/el_genesis.json \
  --mnemonics=/snapshot/val/mnemonics.yaml \
  --state-output=/runtime/cl/genesis.ssz

echo "Genesis.ssz created successfully"

# Generate validator keystores using eth2-val-tools
echo "Generating validator keystores..."
# Remove any existing validator data to allow clean regeneration
rm -rf /runtime/val/validators /runtime/val/secrets
mkdir -p /runtime/val/secrets

# Run eth2-val-tools from a unique clean directory
# NOTE: Do NOT pre-create /runtime/val/validators - eth2-val-tools needs to create it itself
WORK_DIR="/tmp/val-gen-$$-$RANDOM"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
eth2-val-tools keystores \
  --insecure \
  --prysm-pass="password" \
  --out-loc=/runtime/val/validators \
  --source-mnemonic="abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about" \
  --source-min=0 \
  --source-max=1
cd /
rm -rf "$WORK_DIR"

# Create validator_definitions.yml for Lighthouse
# eth2-val-tools doesn't create this file, so we need to generate it ourselves
echo "Creating validator_definitions.yml for Lighthouse..."
python3 <<'EOF_PYTHON'
import yaml
import json
import os
import glob

try:
    # Find all keystores in keys directory
    keystores = glob.glob('/runtime/val/validators/keys/*/voting-keystore.json')
    print(f"Found {len(keystores)} keystores", file=os.sys.stderr)

    validators = []
    for keystore_path in keystores:
        # Extract pubkey from directory name
        pubkey_dir = os.path.dirname(keystore_path)
        pubkey = os.path.basename(pubkey_dir)

        print(f"Processing validator {pubkey[:10]}...", file=os.sys.stderr)

        # Check if secret file exists
        secret_path = f'/runtime/val/validators/secrets/{pubkey}'
        if not os.path.exists(secret_path):
            print(f"WARNING: Secret file not found for {pubkey}", file=os.sys.stderr)
            continue

        # Create validator definition
        val_def = {
            'enabled': True,
            'voting_public_key': pubkey,
            'description': pubkey,
            'type': 'local_keystore',
            'voting_keystore_path': keystore_path,
            'voting_keystore_password_path': secret_path
        }
        validators.append(val_def)

    if len(validators) == 0:
        print("ERROR: No validators found!", file=os.sys.stderr)
        os.sys.exit(1)

    # Write validator_definitions.yml
    with open('/runtime/val/validators/validator_definitions.yml', 'w') as f:
        yaml.dump(validators, f, default_flow_style=False)

    print(f"Successfully created validator_definitions.yml with {len(validators)} validators", file=os.sys.stderr)
except Exception as e:
    print(f"ERROR creating validator_definitions.yml: {e}", file=os.sys.stderr)
    import traceback
    traceback.print_exc(file=os.sys.stderr)
    os.sys.exit(1)
EOF_PYTHON

if [ $? -ne 0 ]; then
  echo "Failed to create validator definitions!"
  exit 1
fi

echo "Validator keystores created: $(ls -1 /runtime/val/validators/keys/ 2>/dev/null | wc -l)"

# Mark ready
touch /runtime/.ready
echo "✅ Init complete - ready to start"
