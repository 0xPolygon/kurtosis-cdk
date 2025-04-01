#!/usr/bin/env bash
export FOUNDRY_DISABLE_NIGHTLY_WARNING=1

private_key=$(cast wallet private-key --mnemonic "{{.l1_preallocated_mnemonic}}")

pushd /opt/op-succinct || { echo "op-succinct directory doesn't exit"; exit 1; }

set -a
source .env
set +a

cat .env

# Deploy the deploy-oracle and save the address to the l2oo_address.out
just deploy-oracle 2> deploy-oracle.out | grep -oP '0x[a-fA-F0-9]{40}' | xargs -I {} echo "L2OO_ADDRESS=\"{}\"" > /opt/op-succinct/l2oo_address.out
# Update the L2OO_ADDRESS in the .env file with the output from the previous command
sed -i "s/^L2OO_ADDRESS=.*$/L2OO_ADDRESS=\"$(grep -oP '0x[a-fA-F0-9]{40}' /opt/op-succinct/l2oo_address.out)\"/" /opt/op-succinct/.env

set -a
source .env
set +a

jq --arg l2oo "$L2OO_ADDRESS" '.L2OO_ADDRESS = $l2oo' /opt/op-succinct/op-succinct-env-vars.json > /opt/op-succinct/op-succinct-env-vars.json.l2oo
mv /opt/op-succinct/op-succinct-env-vars.json.l2oo /opt/op-succinct/op-succinct-env-vars.json

# TODO since we don't have the L2OO, we might have to move this until later
# Update the verifier address to the VerifierGateway contract address in the OPSuccinctL2OutputOracle contract
l2oo_address=$(jq '.L2OO_ADDRESS' /opt/op-succinct/op-succinct-env-vars.json -r)
if [[ $l2oo_address != "" ]]; then
    cast send "$l2oo_address" "updateVerifier(address)" "$SP1_VERIFIER_GATEWAY_GROTH16" --mnemonic "{{.l1_preallocated_mnemonic}}" --rpc-url "$l1_rpc_url"

    # Add that same SPN requester address to the OPSuccinctL2OOOracle contract as approved proposer
    cast send "$l2oo_address" "addProposer(address)" "$spn_requester_eth_address" --mnemonic "{{.l1_preallocated_mnemonic}}" --rpc-url "$l1_rpc_url"
fi
