#!/bin/bash
# Assembles the Besu QBFT genesis for the sovereign L2 and writes the validator node key.
#
# The sovereign bridge/GER contracts are injected the same way as on the op-reth stack: the
# agglayer-contracts createSovereignGenesis tool emits a geth-format genesis, create_op_allocs.py
# normalises it into a plain account map, and that map becomes the "alloc" section here.
set -euo pipefail

input_dir="/opt/besu-genesis-input"
allocs_dir="/opt/besu-genesis-allocs"
output_dir="/opt/besu-genesis-output"
mkdir -p "${output_dir}"

validator_private_key="{{.besu_validator_private_key}}"
validator_address="$(cast wallet address --private-key "${validator_private_key}" | tr '[:upper:]' '[:lower:]')"
echo "QBFT validator address: ${validator_address}"

# QBFT encodes its genesis extraData as the RLP of
#   [32-byte vanity, [validators], vote, round, [committed seals]].
# With exactly one 20-byte validator, no vote, round 0 and no seals, that encoding has a fixed
# shape, so it can be assembled directly instead of shelling out to an RLP encoder:
#   f83a                                    list, 58 bytes
#     a0 <32 bytes>                         vanity
#     d5 94 <20 bytes>                      one-element validator list
#     c0                                    empty vote
#     80                                    round 0
#     c0                                    empty committed seals
# Verified against `besu operator generate-blockchain-config`, which produces the same bytes.
vanity="0000000000000000000000000000000000000000000000000000000000000000"
extra_data="0xf83aa0${vanity}d594${validator_address#0x}c080c0"
echo "QBFT extraData: ${extra_data}"

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
    --arg extra_data "${extra_data}" \
    '$base | .extraData = $extra_data | .alloc = ($predeployed * $funded)' \
    > "${output_dir}/genesis.json"

# Besu reads the node key as bare hex, without the 0x prefix and without a trailing newline.
printf '%s' "${validator_private_key#0x}" > "${output_dir}/key"

echo "Besu genesis written with $(jq '.alloc | length' "${output_dir}/genesis.json") accounts"
