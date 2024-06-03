#!/bin/bash
set -e

# The private key used to send transactions.
private_key="{{.zkevm_l2_admin_private_key}}"

# The address of the recipient.
destination_address="{{.zkevm_l2_admin_address}}"

# The destination networks.
ethereum_network="0"
zkevm_l2_network="1"


# Functions for deploying an ERC20 contract on LX.
deploy_erc20_contract_on_l1() {
  deploy_erc20_contract "$ethereum_network" "{{.l1_rpc_url}}"
}

deploy_erc20_contract_on_l2() {
  deploy_erc20_contract "$zkevm_l2_network" "{{.l2_rpc_url}}"
}

deploy_erc20_contract() {
  network="$1"
  rpc_url="$2"

  echo "Deploying an ERC20 contract on network $network..."
  cast send \
    --private-key "$private_key" \
    --rpc-url "$rpc_url" \
    --legacy \
    --json \
    --create "$(cat /opt/bindings/tokens/ERC20.bin)" | jq > "/opt/erc20-network-$network-deployment-receipt.json"
  erc20_address="$(jq -r '.contractAddress' "/opt/erc20-network-$network-deployment-receipt.json")"
  echo "ERC20 contract deployed at $erc20_address"

  get_erc20_balance_on_lx "$network" "$rpc_url" "$erc20_address"

  echo; echo "Allowing the zkevm-bridge to spend the owner's tokens..."
  cast send \
    --private-key "$private_key" \
    --rpc-url "$rpc_url" \
    --legacy \
    "$erc20_address" \
    "approve(address,uint256)" "{{.zkevm_bridge_address}}" 100
}

# Function for checking ERC20 balance on LX.
get_erc20_balance_on_lx() {
  network="$1"
  rpc_url="$2"
  erc20_address="$3"

  echo "Getting the ERC20 balance of the owner..."
  cast call \
    --rpc-url "$rpc_url" \
    "$erc20_address" \
    "balanceOf(address)" "$destination_address"
}

# Functions for bridging assets from LX to LY.
bridge_assets_from_l1_to_l2() {
  erc20_address="$(jq -r '.contractAddress' /opt/erc20-network-${ethereum_network}-deployment-receipt.json)"
  get_erc20_balance_on_lx "$ethereum_network" "{{.l1_rpc_url}}" "$erc20_address"
  bridge_assets_from_lx_to_ly "$ethereum_network" "$zkevm_l2_network" "{{.l1_rpc_url}}" "$erc20_address"
  get_erc20_balance_on_lx "$ethereum_network" "{{.l1_rpc_url}}" "$erc20_address"
}

bridge_assets_from_l2_to_l1() {
  erc20_address="$(jq -r '.contractAddress' /opt/erc20-network-${zkevm_l2_network}-deployment-receipt.json)"
  get_erc20_balance_on_lx "$zkevm_l2_network" "{{.l2_rpc_url}}" "$erc20_address"
  bridge_assets_from_lx_to_ly "$zkevm_l2_network" "$ethereum_network" "{{.l2_rpc_url}}" "$erc20_address"
  get_erc20_balance_on_lx "$zkevm_l2_network" "{{.l2_rpc_url}}" "$erc20_address"
}

bridge_assets_from_lx_to_ly() {
  lx_network="$1"
  ly_network="$2"
  rpc_url="$3"
  erc20_contract_address="$4"

  echo "Bridging 10 ERC20 tokens from network $lx_network to network $ly_network..."
  cast send \
    --private-key "$private_key" \
    --rpc-url "$rpc_url" \
    --legacy \
    "{{.zkevm_bridge_address}}" \
    "bridgeAsset(uint32,address,uint256,address,bool,bytes)" \
    "$ly_network" "$destination_address" 10 "$erc20_contract_address" true "0x"

  echo; echo "Checking the amount of last updated deposit count to the GER..."
  cast call \
    --rpc-url "$rpc_url" \
    "{{.zkevm_bridge_address}}" \
    "lastUpdatedDepositCount()"
}

# Functions for claiming assets on LX.
claim_assets_on_l1() {
  erc20_address="$(jq -r '.contractAddress' /opt/erc20-network-${zkevm_l2_network}-deployment-receipt.json)"
  get_erc20_balance_on_lx "$ethereum_network" "{{.l1_rpc_url}}" "$erc20_address"
  claim_assets "$ethereum_network" "{{.l1_rpc_url}}"
  get_erc20_balance_on_lx "$ethereum_network" "{{.l1_rpc_url}}" "$erc20_address"
}

claim_assets_on_l2() {
  erc20_address="$(jq -r '.contractAddress' /opt/erc20-network-${ethereum_network}-deployment-receipt.json)"
  get_erc20_balance_on_lx "$zkevm_l2_network" "{{.l2_rpc_url}}" "$erc20_address"
  claim_assets "$zkevm_l2_network" "{{.l2_rpc_url}}"
  get_erc20_balance_on_lx "$zkevm_l2_network" "{{.l2_rpc_url}}" "$erc20_address"
}

claim_assets() {
  network="$1"
  rpc_url="$2"

  # The signature for claiming assets.
  claim_sig="claimAsset(bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes)"

  echo "Getting the list of deposits on network $network..."
  curl -s "{{.zkevm_bridge_api_url}}/bridges/$destination_address?limit=100&offset=0" | jq > /opt/bridge-deposits.json
  cat /opt/bridge-deposits.json

  echo; echo "Filtering the list of deposits..."
  # shellcheck disable=SC2086
  jq '[.deposits[] | select(.ready_for_claim == true and .claim_tx_hash == "" and .dest_net == '$network')]' /opt/bridge-deposits.json | jq > /opt/claimable-txs.json
  cat /opt/claimable-txs.json

  jq -c '.[]' /opt/claimable-txs.json | while IFS= read -r tx; do
    echo; echo "Processing claimable tx..."
    echo "$tx"

    echo; echo "Getting the merkle proof of our deposit..."
    curr_deposit_cnt="$(echo "$tx" | jq -r '.deposit_cnt')"
    curr_network_id="$(echo "$tx" | jq -r '.network_id')"
    curl -s "{{.zkevm_bridge_api_url}}/merkle-proof?deposit_cnt=$curr_deposit_cnt&net_id=$curr_network_id" | jq > /opt/proof.json
    cat /opt/proof.json

    in_merkle_proof="$(jq -r -c '.proof.merkle_proof' /opt/proof.json | tr -d '"')"
    in_rollup_merkle_proof="$(jq -r -c '.proof.rollup_merkle_proof' /opt/proof.json | tr -d '"')"
    in_global_index="$(echo "$tx" | jq -r '.global_index')"
    in_main_exit_root="$(jq -r '.proof.main_exit_root' /opt/proof.json)"
    in_rollup_exit_root="$(jq -r '.proof.rollup_exit_root' /opt/proof.json)"
    in_orig_net="$(echo "$tx" | jq -r '.orig_net')"
    in_orig_addr="$(echo "$tx" | jq -r '.orig_addr')"
    in_dest_net="$(echo "$tx" | jq -r '.dest_net')"
    in_dest_addr="$(echo "$tx" | jq -r '.dest_addr')"
    in_amount="$(echo "$tx" | jq -r '.amount')"
    in_metadata="$(echo "$tx" | jq -r '.metadata')"

    echo; echo "Performing an eth call to make sure the bridge claim tx will work..."
    cast call \
      --rpc-url "$rpc_url" \
      "{{.zkevm_bridge_address}}" \
      "$claim_sig" "$in_merkle_proof" "$in_rollup_merkle_proof" "$in_global_index" "$in_main_exit_root" "$in_rollup_exit_root" "$in_orig_net" "$in_orig_addr" "$in_dest_net" "$in_dest_addr" "$in_amount" "$in_metadata"

    echo; echo "Publishing the bridge claim tx..."
    cast send \
      --private-key "$private_key" \
      --rpc-url "$rpc_url" \
      --legacy \
      "{{.zkevm_bridge_address}}" \
      "$claim_sig" "$in_merkle_proof" "$in_rollup_merkle_proof" "$in_global_index" "$in_main_exit_root" "$in_rollup_exit_root" "$in_orig_net" "$in_orig_addr" "$in_dest_net" "$in_dest_addr" "$in_amount" "$in_metadata"
  done
}

# Check if a function name is provided as an argument.
# If not, run a few bridge operations.
if [ -z "$1" ]; then
  deploy_erc20_contract_on_l1
  for ((i=0; i<=10; i++)); do
    bridge_assets_from_l1_to_l2
  done

  deploy_erc20_contract_on_l2
  for ((i=0; i<=10; i++)); do
    bridge_assets_from_l2_to_l1
  done
fi

# Define the function to execute the specified function.
function execute_function() {
  local function_name="$1"
  "$function_name"
}

# Else, call the function with the function name provided as the script's argument.
execute_function "$1"
