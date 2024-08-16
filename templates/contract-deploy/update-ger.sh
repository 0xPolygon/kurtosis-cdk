#!/bin/bash
set -e

# Setup some vars for use later on
# The private key used to send transactions
private_key="0903a9a721167e2abaa0a33553cbeb209dc9300d28e4e4d6d2fac2452f93e357"

# The bridge address
bridge_addr="0xD71f8F956AD979Cc2988381B8A743a2fE280537D" # TODO: populate this addr using kurtosis magic

# Grab the endpoints for l1
l1_rpc_url="{{.l1_rpc_url}}"
# l1_rpc_url="http://localhost:33201"

# The signature for bridging is long - just putting it into a var
bridge_sig="bridgeAsset(uint32 destinationNetwork, address destinationAddress, uint256 amount, address token, bool forceUpdateGlobalExitRoot, bytes permitData)"

# Get our variables organized
destination_net="7"
destination_addr="0x0000000000000000000000000000000000000000"
amount=0
token="0x0000000000000000000000000000000000000000"
update_ger=true
permit_data="0x"

# Generate the call data, this is useful just to examine what the call will look loke
echo "Generating the call data for the bridge tx..."
cast calldata "$bridge_sig" "$destination_net" "$destination_addr" "$amount" "$token" "$update_ger" "$permit_data"

# Perform an eth_call to make sure the tx will work
echo "Performing an eth call to make sure the bridge tx will work..."
cast call --rpc-url "$l1_rpc_url" "$bridge_addr" "$bridge_sig" "$destination_net" "$destination_addr" "$amount" "$token" "$update_ger" "$permit_data"

# Publish the actual transaction!
echo "Publishing the bridge tx..."
cast send --rpc-url "$l1_rpc_url" --private-key "$private_key" "$bridge_addr" "$bridge_sig" "$destination_net" "$destination_addr" "$amount" "$token" "$update_ger" "$permit_data"