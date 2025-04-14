#!/bin/bash
# This script deploys the OP-Succinct contracts to the OP network.

private_key=$(cast wallet private-key --mnemonic "{{.l1_preallocated_mnemonic}}")

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
EOF

# Deploy the mock-verifier and save the address to the verifier_address.out
just deploy-mock-verifier | grep -oP '0x[a-fA-F0-9]{40}' | xargs -I {} echo "VERIFIER_ADDRESS=\"{}\"" > /opt/op-succinct/verifier_address.out
# Update the VERIFIER_ADDRESS in the .env file with the output from the previous command
sed -i "s/^VERIFIER_ADDRESS=.*$/VERIFIER_ADDRESS=\"$(grep -oP '0x[a-fA-F0-9]{40}' /opt/op-succinct/verifier_address.out)\"/" /opt/op-succinct/.env

# Deploy the deploy-oracle and save the address to the l2oo_address.out
just deploy-oracle | grep -oP '0x[a-fA-F0-9]{40}' | xargs -I {} echo "L2OO_ADDRESS=\"{}\"" > /opt/op-succinct/l2oo_address.out
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