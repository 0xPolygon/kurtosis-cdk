#!/bin/bash
set -e

# TODO we should understand if this is still need and if so we
# shouldn't run it if the network has already been deployed

# Setup some vars for use later on
# The private key used to send transactions
private_key="{{.zkevm_l2_admin_private_key}}"

# The bridge address
bridge_address="$(jq --raw-output '.polygonZkEVMBridgeAddress' /opt/zkevm/combined.json)"

# Grab the endpoints for l1
l1_rpc_url="{{.l1_rpc_url}}"

# The signature for bridging is long - just putting it into a var
bridge_sig="bridgeAsset(uint32 destinationNetwork, address destinationAddress, uint256 amount, address token, bool forceUpdateGlobalExitRoot, bytes permitData)"

# Get our variables organized
destination_net="7" # random value (better to not use 1 as it could interfere with the network being deployed)
destination_addr="0x0000000000000000000000000000000000000000"
amount=0
token="0x0000000000000000000000000000000000000000"
update_ger=true
permit_data="0x"

# Generate the call data, this is useful just to examine what the call will look like
echo "Generating the call data for the bridge tx..."
cast calldata "$bridge_sig" "$destination_net" "$destination_addr" "$amount" "$token" "$update_ger" "$permit_data"

# Perform an eth_call to make sure the tx will work
echo "Performing an eth call to make sure the bridge tx will work..."
cast call --rpc-url "$l1_rpc_url" "$bridge_address" "$bridge_sig" "$destination_net" "$destination_addr" "$amount" "$token" "$update_ger" "$permit_data"

# Publish the actual transaction!
echo "Publishing the bridge tx..."
cast send --rpc-url "$l1_rpc_url" --private-key "$private_key" "$bridge_address" "$bridge_sig" "$destination_net" "$destination_addr" "$amount" "$token" "$update_ger" "$permit_data"
