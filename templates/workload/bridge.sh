#!/bin/bash
set -e

# The private key used to send transactions.
private_key="{{.zkevm_l2_admin_private_key}}"

# The address of the recipient.
destination_address="{{.zkevm_l2_admin_address}}"

# Function for deploying an ERC20 contract
deploy_erc20_contract() {
  echo "Deploying an ERC20 contract on L1..."
  cast send \
    --private-key "$private_key" \
    --rpc-url "{{.l1_rpc_url}}" \
    --json \
    --create "$(cat /opt/bindings/tokens/ERC20.bin)" > /opt/erc20-l1-deployment-receipt.json
  erc20_address_on_l1="$(jq -r '.contractAddress' /opt/erc20-l1-deployment-receipt.json)"
  echo "ERC20 contract deployed at $erc20_address_on_l1"

  echo; echo "Getting the ERC20 balance of the owner..."
  cast call \
    --rpc-url "{{.l1_rpc_url}}" \
    "$erc20_address_on_l1" \
    "balanceOf(address)" "$destination_address"

  echo; echo "Allowing the zkevm-bridge to spend the owner's tokens..."
  cast send \
    --private-key "$private_key" \
    --rpc-url "{{.l1_rpc_url}}" \
    "$erc20_address_on_l1" \
    "approve(address,uint256)" "{{.zkevm_bridge_address}}" 100
}

# Function for bridging assets from L1 to L2
bridge_assets_from_l1_to_l2() {
  echo "Bridging 10 ERC20 tokens from L1 to L2..."
  erc20_address_on_l1="$(jq -r '.contractAddress' /opt/erc20-l1-deployment-receipt.json)"
  cast send \
    --private-key "$private_key" \
    --rpc-url "{{.l1_rpc_url}}" \
    "{{.zkevm_bridge_address}}" \
    "bridgeAsset(uint32,address,uint256,address,bool,bytes)" \
    1 "$destination_address" 10 "$erc20_address_on_l1" true "0x"

  echo; echo "Checking the amount of last updated deposit count to the GER..."
  cast call \
    --rpc-url "{{.l1_rpc_url}}" \
    "{{.zkevm_bridge_address}}" \
    "lastUpdatedDepositCount()"
}

# Function for claiming assets on L2
claim_assets_on_l2() {
  # The signature for claiming assets.
  claim_sig="claimAsset(bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes)"

  echo "Getting the list of deposits on L2..."
  curl -s "{{.zkevm_bridge_api_url}}/bridges/$destination_address?limit=100&offset=0" | jq > bridge-deposits.json
  cat bridge-deposits.json

  echo; echo "Filtering the list of deposits..."
  jq '[.deposits[] | select(.ready_for_claim == true and .claim_tx_hash == "" and .dest_net == 1)]' bridge-deposits.json > claimable-txs.json
  cat claimable-txs.json

  jq -c '.[]' claimable-txs.json | while IFS= read -r tx; do
    echo; echo "Processing claimable tx..."
    echo "$tx"

    echo; echo "Getting the merkle proof of our deposit..."
    curr_deposit_cnt="$(echo "$tx" | jq -r '.deposit_cnt')"
    curr_network_id="$(echo "$tx" | jq -r '.network_id')"
    curl -s "{{.zkevm_bridge_api_url}}/merkle-proof?deposit_cnt=$curr_deposit_cnt&net_id=$curr_network_id" | jq '.' > proof.json
    cat proof.json

    in_merkle_proof="$(jq -r -c '.proof.merkle_proof' proof.json | tr -d '"')"
    in_rollup_merkle_proof="$(jq -r -c '.proof.rollup_merkle_proof' proof.json | tr -d '"')"
    in_global_index="$(echo "$tx" | jq -r '.global_index')"
    in_main_exit_root="$(jq -r '.proof.main_exit_root' proof.json)"
    in_rollup_exit_root="$(jq -r '.proof.rollup_exit_root' proof.json)"
    in_orig_net="$(echo "$tx" | jq -r '.orig_net')"
    in_orig_addr="$(echo "$tx" | jq -r '.orig_addr')"
    in_dest_net="$(echo "$tx" | jq -r '.dest_net')"
    in_dest_addr="$(echo "$tx" | jq -r '.dest_addr')"
    in_amount="$(echo "$tx" | jq -r '.amount')"
    in_metadata="$(echo "$tx" | jq -r '.metadata')"

    echo; echo "Publishing the bridge claim tx..."
    cast send \
      --private-key "$private_key" \
      --rpc-url "{{.l2_rpc_url}}" \
      --legacy \
      "{{.zkevm_bridge_address}}" \
      "$claim_sig" "$in_merkle_proof" "$in_rollup_merkle_proof" "$in_global_index" "$in_main_exit_root" "$in_rollup_exit_root" "$in_orig_net" "$in_orig_addr" "$in_dest_net" "$in_dest_addr" "$in_amount" "$in_metadata"
  done
}

# Help function
print_help() {
  echo "Usage: $0 mode"
  echo "Modes:"
  echo "  deploy-erc20: Deploy ERC20 contract on L1"
  echo "  bridge-from-l1-to-l2: Bridge assets from L1 to L2"
  echo "  claim-on-l2: Claim assets on L2"
}

# Check for mode argument
if [ $# -ne 1 ]; then
  echo "Error: Mode argument is required."
  print_help
  exit 1
fi

# Execute selected mode
case $1 in
  deploy-erc20)
    deploy_erc20_contract
    ;;
  bridge-from-l1-to-l2)
    bridge_assets_from_l1_to_l2
    ;;
  claim-on-l2)
    claim_assets_on_l2
    ;;
  *)
    echo "Error: Invalid mode."
    print_help
    exit 1
    ;;
esac
