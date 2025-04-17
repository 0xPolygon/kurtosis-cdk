#!/bin/bash

export FOUNDRY_DISABLE_NIGHTLY_WARNING=1

l1_rpc_url="{{.l1_rpc_url}}"
private_key=$(cast wallet private-key --mnemonic "{{.l1_preallocated_mnemonic}}")
eth_address=$(cast wallet address --private-key "$private_key")

# Create the .env file
pushd /opt/sp1-contracts || exit 1

# FIXME - What exactly is this doing? It seems to require git
forge install succinctlabs/sp1-contracts

# Update Foundry.toml with the RPC_KURTOSIS
sed -i "/scroll_sepolia = \"${RPC_SCROLL_SEPOLIA}\"/a kurtosis = \"${RPC_KURTOSIS}\"" /opt/sp1-contracts/lib/sp1-contracts/contracts/foundry.toml

# Create 271828.json Deployment artifact for Kurtosis devnet. Referenced from https://github.com/succinctlabs/sp1-contracts/blob/v4.0.0/contracts/deployments/11155420.json
# These addresses should be deterministic using CREATE2 deployments
# TODO: Update the addresses once they are finalized
touch /opt/sp1-contracts/lib/sp1-contracts/contracts/deployments/271828.json
cat << EOF > /opt/sp1-contracts/lib/sp1-contracts/contracts/deployments/271828.json
{
  "CREATE2_SALT": "0x0000000000000000000000000000000000000000000000000000000000000001",
  "SP1_VERIFIER_GATEWAY_GROTH16": "0x397A5f7f3dBd538f23DE225B51f532c34448dA9B",
  "SP1_VERIFIER_GATEWAY_PLONK": "0x3B6041173B80E77f038f3F2C0f9744f04837185e",
  "V4_0_0_RC_3_SP1_VERIFIER_GROTH16": "0xa27A057CAb1a4798c6242F6eE5b2416B7Cd45E5D",
  "V4_0_0_RC_3_SP1_VERIFIER_PLONK": "0xE00a3cBFC45241b33c0A44C78e26168CBc55EC63"
}
EOF

pushd /opt/sp1-contracts/lib/sp1-contracts/contracts || exit 1
touch /opt/sp1-contracts/lib/sp1-contracts/contracts/.env

# Create .env file
cat << EOF > /opt/sp1-contracts/lib/sp1-contracts/contracts/.env
### Salt used to deploy the contracts. Recommended to use the same salt across different chains.
CREATE2_SALT=0x0000000000000000000000000000000000000000000000000000000000000001

### The owner of the SP1 Verifier Gateway. This is the account that will be able to add and freeze routes.
OWNER="$eth_address"

### The chains to deploy to, specified by chain name (e.g. CHAINS=MAINNET,SEPOLIA,ARBITRUM_SEPOLIA)
CHAINS=KURTOSIS

### RPCs for each chain ID
RPC_KURTOSIS="$l1_rpc_url"

## Contract Deployer Private Key
PRIVATE_KEY="$private_key"
EOF

pushd /opt/sp1-contracts/lib/sp1-contracts/contracts || exit 1
set -a
# shellcheck disable=SC1091
source .env
set +a

# Change Verifier Hash in SP1Verifier contract
# TODO: Update the hash to the correct one once Provers are ready
# Plonk Deployments
# Deploy SP1 Verifier Gateway Plonk
FOUNDRY_PROFILE=deploy forge script --legacy /opt/sp1-contracts/lib/sp1-contracts/contracts/script/deploy/SP1VerifierGatewayPlonk.s.sol:SP1VerifierGatewayScript --private-key "$private_key" --broadcast
# Deploy SP1 Verifier Plonk contract
FOUNDRY_PROFILE=deploy forge script /opt/sp1-contracts/lib/sp1-contracts/contracts/script/deploy/v4.0.0-rc.3/SP1VerifierPlonk.s.sol:SP1VerifierScript --private-key "$private_key" --broadcast


# TODO: Fix Groth16 Verifier Deployments.
# Groth16 Deployments - Since the deployments are made with CREATE2, the deployment will revert with EvmError: CreateCollision. So the salt is changed.
sed -i 's/0x0000000000000000000000000000000000000000000000000000000000000001/0x0000000000000000000000000000000000000000000000000000000000000002/' /opt/sp1-contracts/lib/sp1-contracts/contracts/deployments/271828.json
sed -i 's/0x0000000000000000000000000000000000000000000000000000000000000001/0x0000000000000000000000000000000000000000000000000000000000000002/' /opt/sp1-contracts/lib/sp1-contracts/contracts/.env

# Source the updated .env file
set -a
# shellcheck disable=SC1091
source .env
set +a

# Deploy SP1 Verifier Gateway Groth16
FOUNDRY_PROFILE=deploy forge script --legacy /opt/sp1-contracts/lib/sp1-contracts/contracts/script/deploy/SP1VerifierGatewayGroth16.s.sol:SP1VerifierGatewayScript --private-key "$private_key" --broadcast
# Deploy SP1 Verifier Groth16 contract
FOUNDRY_PROFILE=deploy forge script /opt/sp1-contracts/lib/sp1-contracts/contracts/script/deploy/v4.0.0-rc.3/SP1VerifierGroth16.s.sol:SP1VerifierScript --private-key "$private_key" --broadcast

# Create initial JSON with Gateway Plonk address
jq -n --arg gatewayaddr "$(jq -r '.transactions[0].contractAddress' /opt/sp1-contracts/lib/sp1-contracts/contracts/broadcast/SP1VerifierGatewayPlonk.s.sol/271828/run-latest.json)" \
'{ "SP1_VERIFIER_GATEWAY_PLONK": $gatewayaddr }' > /tmp/sp1_verifier_out.json

# Add SP1 Verifier Plonk address
jq --arg addr "$(jq -r '.transactions[0].contractAddress' /opt/sp1-contracts/lib/sp1-contracts/contracts/broadcast/SP1VerifierPlonk.s.sol/271828/run-latest.json)" \
    '. + {"SP1_VERIFIER_PLONK": $addr}' /tmp/sp1_verifier_out.json > /tmp/tmp.json && mv /tmp/tmp.json /tmp/sp1_verifier_out.json

# Add SP1 Verifier Gateway Groth16 address
jq --arg gatewayaddr "$(jq -r '.transactions[0].contractAddress' /opt/sp1-contracts/lib/sp1-contracts/contracts/broadcast/SP1VerifierGatewayGroth16.s.sol/271828/run-latest.json)" \
    '. + {"SP1_VERIFIER_GATEWAY_GROTH16": $gatewayaddr}' /tmp/sp1_verifier_out.json > /tmp/tmp.json && mv /tmp/tmp.json /tmp/sp1_verifier_out.json

# Add SP1 Verifier Groth16 address
jq --arg addr "$(jq -r '.transactions[0].contractAddress' /opt/sp1-contracts/lib/sp1-contracts/contracts/broadcast/SP1VerifierGroth16.s.sol/271828/run-latest.json)" \
    '. + {"SP1_VERIFIER_GROTH16": $addr}' /tmp/sp1_verifier_out.json > /tmp/tmp.json && mv /tmp/tmp.json /tmp/sp1_verifier_out.json

# Merge with op-succinct-env-vars.json
jq -s '.[0] * .[1]' /opt/op-succinct/op-succinct-env-vars.json /tmp/sp1_verifier_out.json > /tmp/merged.json && \
mv /tmp/merged.json /opt/op-succinct/op-succinct-env-vars.json

# TODO: Remove SC2034 shellcheck - unused variables once the specs are finalized.
# shellcheck disable=SC2034
SP1_VERIFIER_GATEWAY_PLONK=$(jq '.SP1_VERIFIER_GATEWAY_PLONK' /tmp/sp1_verifier_out.json -r)
# shellcheck disable=SC2034
SP1_VERIFIER_PLONK=$(jq '.SP1_VERIFIER_PLONK' /tmp/sp1_verifier_out.json -r)
# shellcheck disable=SC2034
SP1_VERIFIER_GATEWAY_GROTH16=$(jq '.SP1_VERIFIER_GATEWAY_GROTH16' /tmp/sp1_verifier_out.json -r)
# shellcheck disable=SC2034
SP1_VERIFIER_GROTH16=$(jq '.SP1_VERIFIER_GROTH16' /tmp/sp1_verifier_out.json -r)

# Add Plonk verifier to Plonk SP1_VERIFIER_GATEWAY_PLONK
cast send "$SP1_VERIFIER_GATEWAY_PLONK" "addRoute(address)" "$SP1_VERIFIER_PLONK" --private-key "$private_key" --rpc-url "$l1_rpc_url"

# Add Groth16 verifier to Plonk SP1_VERIFIER_GATEWAY_GROTH16
cast send "$SP1_VERIFIER_GATEWAY_GROTH16" "addRoute(address)" "$SP1_VERIFIER_GROTH16" --private-key "$private_key" --rpc-url "$l1_rpc_url"

# SPN Requester address
spn_requester_eth_address=$(cast wallet address --private-key "{{.sp1_prover_key}}")
# Fund the op-succinct-proposer. This address of the sp1_prover_key - address submitting requests to SPN
# This will allow the op-succinct-proposer to submit L1 requests to call "Propose L2Output" on the OPSuccinctL2OutputOracle contract.
cast send "$spn_requester_eth_address" --private-key "$private_key" --value 1ether --rpc-url "$l1_rpc_url"

