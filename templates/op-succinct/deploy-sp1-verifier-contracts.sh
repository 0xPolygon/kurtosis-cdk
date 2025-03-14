#!/bin/bash

L1_RPC="{{.l1_rpc_url}}"
PRIVATE_KEY=$(cast wallet private-key --mnemonic "{{.l1_preallocated_mnemonic}}")
ETH_ADDRESS=$(cast wallet address --private-key $PRIVATE_KEY)

# Create the .env file
mkdir /tmp/sp1-contracts
cd /tmp/sp1-contracts || exit

git clone https://github.com/succinctlabs/sp1-contracts.git .
forge install succinctlabs/sp1-contracts

# Update Foundry.toml with the RPC_KURTOSIS
sed -i '/scroll_sepolia = "${RPC_SCROLL_SEPOLIA}"/a kurtosis = "${RPC_KURTOSIS}"' /tmp/sp1-contracts/lib/sp1-contracts/contracts/foundry.toml

# Create 271828.json Deployment artifact for Kurtosis devnet
touch /tmp/sp1-contracts/lib/sp1-contracts/contracts/deployments/271828.json
cat << EOF > /tmp/sp1-contracts/lib/sp1-contracts/contracts/deployments/271828.json
{
  "CREATE2_SALT": "0x0000000000000000000000000000000000000000000000000000000000000001",
  "SP1_VERIFIER_GATEWAY_PLONK": "0x4b0ee221beaf614ee28df4be4a46448f3e500166",
  "V4_0_0_RC_3_SP1_VERIFIER_PLONK": "0x9d3D12D0e46810389b2D5aba477C80cA8f5A552E"
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
source .env
set +a

# Plonk Deployments
# Deploy SP1 Verifier Gateway Plonk
FOUNDRY_PROFILE=deploy forge script --legacy ./script/deploy/SP1VerifierGatewayPlonk.s.sol:SP1VerifierGatewayScript --private-key "$PRIVATE_KEY" --broadcast
# Deploy SP1 Verifier Plonk contract
FOUNDRY_PROFILE=deploy forge script ./script/deploy/v4.0.0-rc.3/SP1VerifierPlonk.s.sol:SP1VerifierScript --private-key "$PRIVATE_KEY" --broadcast

# Groth16 Deployments
# Deploy SP1 Verifier Gateway Groth16
# FOUNDRY_PROFILE=deploy forge script --legacy ./script/deploy/SP1VerifierGatewayGroth16.s.sol:SP1VerifierGatewayScript --private-key "$PRIVATE_KEY" --broadcast
# Deploy SP1 Verifier Groth16 contract
# FOUNDRY_PROFILE=deploy forge script ./script/deploy/v4.0.0-rc.3/SP1VerifierGroth16.s.sol:SP1VerifierScript --private-key "$PRIVATE_KEY" --broadcast

# Extract SP1 Verifier Gateway address
jq -n --arg gatewayaddr "$(jq -r '.transactions[0].contractAddress' /tmp/sp1-contracts/lib/sp1-contracts/contracts/broadcast/SP1VerifierGatewayPlonk.s.sol/271828/run-latest.json)" \
'{ "SP1VERIFIERGATEWAY": $gatewayaddr }' > /tmp/sp1_verifier_out.json

# Extract SP1 Verifier addresses
jq --arg addr "$(jq -r '.transactions[0].contractAddress' /tmp/sp1-contracts/lib/sp1-contracts/contracts/broadcast/SP1VerifierPlonk.s.sol/271828/run-latest.json)" \
    '. + { "SP1VERIFIER": $addr }' /tmp/sp1_verifier_out.json > /tmp/tmp.json && mv /tmp/tmp.json /tmp/sp1_verifier_out.json

# Append the addresses of SP1 Verifier Contracts into the op-succinct-env-vars.json file. This will be used by the OP-Succinct components to point to a real verifier.
jq -s '.[0] * .[1]' /opt/op-succinct/op-succinct-env-vars.json /tmp/sp1_verifier_out.json > /opt/op-succinct/op-succinct-env-vars.json.tmp
mv /opt/op-succinct/op-succinct-env-vars.json.tmp /opt/op-succinct/op-succinct-env-vars.json

# Update the verifier address in the OPSuccinctL2OutputOracle contract
SP1_VERIFIER_GATEWAY=$(jq '.SP1VERIFIERGATEWAY' /tmp/sp1_verifier_out.json -r)
L2OO_ADDRESS=$(jq '.L2OO_ADDRESS' /opt/op-succinct/op-succinct-env-vars.json -r)
cast send "$L2OO_ADDRESS" "updateVerifier(address)" "$SP1_VERIFIER_GATEWAY" --private-key "$PRIVATE_KEY" --rpc-url "$L1_RPC"