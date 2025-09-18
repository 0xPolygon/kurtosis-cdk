#!/bin/bash
# This script deploys the OP-Succinct contracts to the OP network.
export FOUNDRY_DISABLE_NIGHTLY_WARNING=1
set -x

wait_for_rpc_to_be_available() {
    counter=0
    max_retries=40
    until cast send --rpc-url "{{.l1_rpc_url}}" --mnemonic "{{.l1_preallocated_mnemonic}}" --value 0 "$(cast az)" &> /dev/null; do
        ((counter++))
        echo "Can't send L1 transfers yet... Retrying ($counter)..."
        if [[ $counter -ge $max_retries ]]; then
            echo "Exceeded maximum retry attempts. Exiting."
            exit 1
        fi
        sleep 5
    done
}

function deploy_create2() {
    signer_address="0x3fab184622dc19b6109349b94811493bf2a45362"
    gas_cost="0.01ether"    transaction="0xf8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222"
    deployer_address="0x4e59b44847b379578588920ca78fbf26c0b4956c"
    deployer_code=$(cast code --rpc-url "{{.l1_rpc_url}}" "$deployer_address")

    if [[ $deployer_code != "0x" ]]; then
        return
    fi

    cast send \
         --legacy \
         --rpc-url "{{.l1_rpc_url}}" \
         --mnemonic "{{.l1_preallocated_mnemonic}}" \
         --value "$gas_cost" \
         "$signer_address"
    cast publish --rpc-url "{{.l1_rpc_url}}" "$transaction"
    deployer_code=$(cast code --rpc-url "{{.l1_rpc_url}}" "$deployer_address")
    if [[ $deployer_code == "0x" ]]; then
        echo "The create2 deployer wasn't setup properly"
        exit 1
    fi
}

echo "Waiting for the L1 RPC to be available"
wait_for_rpc_to_be_available "{{.l1_rpc_url}}"
deploy_create2


# TODO confirm if these environment variables are all needed.. Many aren't functional yet
# Create the .env file
pushd /opt/op-succinct || exit 1
touch /opt/op-succinct/.env
cat << EOF > ./.env
# Mandatory .env parameters
L1_RPC="{{.l1_rpc_url}}"
L1_BEACON_RPC="{{.l1_beacon_url}}"
L2_RPC="{{.op_el_rpc_url}}"
L2_NODE_RPC="{{.op_cl_rpc_url}}"
# PRIVATE_KEY="" # This value is only used in just deploy-oracle step, which is skipped in agglayer/op-succinct.
ETHERSCAN_API_KEY=""

# Below parameters are not mandatory for the .env file itself. This is required specific to Kurtosis logic.
# We need to know some parameters to spin up CDK services before the OP-Succinct services are up.
# Interval between submissions
SUBMISSION_INTERVAL="{{.op_succinct_submission_interval}}"

# Verifier address, to be set after deployment
VERIFIER_ADDRESS=""

# Oracle address, to be set after deployment
L2OO_ADDRESS=""

# Mock OP Stack succinct flag
# true = mock
# false = network
OP_SUCCINCT_MOCK="{{.op_succinct_mock}}"

# Enable the integration with the Agglayer
AGGLAYER="{{.op_succinct_agglayer}}"

# The RPC endpoint for the Succinct Prover Network
NETWORK_RPC_URL="{{.agglayer_prover_network_url}}"

# Proof type. Must match the verifier gateway contract type. Options: "plonk" or "groth16"
AGG_PROOF_MODE="{{.op_succinct_agg_proof_mode}}"
EOF

# starting_block_number=$(cast block-number --rpc-url "{{.l1_rpc_url}}")
# starting_timestamp=$(cast block --rpc-url "{{.l1_rpc_url}}" -f timestamp "$starting_block_number")
echo "STARTING_BLOCK_NUMBER=1" >> .env


# Print out the config for reference / debugging
cat .env

# Save environment variables to .json file for Kurtosis ExecRecipe extract.
# The extracted environment variables will be passed into the OP-Succinct components' environment variables.

# Run fetch-l2oo-config to get the various configuration values that
# we'll need in the rest of smart contract deployment
mv /opt/op-succinct/fetch-l2oo-config /usr/local/bin/
touch .git
RUST_LOG=info fetch-l2oo-config --env-file .env 2> fetch-l2oo-config.out

# Print out the rollup config for reference / debugging
cat fetch-l2oo-config.out

convert_env_to_json() {
  # Accept input .env file and output json file as arguments
  local env_file="$1"
  local json_file="$2"

  touch "$json_file"

  # Initialize the JSON object
  json="{"

  # Loop through each line in the .env file
  while IFS='=' read -r key value; do
    # Skip empty lines and comments
    if [[ -z "$key" || "$key" =~ ^# ]]; then
      continue
    fi

    # Remove leading/trailing whitespaces from key and value
    key=$(echo "$key" | xargs)
    value=$(echo "$value" | xargs)

    # Wrap everything in quotes, including numeric and boolean values
    value="\"$value\""

    # Append key-value pair to the JSON object
    json+="\"$key\": $value, "
  done < "$env_file"

  # Remove trailing comma and space, close the JSON object
  json="${json%, }"
  json+="}"

  # Save the JSON output to the specified output file
  echo "$json" > "$json_file"

  # Notify the user
  echo "Conversion complete! The JSON file has been saved as $json_file."
}

# Call the function with input .env and output json file as arguments
convert_env_to_json "/opt/op-succinct/.env" "/opt/op-succinct/op-succinct-env-vars.json"

# Call upgrade-oracle
# cd /opt/op-succinct/contracts
# just upgrade-oracle 2>&1 | tee /opt/op-succinct/upgrade-oracle.out

# Contract addresses to extract from op-succinct-env-vars.json and check for bytecode
# shellcheck disable=SC2034
l1_contract_names=(
    "SP1_VERIFIER_GATEWAY_PLONK"
    "SP1_VERIFIER_PLONK"
    "SP1_VERIFIER_GATEWAY_GROTH16"
    "SP1_VERIFIER_GROTH16"
    "VERIFIER_ADDRESS"
    "L2OO_ADDRESS"
)

# JSON file to extract addresses from
json_file="op-succinct-env-vars.json"

# Function to build jq filter and extract addresses
extract_addresses() {
    local -n keys_array=$1  # Reference to the input array
    local json_file=$2      # JSON file path
    local jq_filter=""

    # Build the jq filter
    for key in "${keys_array[@]}"; do
        if [ -z "$jq_filter" ]; then
            jq_filter=".${key}"
        else
            jq_filter="$jq_filter, .${key}"
        fi
    done

    # Extract addresses using jq and return them
    jq -r "[$jq_filter][] | select(. != null)" "$json_file"
}

# Function to check if addresses have deployed bytecode
check_deployed_contracts() {
    local addresses=$1         # String of space-separated addresses
    local rpc_url=$2           # RPC URL for cast command

    if [ -z "$addresses" ]; then
        echo "ERROR: No addresses provided to check"
        exit 1
    fi

    for addr in $addresses; do
        if ! bytecode=$(cast code "$addr" --rpc-url "$rpc_url" 2>/dev/null); then
            echo "Address: $addr - Error checking address (RPC: $rpc_url)"
            continue
        fi

        if [[ $addr == "0x0000000000000000000000000000000000000000" ]]; then
            echo "Warning - The zero address was provide as one of the contracts"
            continue
        fi

        if [ "$bytecode" = "0x" ] || [ -z "$bytecode" ]; then
            echo "Address: $addr - MISSING BYTECODE AT CONTRACT ADDRESS"
            exit 1
        else
            byte_length=$(echo "$bytecode" | sed 's/^0x//' | wc -c)
            byte_length=$((byte_length / 2))
            echo "Address: $addr - DEPLOYED (bytecode length: $byte_length bytes)"
        fi
    done
}

# Extract addresses
# shellcheck disable=SC2128
# l1_contract_addresses=$(extract_addresses l1_contract_names "$json_file")

# Check deployed contracts
# check_deployed_contracts "$l1_contract_addresses" "{{.l1_rpc_url}}"

jq -s '.[0] * .[1]' /opt/op-succinct/op-succinct-env-vars.json contracts/opsuccinctl2ooconfig.json > /opt/op-succinct/op-succinct-env-vars.json.merged
mv /opt/op-succinct/op-succinct-env-vars.json.merged /opt/op-succinct/op-succinct-env-vars.json
