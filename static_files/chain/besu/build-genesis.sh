#!/bin/bash
# Assembles the Besu QBFT genesis for the sovereign L2 (without its extraData, which
# encode-extra-data.sh fills in with Besu's own RLP encoder) and writes the node keys.
#
# The sovereign bridge/GER contracts are injected the same way as on the op-reth stack: the
# agglayer-contracts createSovereignGenesis tool emits a geth-format genesis, create_op_allocs.py
# normalises it into a plain account map, and that map becomes the "alloc" section here.
set -euo pipefail

input_dir="/opt/besu-genesis-input"
allocs_dir="/opt/besu-genesis-allocs"
output_dir="/opt/besu-genesis-output"
mkdir -p "${output_dir}"

validator_count="{{.besu_validator_count}}"
index_base="{{.besu_validator_mnemonic_index_base}}"
mnemonic="{{.l1_preallocated_mnemonic}}"

# write_node_key <name> <private key>: Besu reads the node key as bare hex, without the 0x prefix
# and without a trailing newline. The enode id is the uncompressed public key without its 0x04
# prefix, which is what `cast wallet public-key` prints.
write_node_key() {
    mkdir -p "${output_dir}/$1"
    printf '%s' "${2#0x}" > "${output_dir}/$1/key"
    cast wallet public-key --private-key "$2" | sed 's/^0x//' | tr -d '\n' > "${output_dir}/$1/pub"
    cast wallet address --private-key "$2" | tr '[:upper:]' '[:lower:]' | tr -d '\n' > "${output_dir}/$1/address"
    echo "Besu node $1: address $(cat "${output_dir}/$1/address")"
}

if [[ "${validator_count}" -eq 1 ]]; then
    # A single node is both the validator and the RPC endpoint.
    write_node_key "validator-1" "{{.besu_validator_private_key}}"
else
    # Validator n uses mnemonic index base+n-1 and the dedicated RPC node the next one, the scheme of
    # prover-besu-qbft vectors/capture.sh (validators 100..103 and node5 = 104 for 4 validators).
    for ((n = 1; n <= validator_count; n++)); do
        write_node_key "validator-${n}" \
            "$(cast wallet private-key --mnemonic "${mnemonic}" --mnemonic-index $((index_base + n - 1)))"
    done
    write_node_key "rpc" \
        "$(cast wallet private-key --mnemonic "${mnemonic}" --mnemonic-index $((index_base + validator_count)))"
fi

# Genesis validators, sorted ascending: QBFT orders the validator set by address, and AggchainQBFT
# requires startingValidators strictly ascending.
for ((n = 1; n <= validator_count; n++)); do
    cat "${output_dir}/validator-${n}/address"
    echo
done | sort | jq -R . | jq -s -c . > "${output_dir}/validators.json"
echo "QBFT genesis validators: $(cat "${output_dir}/validators.json")"

# Accounts that must be able to transact on the L2 from block 0. The aggoracle injects global exit
# roots, the sovereign admin administers the bridge, the claim sponsor pays for claims, and the
# preallocated account is the funder the contracts scripts use to top the others up.
funded_addresses=(
    "$(cast wallet address --private-key '{{.l1_preallocated_private_key}}')"
    "{{.l2_sequencer_address}}"
    "{{.l2_aggregator_address}}"
    "{{.l2_admin_address}}"
    "{{.l2_dac_address}}"
    "{{.l2_aggoracle_address}}"
    "{{.l2_sovereignadmin_address}}"
    "{{.l2_claimsponsor_address}}"
)
# 10,000 ETH each.
genesis_balance="0x21e19e0c9bab2400000"

funded_allocs="$(printf '%s\n' "${funded_addresses[@]}" \
    | jq -R 'ascii_downcase' \
    | jq -s --arg balance "${genesis_balance}" 'map({(.): {balance: $balance}}) | add')"

# Normalise the predeployed account keys to lowercase 0x form so they cannot collide with the
# funded accounts below under a different spelling of the same address.
predeployed_allocs="$(jq 'with_entries(
    .key |= (ascii_downcase | if startswith("0x") then . else "0x" + . end)
)' "${allocs_dir}/predeployed_allocs.json")"

# Deep merge so a funded address that is also a predeploy keeps its code and storage.
jq -n \
    --argjson base "$(cat "${input_dir}/genesis-base.json")" \
    --argjson predeployed "${predeployed_allocs}" \
    --argjson funded "${funded_allocs}" \
    '$base | .extraData = "@@QBFT_EXTRA_DATA@@" | .alloc = ($predeployed * $funded)' \
    > "${output_dir}/genesis-without-extra-data.json"

echo "Besu genesis assembled with $(jq '.alloc | length' "${output_dir}/genesis-without-extra-data.json") accounts"
