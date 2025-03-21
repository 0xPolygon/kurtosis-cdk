#!/bin/bash

L1_RPC="{{.l1_rpc_url}}"
PRIVATE_KEY=$(cast wallet private-key --mnemonic "{{.l1_preallocated_mnemonic}}")
ETH_ADDRESS=$(cast wallet address --private-key "$PRIVATE_KEY")

# Create the .env file
mkdir /tmp/sp1-contracts
cd /tmp/sp1-contracts || exit

git clone https://github.com/succinctlabs/sp1-contracts.git .
forge install succinctlabs/sp1-contracts

# Update Foundry.toml with the RPC_KURTOSIS
sed -i "/scroll_sepolia = \"${RPC_SCROLL_SEPOLIA}\"/a kurtosis = \"${RPC_KURTOSIS}\"" /tmp/sp1-contracts/lib/sp1-contracts/contracts/foundry.toml

# Create 271828.json Deployment artifact for Kurtosis devnet. Referenced from https://github.com/succinctlabs/sp1-contracts/blob/v4.0.0/contracts/deployments/11155420.json
# These addresses should be deterministic using CREATE2 deployments
# TODO: Update the addresses once they are finalized
touch /tmp/sp1-contracts/lib/sp1-contracts/contracts/deployments/271828.json
cat << EOF > /tmp/sp1-contracts/lib/sp1-contracts/contracts/deployments/271828.json
{
  "CREATE2_SALT": "0x0000000000000000000000000000000000000000000000000000000000000001",
  "SP1_VERIFIER_GATEWAY_GROTH16": "0x397A5f7f3dBd538f23DE225B51f532c34448dA9B",
  "SP1_VERIFIER_GATEWAY_PLONK": "0x3B6041173B80E77f038f3F2C0f9744f04837185e",
  "V4_0_0_RC_3_SP1_VERIFIER_GROTH16": "0xa27A057CAb1a4798c6242F6eE5b2416B7Cd45E5D",
  "V4_0_0_RC_3_SP1_VERIFIER_PLONK": "0xE00a3cBFC45241b33c0A44C78e26168CBc55EC63"
}
EOF

cd /tmp/sp1-contracts/lib/sp1-contracts/contracts || exit
touch /tmp/sp1-contracts/lib/sp1-contracts/contracts/.env

# Create .env file
cat << EOF > ./.env
### Salt used to deploy the contracts. Recommended to use the same salt across different chains.
CREATE2_SALT=0x0000000000000000000000000000000000000000000000000000000000000001

### The owner of the SP1 Verifier Gateway. This is the account that will be able to add and freeze routes.
OWNER="$ETH_ADDRESS"

### The chains to deploy to, specified by chain name (e.g. CHAINS=MAINNET,SEPOLIA,ARBITRUM_SEPOLIA)
CHAINS=KURTOSIS

### RPCs for each chain ID
RPC_KURTOSIS="$L1_RPC"

## Contract Deployer Private Key
PRIVATE_KEY="$PRIVATE_KEY"
EOF

cd /tmp/sp1-contracts/lib/sp1-contracts/contracts || exit
set -a
# shellcheck disable=SC1091
source .env
set +a

# Change Verifier Hash in SP1Verifier contract
# TODO: Update the hash to the correct one once Provers are ready
sed -i 's/0x865350661abdacc425126316fdaa2a67a1dc087f03c31f5cdfdc6613f501f042/0x11b6a09d00000000000000000000000000000000000000000000000000000000/' /tmp/sp1-contracts/lib/sp1-contracts/contracts/src/v3.0.0-rc4/SP1VerifierPlonk.sol
sed -i 's/0xfeb5e54e3703b9aecfb0a650545bf1a8cc4b11eba14e48afa89a95dc0bd9c867/0x11b6a09d00000000000000000000000000000000000000000000000000000000/' /tmp/sp1-contracts/lib/sp1-contracts/contracts/src/v3.0.0-rc4/SP1VerifierPlonk.sol

# Plonk Deployments
# Deploy SP1 Verifier Gateway Plonk
FOUNDRY_PROFILE=deploy forge script --legacy ./script/deploy/SP1VerifierGatewayPlonk.s.sol:SP1VerifierGatewayScript --private-key "$PRIVATE_KEY" --broadcast
# Deploy SP1 Verifier Plonk contract
FOUNDRY_PROFILE=deploy forge script ./script/deploy/v3.0.0-rc4/SP1VerifierPlonk.s.sol:SP1VerifierScript --private-key "$PRIVATE_KEY" --broadcast

# Groth16 Deployments
# Deploy SP1 Verifier Gateway Groth16
FOUNDRY_PROFILE=deploy forge script --legacy ./script/deploy/SP1VerifierGatewayGroth16.s.sol:SP1VerifierGatewayScript --private-key "$PRIVATE_KEY" --broadcast
# Deploy SP1 Verifier Groth16 contract
FOUNDRY_PROFILE=deploy forge script ./script/deploy/v4.0.0-rc.3/SP1VerifierGroth16.s.sol:SP1VerifierScript --private-key "$PRIVATE_KEY" --broadcast

# Extract SP1 Verifier Gateway Plonk address
jq -n --arg gatewayaddr "$(jq -r '.transactions[0].contractAddress' /tmp/sp1-contracts/lib/sp1-contracts/contracts/broadcast/SP1VerifierGatewayPlonk.s.sol/271828/run-latest.json)" \
'{ "SP1VERIFIERGATEWAYPLONK": $gatewayaddr }' > /tmp/sp1_verifier_out.json

# Extract SP1 Verifier Plonk addresses
jq --arg addr "$(jq -r '.transactions[0].contractAddress' /tmp/sp1-contracts/lib/sp1-contracts/contracts/broadcast/SP1VerifierPlonk.s.sol/271828/run-latest.json)" \
    '. + { "SP1VERIFIERPLONK": $addr }' /tmp/sp1_verifier_out.json > /tmp/tmp.json && mv /tmp/tmp.json /tmp/sp1_verifier_out.json

# Extract SP1 Verifier Gateway Groth16 address
jq -n --arg gatewayaddr "$(jq -r '.transactions[0].contractAddress' /tmp/sp1-contracts/lib/sp1-contracts/contracts/broadcast/SP1VerifierGatewayGroth16.s.sol/271828/run-latest.json)" \
'{ "SP1VERIFIERGATEWAYGROTH16": $gatewayaddr }' > /tmp/sp1_verifier_out.json

# Extract SP1 Verifier Groth16 addresses
jq --arg addr "$(jq -r '.transactions[0].contractAddress' /tmp/sp1-contracts/lib/sp1-contracts/contracts/broadcast/SP1VerifierGroth16.s.sol/271828/run-latest.json)" \
    '. + { "SP1VERIFIERGROTH16": $addr }' /tmp/sp1_verifier_out.json > /tmp/tmp.json && mv /tmp/tmp.json /tmp/sp1_verifier_out.json

# Append the addresses of SP1 Verifier Contracts into the op-succinct-env-vars.json file. This will be used by the OP-Succinct components to point to a real verifier.
jq -s '.[0] * .[1]' /opt/op-succinct/op-succinct-env-vars.json /tmp/sp1_verifier_out.json > /opt/op-succinct/op-succinct-env-vars.json.tmp
mv /opt/op-succinct/op-succinct-env-vars.json.tmp /opt/op-succinct/op-succinct-env-vars.json

# Update the verifier address in the OPSuccinctL2OutputOracle contract
# TODO: Remove SC2034 shellcheck - unused variables once the specs are finalized.
# shellcheck disable=SC2034
SP1_VERIFIER_GATEWAY_PLONK=$(jq '.SP1VERIFIERGATEWAYPLONK' /tmp/sp1_verifier_out.json -r)
# shellcheck disable=SC2034
SP1_VERIFIER_PLONK=$(jq '.SP1VERIFIERPLONK' /tmp/sp1_verifier_out.json -r)
# shellcheck disable=SC2034
SP1_VERIFIER_GATEWAY_GROTH16=$(jq '.SP1VERIFIERGATEWAYGROTH16' /tmp/sp1_verifier_out.json -r)
# shellcheck disable=SC2034
SP1_VERIFIER_GROTH16=$(jq '.SP1VERIFIERGROTH16' /tmp/sp1_verifier_out.json -r)
L2OO_ADDRESS=$(jq '.L2OO_ADDRESS' /opt/op-succinct/op-succinct-env-vars.json -r)
cast send "$L2OO_ADDRESS" "updateVerifier(address)" "$SP1_VERIFIER_GROTH16" --private-key "$PRIVATE_KEY" --rpc-url "$L1_RPC"

# SPN Requester address
SPN_REQUESTER_ETH_ADDRESS=$(cast wallet address --private-key "{{.agglayer_prover_sp1_key}}")
# Fund the op-succinct-proposer. This address of the agglayer_prover_sp1_key - address submitting requests to SPN
# This will allow the op-succinct-proposer to submit L1 requests to call "Propose L2Output" on the OPSuccinctL2OutputOracle contract.
cast send "$SPN_REQUESTER_ETH_ADDRESS" --private-key "{{.zkevm_l2_admin_private_key}}" --value 1ether --rpc-url "$L1_RPC"
# Add that same SPN requester address to the OPSuccinctL2OOOracle contract as approved proposer
cast send "$L2OO_ADDRESS" --private-key "$PRIVATE_KEY" "addProposer(address)" "$SPN_REQUESTER_ETH_ADDRESS" --rpc-url "$L1_RPC"