#!/bin/bash

echo_ts() {
    green="\e[32m"
    end_color="\e[0m"

    timestamp=$(date +"[%Y-%m-%d %H:%M:%S]")
    echo -e "$green$timestamp$end_color $1" >&2
}

# deploymentRollupManagerBlockNumber must be different to 0 becuase cdk-erigon requires this value (zkevm.l1-first-block) to be different to 0
cat >/opt/zkevm/combined.json <<'EOF'
    {
        "polygonRollupManagerAddress": "0xFB054898a55bB49513D1BA8e0FB949Ea3D9B4153",
        "polygonZkEVMBridgeAddress":   "0x927aa8656B3a541617Ef3fBa4A2AB71320dc7fD7",
        "polygonZkEVMGlobalExitRootAddress": "0x2F50ef6b8e8Ee4E579B17619A92dE3E2ffbD8AD2",
        "aggLayerGatewayAddress":      "0x6c6c009cC348976dB4A908c92B24433d4F6edA43",
        "pessimisticVKeyRouteALGateway": {
            "pessimisticVKeySelector": "0x00000002",
            "verifier":                "0xf22E2B040B639180557745F47aB97dFA95B1e22a",
            "pessimisticVKey":         "0x00e60517ac96bf6255d81083269e72c14ad006e5f336f852f7ee3efb91b966be"
        },
        "polTokenAddress":            "0xEdE9cf798E0fE25D35469493f43E88FeA4a5da0E",
        "zkEVMDeployerContract":      "0x1b50e2F3bf500Ab9Da6A7DBb6644D392D9D14b99",
        "deployerAddress":            "0xE34aaF64b29273B7D567FCFc40544c014EEe9970",
        "timelockContractAddress":    "0x3D4C5989214ca3CDFf9e62778cDD56a94a05348D",
        "deploymentRollupManagerBlockNumber": 0,
        "upgradeToULxLyBlockNumber":          0,
        "admin":                 "0xE34aaF64b29273B7D567FCFc40544c014EEe9970",
        "trustedAggregator":      "0xCae5b68Ff783594bDe1b93cdE627c741722c4D4d",
        "proxyAdminAddress":      "0xd60F1BCf5566fCCD62f8AA3bE00525DdA6Ab997c",
        "salt":                   "0x0000000000000000000000000000000000000000000000000000000000000001",
        "polygonZkEVML2BridgeAddress":        "0x927aa8656B3a541617Ef3fBa4A2AB71320dc7fD7",
        "polygonZkEVMGlobalExitRootL2Address": "0xa40d5f56745a118d0906a34e69aec8c0db1cb8fa",
        "bridgeGenBlockNumber":               0
    }
EOF

cp /opt/zkevm/combined.json /opt/zkevm-contracts/deployment/v2/deploy_output.json
# sed -i 's#http://127.0.0.1:8545#{{.l1_rpc_url}}#' /opt/zkevm-contracts/hardhat.config.ts
# cp /opt/contract-deploy/deploy_parameters.json /opt/zkevm-contracts/deployment/v2/deploy_parameters.json

# pushd /opt/zkevm-contracts || exit 1
# MNEMONIC="{{.l1_preallocated_mnemonic}}" npx ts-node deployment/v2/1_createGenesis.ts 2>&1 | tee 02_create_genesis.out

# MNEMONIC="{{.l1_preallocated_mnemonic}}" npx hardhat run deployment/v2/4_createRollup.ts --network localhost 2>&1 | tee ./05_create_rollup.out
# popd || exit 1

# cp /opt/zkevm-contracts/deployment/v2/genesis.json /opt/zkevm/
# cp /opt/contract-deploy/create_rollup_parameters.json /opt/zkevm/
# cp /opt/zkevm/combined.json /opt/zkevm/combined-001.json

# if [[ -e /opt/zkevm-contracts/deployment/v2/create_rollup_output.json ]]; then
#     cp /opt/zkevm-contracts/deployment/v2/create_rollup_output.json /opt/zkevm/
# else
#     echo "File /opt/zkevm-contracts/deployment/v2/create_rollup_output.json does not exist."
# fi

# # This is a jq script to transform the CDK-style genesis file into an allocs file for erigon
# jq_script='
# .genesis | map({
#   (.address): {
#     contractName: (if .contractName == "" then null else .contractName end),
#     balance: (if .balance == "" then null else .balance end),
#     nonce: (if .nonce == "" then null else .nonce end),
#     code: (if .bytecode == "" then null else .bytecode end),
#     storage: (if .storage == null or .storage == {} then null else (.storage | to_entries | sort_by(.key) | from_entries) end)
#   }
# }) | add'

# # Use jq to transform the input JSON into the desired format
# if ! output_json=$(jq "$jq_script" /opt/zkevm/genesis.json); then
#     echo_ts "Error processing JSON with jq"
#     exit 1
# fi

# # Write the output JSON to a file
# if ! echo "$output_json" | jq . > "/opt/zkevm/dynamic-{{.chain_name}}-allocs.json"; then
#     echo_ts "Error writing to file dynamic-{{.chain_name}}-allocs.json"
#     exit 1
# fi

# if [[ -e create_rollup_output.json ]]; then
#     jq '{"root": .root, "timestamp": 0, "gasLimit": 0, "difficulty": 0}' /opt/zkevm/genesis.json > "/opt/zkevm/dynamic-{{.chain_name}}-conf.json"
#     batch_timestamp=$(jq '.firstBatchData.timestamp' /opt/zkevm/combined.json)
#     jq --arg bt "$batch_timestamp" '.timestamp |= ($bt | tonumber)' "/opt/zkevm/dynamic-{{.chain_name}}-conf.json" > tmp_output.json
#     mv tmp_output.json "/opt/zkevm/dynamic-{{.chain_name}}-conf.json"
# else
#     echo "Without create_rollup_output.json, there is no batch_timestamp available"
#     jq '{"root": .root, "timestamp": 0, "gasLimit": 0, "difficulty": 0}' /opt/zkevm/genesis.json > "/opt/zkevm/dynamic-{{.chain_name}}-conf.json"
# fi

# # zkevm.initial-batch.config
# jq '.firstBatchData' /opt/zkevm/combined.json > /opt/zkevm/first-batch-config.json

# if [[ ! -s "/opt/zkevm/dynamic-{{.chain_name}}-conf.json" ]]; then
#     echo_ts "Error creating the dynamic kurtosis config"
#     exit 1
# fi

cast send 0x2F50ef6b8e8Ee4E579B17619A92dE3E2ffbD8AD2 "initialize()" --private-key "{{.zkevm_l2_admin_private_key}}" --rpc-url "{{.l1_rpc_url}}"
