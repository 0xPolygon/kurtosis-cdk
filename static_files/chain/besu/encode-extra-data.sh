#!/bin/bash
# Runs in the Besu image: encodes the QBFT genesis extraData with Besu's own encoder,
#   RLP([32-byte vanity, [validators], vote, round, [committed seals]]),
# and writes it into the genesis assembled by build-genesis.sh.
set -euo pipefail

input_dir="/opt/besu-genesis-unsealed"
validators_dir="/opt/besu-genesis-validators"
output_dir="/opt/besu-genesis-output"
mkdir -p "${output_dir}"

extra_data="$(besu rlp encode --type=QBFT_EXTRA_DATA --from="${validators_dir}/validators.json" 2>/dev/null | tr -d '\r\n')"
if [[ ! "${extra_data}" =~ ^0x[0-9a-f]+$ ]]; then
    echo "besu rlp encode returned an unexpected value: '${extra_data}'" >&2
    exit 1
fi
echo "QBFT extraData: ${extra_data}"

sed "s/@@QBFT_EXTRA_DATA@@/${extra_data}/" \
    "${input_dir}/genesis-without-extra-data.json" > "${output_dir}/genesis.json"
grep -q "\"extraData\": *\"${extra_data}\"" "${output_dir}/genesis.json"
