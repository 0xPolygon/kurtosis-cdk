#!/usr/bin/env bash

# Fund L1 OP addresses.
IFS=';' read -ra addresses <<<"${L1_OP_ADDRESSES}"
private_key=$(cast wallet private-key --mnemonic "{{.l1_preallocated_mnemonic}}")
for address in "${addresses[@]}"; do
    echo "Funding ${address}"
    cast send \
        --private-key "$private_key" \
        --rpc-url "{{.l1_rpc_url}}" \
        --value "{{.l2_funding_amount}}" \
        "${address}"
done

