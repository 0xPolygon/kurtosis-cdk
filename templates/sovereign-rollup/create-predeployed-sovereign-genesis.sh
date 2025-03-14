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

with open(genesis_polygon, "r") as fg_polygon:
    genesis_polygon = json.load(fg_polygon)

allocs = {}
for item in genesis_polygon["genesis"]:
    addr = item["address"].lower()
    allocs[addr] = {
        "balance": hex(int(item["balance"])),
    }
    if "nonce" in item:
        allocs[addr]["nonce"] = hex(int(item["nonce"]))
    if "bytecode" in item:
        allocs[addr]["code"] = item["bytecode"]
    if "storage" in item:
        allocs[addr]["storage"] = item["storage"]

with open(predeployed_allocs, "w") as fg_output:
    json.dump(allocs, fg_output, indent=4)
    print(f"Predeployed Allocs file saved: {predeployed_allocs}")
EOF

python3 /tmp/create_op_allocs.py
