#!/bin/bash
set -e

pushd /opt/zkevm-contracts || exit 1

# FIXME Just in case for now... ideally we don't need this but the base image is hacky right now
git config --global --add safe.directory /opt/zkevm-contracts

# Extract the rollup manager address from the JSON file. .agglayer_manager_address is not available at the time of importing this script.
# So a manual extraction of agglayerManagerAddress is done here.
# Even with multiple op stack deployments, the rollup manager address can be retrieved from combined{{.deployment_suffix}}.json because it must be constant.
rollup_manager_addr="$(jq -r '.agglayerManagerAddress' "/opt/zkevm/combined{{.deployment_suffix}}.json")"
chainID="$(jq -r '.chainID' "/opt/zkevm/create_rollup_parameters.json")"
rollup_id="$(cast call "$rollup_manager_addr" "chainIDToRollupID(uint64)(uint32)" "$chainID" --rpc-url "{{.l1_rpc_url}}")"
gas_token_addr="$(jq -r '.gasTokenAddress' "/opt/zkevm/combined{{.deployment_suffix}}.json")"

# Replace rollupManagerAddress with the extracted address
# sed -i "s|\"rollupManagerAddress\": \".*\"|\"rollupManagerAddress\":\"$rollup_manager_addr\"|" /opt/contract-deploy/create-genesis-sovereign-params.json
# jq --arg ruid "$rollup_id" '.rollupID = ($ruid | tonumber)'  /opt/contract-deploy/create-genesis-sovereign-params.json > /opt/contract-deploy/create-genesis-sovereign-params.json.tmp

# Extract AggOracle Committee member addresses as a JSON array
agg_oracle_committee_members=$(seq 0 $(( "{{ .agg_oracle_committee_total_members }}" - 1 )) | while read -r index; do
    cast wallet address --mnemonic "lab code glass agree maid neutral vessel horror deny frequent favorite soft gate galaxy proof vintage once figure diary virtual scissors marble shrug drop" --mnemonic-index "$index"
done | jq -R . | jq -s .)

# By default, the AggOracle sender will be "{{ .zkevm_l2_aggoracle_address }}", which is also the signer to update L2 GER.
# But any of the addresses from the aggOracleCommittee should be able to sign the transaction. This will require change to AggOracle.EVMSender.EthTxManager.PrivateKeys
# Append to aggOracleCommittee in the JSON file
jq --argjson addrs "$agg_oracle_committee_members" '
  .aggOracleCommittee += $addrs
' /opt/contract-deploy/create-genesis-sovereign-params.json > /opt/contract-deploy/create-genesis-sovereign-params.json.tmp \
  && mv /opt/contract-deploy/create-genesis-sovereign-params.json.tmp /opt/contract-deploy/create-genesis-sovereign-params.json

# shellcheck disable=SC1054,SC1083,SC1056,SC1072
{{ if not .gas_token_enabled }}
gas_token_addr=0x0000000000000000000000000000000000000000
# shellcheck disable=SC1009,SC1054,SC1073
{{ end }}

jq --arg ROLLUPMAN "$rollup_manager_addr" \
   --arg ROLLUPID $rollup_id \
   --arg GAS_TOKEN_ADDR "$gas_token_addr" \
   '
   .rollupManagerAddress = $ROLLUPMAN |
   .rollupID = ($ROLLUPID | tonumber) |
   .gasTokenAddress = $GAS_TOKEN_ADDR
   ' /opt/contract-deploy/create-genesis-sovereign-params.json > /opt/contract-deploy/create-genesis-sovereign-params.json.tmp
mv /opt/contract-deploy/create-genesis-sovereign-params.json.tmp /opt/contract-deploy/create-genesis-sovereign-params.json

# Required files to run the script
cp /opt/contract-deploy/create-genesis-sovereign-params.json /opt/zkevm-contracts/tools/createSovereignGenesis/create-genesis-sovereign-params.json
# 2025-04-03 it's not clear which of these should be used at this point
# cp /opt/contract-deploy/sovereign-genesis.json /opt/zkevm-contracts/tools/createSovereignGenesis/genesis-base.json
cp /opt/zkevm-contracts/deployment/v2/genesis.json /opt/zkevm-contracts/tools/createSovereignGenesis/genesis-base.json

# Remove all existing output files if they exist
find /opt/zkevm-contracts/tools/createSovereignGenesis/ -maxdepth 1 -type f -name 'genesis-rollupID*' -exec rm {} +
find /opt/zkevm-contracts/tools/createSovereignGenesis/ -maxdepth 1 -type f -name 'output-rollupID*' -exec rm {} +

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

# Copy aggoracle implementation and proxy address to combined.json
if [[ "{{.use_agg_oracle_committee}}" ]]; then
jq --arg impl "$(jq -r '.genesisSCNames["AggOracleCommittee implementation"]' /opt/zkevm/create-sovereign-genesis-output.json)" \
   --arg proxy "$(jq -r '.genesisSCNames["AggOracleCommittee proxy"]' /opt/zkevm/create-sovereign-genesis-output.json)" \
   '. + { "aggOracleCommitteeImplementationAddress": $impl, "aggOracleCommitteeProxyAddress": $proxy }' \
   /opt/zkevm/combined.json > /opt/zkevm/combined.json.tmp && mv /opt/zkevm/combined.json.tmp /opt/zkevm/combined.json
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
        if "code" in data:
            allocs[addr]["code"] = data["code"]
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
        if "code" in item:
            allocs[addr]["code"] = item["code"]
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
