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

>/tmp/create_op_genesis.py cat <<EOF
import json

genesis_orig = "/opt/contract-deploy/op-original-genesis.json"
genesis_polygon = "/opt/zkevm/sovereign-predeployed-genesis.json"
genesis_output = "/opt/zkevm/op-genesis.json"

with open(genesis_orig, "r") as fg_orig:
    genesis = json.load(fg_orig)
with open(genesis_polygon, "r") as fg_polygon:
    genesis_polygon = json.load(fg_polygon)

for item in genesis_polygon["genesis"]:
    addr = item["address"][2:]
    genesis["alloc"][addr] = {
        "balance": hex(int(item["balance"])),
    }
    if "nonce" in item:
        genesis["alloc"][addr]["nonce"] = hex(int(item["nonce"]))
    if "bytecode" in item:
        genesis["alloc"][addr]["code"] = item["bytecode"]
    if "storage" in item:
        genesis["alloc"][addr]["storage"] = item["storage"]

with open(genesis_output, "w") as fg_output:
    json.dump(genesis, fg_output, indent=4)
    print(f"OP Genesis file saved: {genesis_output}")
EOF

python3 /tmp/create_op_genesis.py
