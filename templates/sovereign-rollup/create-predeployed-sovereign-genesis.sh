#!/bin/bash

cd /opt/zkevm-contracts || exit

# Extract the rollup manager address from the JSON file. .zkevm_rollup_manager_address is not available at the time of importing this script.
# So a manual extraction of polygonRollupManagerAddress is done here.
# Even with multiple op stack deployments, the rollup manager address can be retrieved from combined{{.deployment_suffix}}.json because it must be constant.
rollup_manager_addr="$(jq -r '.polygonRollupManagerAddress' "/opt/zkevm/combined{{.deployment_suffix}}.json")"

# Replace rollupManagerAddress with the extracted address
sed -i "s|\"rollupManagerAddress\": \".*\"|\"rollupManagerAddress\":\"$rollup_manager_addr\"|" /opt/contract-deploy/create-genesis-sovereign-params.json

# Required files to run the script
cp /opt/contract-deploy/create-genesis-sovereign-params.json /opt/zkevm-contracts/tools/createSovereignGenesis/create-genesis-sovereign-params.json
cp /opt/contract-deploy/sovereign-genesis.json /opt/zkevm-contracts/tools/createSovereignGenesis/genesis-base.json

# Run the script
npx hardhat run ./tools/createSovereignGenesis/create-sovereign-genesis.ts --network localhost

# Save the genesis file
genesis_file=$(find /opt/zkevm-contracts/tools/createSovereignGenesis/ -maxdepth 1 -type f -name 'genesis-rollupID*' 2>/dev/null | head -n 1)
if [[ -f "$genesis_file" ]]; then
    cp "$genesis_file" /opt/zkevm/sovereign-predeployed-genesis.json
    echo "Predeployed Genesis file saved: /opt/zkevm/sovereign-predeployed-genesis.json"
else
    echo "No matching Genesis file found!"
    exit 1
fi

# Save tool output file
output_file=$(find /opt/zkevm-contracts/tools/createSovereignGenesis/ -maxdepth 1 -type f -name 'output-rollupID*' 2>/dev/null | head -n 1)
if [[ -f "$output_file" ]]; then
    cp "$output_file" /opt/zkevm/create-sovereign-genesis-output.json
    echo "Output saved: /opt/zkevm/create-sovereign-genesis-output.json"
else
    echo "No matching Output file found!"
    exit 1
fi

>/tmp/create_op_allocs.py cat <<EOF
import json

genesis_polygon = "/opt/zkevm/sovereign-predeployed-genesis.json"
predeployed_allocs = "/opt/zkevm/predeployed_allocs.json"

# Load the genesis file
import json

with open(genesis_polygon, "r") as fg_polygon:
    genesis_polygon = json.load(fg_polygon)

allocs = {}

# Determine the correct part of the JSON to iterate over
if "genesis" in genesis_polygon:
    if isinstance(genesis_polygon["genesis"], list):
        items = genesis_polygon["genesis"]
    elif isinstance(genesis_polygon["genesis"], dict):
        items = genesis_polygon["genesis"].get("alloc", {})
    else:
        raise ValueError("Unexpected structure in 'genesis' field")
else:
    items = genesis_polygon

# Handle different possible structures
if isinstance(items, dict):
    for addr, data in items.items():
        addr = addr.lower()
        # Handle balance: ensure it's treated as a hex string
        balance = data.get("balance", "0x0")
        if isinstance(balance, str) and balance.startswith("0x"):
            balance_value = int(balance, 16)
        else:
            balance_value = int(balance)  # Assume decimal if not hex
        allocs[addr] = {"balance": hex(balance_value)}
        
        # Handle nonce: ensure it's treated as a hex string
        if "nonce" in data:
            nonce = data["nonce"]
            if isinstance(nonce, str) and nonce.startswith("0x"):
                nonce_value = int(nonce, 16)
            else:
                nonce_value = int(nonce)  # Assume decimal if not hex
            allocs[addr]["nonce"] = hex(nonce_value)
        
        if "bytecode" in data:
            allocs[addr]["code"] = data["bytecode"]
        if "storage" in data:
            allocs[addr]["storage"] = data["storage"]
elif isinstance(items, list):
    for item in items:
        if not isinstance(item, dict) or "address" not in item:
            continue
        addr = item["address"].lower()
        # Handle balance: ensure it's treated as a hex string
        balance = item.get("balance", "0x0")
        if isinstance(balance, str) and balance.startswith("0x"):
            balance_value = int(balance, 16)
        else:
            balance_value = int(balance)  # Assume decimal if not hex
        allocs[addr] = {"balance": hex(balance_value)}
        
        # Handle nonce: ensure it's treated as a hex string
        if "nonce" in item:
            nonce = item["nonce"]
            if isinstance(nonce, str) and nonce.startswith("0x"):
                nonce_value = int(nonce, 16)
            else:
                nonce_value = int(nonce)  # Assume decimal if not hex
            allocs[addr]["nonce"] = hex(nonce_value)
        
        if "bytecode" in item:
            allocs[addr]["code"] = item["bytecode"]
        if "storage" in item:
            allocs[addr]["storage"] = item["storage"]
else:
    raise ValueError("Unexpected JSON structure")

# Write the output file
with open(predeployed_allocs, "w") as fg_output:
    json.dump(allocs, fg_output, indent=4)
    print(f"Predeployed Allocs file saved: {predeployed_allocs}")
EOF

python3 /tmp/create_op_allocs.py
