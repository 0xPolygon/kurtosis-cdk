#!/bin/bash
# This script deploys the OP-Succinct contracts to the OP network.

private_key=$(cast wallet private-key --mnemonic "{{.l1_preallocated_mnemonic}}")

export FOUNDRY_DISABLE_NIGHTLY_WARNING=1

# Create the .env file
cd /opt/op-succinct || exit
touch /opt/op-succinct/.env
cat << EOF > ./.env
L1_RPC="{{.l1_rpc_url}}"
L1_BEACON_RPC="{{.l1_beacon_url}}"
L2_RPC="{{.op_el_rpc_url}}"
L2_NODE_RPC="{{.op_cl_rpc_url}}"

# Private key of the prefunded OP Stack address
PRIVATE_KEY="$private_key"

# API key for Etherscan
ETHERSCAN_API_KEY=""

# Interval between submissions
SUBMISSION_INTERVAL="{{.op_succinct_submission_interval}}"

# Verifier address, to be set after mock verifier deployment
VERIFIER_ADDRESS=""

# Oracle address, to be set after deployment
L2OO_ADDRESS=""

# Mock OP Stack succinct flag
# true = mock
# false = network
OP_SUCCINCT_MOCK="{{.op_succinct_mock}}"

# Enable the integration with the Agglayer
OP_SUCCINCT_AGGLAYER="{{.op_succinct_agglayer}}"

# The RPC endpoint for the Succinct Prover Network
NETWORK_RPC_URL="{{.agglayer_prover_network_url}}"

# Proof type. Must match the verifier gateway contract type. Options: "plonk" or "groth16"
AGG_PROOF_MODE="{{.op_succinct_agg_proof_mode}}"

EOF

starting_block_number=$(cast block-number --rpc-url "{{.l1_rpc_url}}")
starting_timestamp=$(cast block --rpc-url "{{.l1_rpc_url}}" -f timestamp "$starting_block_number")
echo "STARTING_BLOCK_NUMBER=\"$starting_block_number\"" >> .env
echo "STARTING_TIMESTAMP=\"$starting_timestamp\"" >> .env
echo "" >> .env

# Print out the config for reference / debugging
cat .env

# TODO confirm that this isn't used
# Deploy the mock-verifier and save the address to the verifier_address.out
just deploy-mock-verifier 2> deploy-mock-verifier.out | grep -oP '0x[a-fA-F0-9]{40}' | xargs -I {} echo "VERIFIER_ADDRESS=\"{}\"" > /opt/op-succinct/verifier_address.out
# Update the VERIFIER_ADDRESS in the .env file with the output from the previous command
sed -i "s/^VERIFIER_ADDRESS=.*$/VERIFIER_ADDRESS=\"$(grep -oP '0x[a-fA-F0-9]{40}' /opt/op-succinct/verifier_address.out)\"/" /opt/op-succinct/.env

# Deploy the deploy-oracle and save the address to the l2oo_address.out
just deploy-oracle  2> deploy-oracle.out | grep -oP '0x[a-fA-F0-9]{40}' | xargs -I {} echo "L2OO_ADDRESS=\"{}\"" > /opt/op-succinct/l2oo_address.out
# Update the L2OO_ADDRESS in the .env file with the output from the previous command
sed -i "s/^L2OO_ADDRESS=.*$/L2OO_ADDRESS=\"$(grep -oP '0x[a-fA-F0-9]{40}' /opt/op-succinct/l2oo_address.out)\"/" /opt/op-succinct/.env

# Save environment variables to .json file for Kurtosis ExecRecipe extract.
# The extracted environment variables will be passed into the OP-Succinct components' environment variables.

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

# Extract addresses
# shellcheck disable=SC2128
l1_contract_addresses=$(extract_addresses l1_contract_names "$json_file")

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

# Check deployed contracts
check_deployed_contracts "$l1_contract_addresses" "{{.l1_rpc_url}}"
