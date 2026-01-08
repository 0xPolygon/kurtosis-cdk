#!/bin/bash
# Get arg and check its either PP of FEP
MODE=$1
if [ "$MODE" != "pp" ] && [ "$MODE" != "fep" ]; then
    echo "Usage: $0 [pp|fep]"
    exit 1
fi
ENCLAVE_NAME="reorgtester"
FUNDED_PRV_KEY=0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625
BLOCK_TIME=6
BLOCKS_PER_EPOCH=32

KURTOSIS_PP_ARGS='{
    "args": {
        "l1_engine": "anvil",
        "l1_anvil_block_time": '$BLOCK_TIME',
        "l1_anvil_slots_in_epoch": '$BLOCKS_PER_EPOCH',
        "mitm_proxied_components": {"agglayer": true, "cdk-node": true},
        "cdk_node_image": "ghcr.io/0xpolygon/cdk:0.5.1-rc4",
        "agglayer_contracts_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/zkevm-contracts:v9.0.0-rc.5-pp-fork.12",
        "consensus_contract_type": "pessimistic",
        "erigon_strict_mode": false,
        "gas_token_enabled": false,
        "zkevm_use_real_verifier": false,
        "enable_normalcy": true,
        "sp1_prover_key": "",
        "agglayer_prover_primary_prover": "mock-prover",
        "sequencer_type": "erigon"
    }
}'
KURTOSIS_FEP_ARGS='{
    "args": {
        "l1_engine": "anvil",
        "l1_anvil_block_time": '$BLOCK_TIME',
        "l1_anvil_slots_in_epoch": '$BLOCKS_PER_EPOCH',
        "mitm_proxied_components": {"agglayer": true, "cdk-node": true},
        "cdk_node_image": "ghcr.io/0xpolygon/cdk:0.5.1-rc4",
        "consensus_contract_type": "rollup",
        "additional_services": ["tx_spammer"]
    }
}'

if [ "$MODE" == "pp" ]; then
    KURTOSIS_ARGS=$KURTOSIS_PP_ARGS
else
    KURTOSIS_ARGS=$KURTOSIS_FEP_ARGS
fi
kurtosis run --enclave $ENCLAVE_NAME . "$KURTOSIS_ARGS"

L1_RPC_URL=$(kurtosis port print $ENCLAVE_NAME anvil-001 rpc)
L2_RPC_URL=$(kurtosis port print $ENCLAVE_NAME cdk-erigon-rpc-001 rpc)

# Fund claimsponsor
sleep 10
cast send --legacy --rpc-url "$L2_RPC_URL" --private-key "$FUNDED_PRV_KEY" --value 10ether 0x635243A11B41072264Df6c9186e3f473402F94e9

# Deposit on L1 to avoid negative balance
polycli ulxly bridge asset \
    --value "$(cast to-wei 90)" \
    --gas-limit "1250000" \
    --bridge-address 0x83F138B325164b162b320F797b57f6f7E235ABAC \
    --destination-address 0xE34aaF64b29273B7D567FCFc40544c014EEe9970 \
    --destination-network 1 \
    --rpc-url "$L1_RPC_URL" \
    --private-key "$FUNDED_PRV_KEY" \
    --chain-id 271828 \
    --pretty-logs=false

# Wait for tx to be finalized: block_time*slots_in_epoch
sleep $((BLOCK_TIME*BLOCKS_PER_EPOCH*2))


LATEST_BLOCK=$(cast bn --rpc-url "$L1_RPC_URL" latest)
SAFE_BLOCK=$(cast bn --rpc-url "$L1_RPC_URL" safe)
FINALIZED_BLOCK=$(cast bn --rpc-url "$L1_RPC_URL" finalized)
echo "L1 | Latest: $LATEST_BLOCK, Safe: $SAFE_BLOCK, Finalized: $FINALIZED_BLOCK"

# Wait until there at least 5 finaled blocks on L1
while [ "$FINALIZED_BLOCK" -lt 5 ]; do
    echo "Waiting for at least 5 finalized blocks ($FINALIZED_BLOCK so far)"
    sleep $BLOCK_TIME
    FINALIZED_BLOCK=$(cast bn --rpc-url "$L1_RPC_URL" finalized)
done

FORK_BLOCK=$(cast bn --rpc-url "$L1_RPC_URL" latest)

docker run --detach --name fork --rm --network kt-${ENCLAVE_NAME} -p 8545:8545 \
    ghcr.io/foundry-rs/foundry:v1.0.0-rc \
        "anvil \
        --block-time $BLOCK_TIME \
        -p 8545 \
        --slots-in-an-epoch $BLOCKS_PER_EPOCH \
        --host 0.0.0.0 \
        --fork-url http://anvil-001:8545 \
        --fork-block-number $FORK_BLOCK"

echo "Deployed fork from block $FORK_BLOCK"
FORK_RPC_URL=http://localhost:8545

sleep 3

F_LATEST_BLOCK=$(cast bn --rpc-url "$FORK_RPC_URL" latest)
F_SAFE_BLOCK=$(cast bn --rpc-url "$FORK_RPC_URL" safe)
F_FINALIZED_BLOCK=$(cast bn --rpc-url "$FORK_RPC_URL" finalized)
echo "Fork | Latest: $F_LATEST_BLOCK, Safe: $F_SAFE_BLOCK, Finalized: $F_FINALIZED_BLOCK"

# Set fork on cdknode
kurtosis service exec "$ENCLAVE_NAME" mitm-001 \
    'echo "import failures" > /scripts/empty.py'
kurtosis service exec "$ENCLAVE_NAME" mitm-001 \
    'echo "addons = [ failures.RedirectRequest(ratio=1.0, selected_peers=[], redirect_url=\"http://fork:8545\") ]" >> /scripts/empty.py'


# Let's keep the fork until we're 5 blocks behind finalized
while [ "$FINALIZED_BLOCK" -lt $((FORK_BLOCK - 6)) ]; do
    polycli ulxly bridge asset \
        --value 10 \
        --gas-limit "250000" \
        --bridge-address 0x83F138B325164b162b320F797b57f6f7E235ABAC \
        --destination-address 0xE34aaF64b29273B7D567FCFc40544c014EEe9970 \
        --destination-network 0 \
        --rpc-url "$L2_RPC_URL" \
        --private-key "$FUNDED_PRV_KEY" \
        --chain-id 10101 \
        --pretty-logs=false
    echo "Forkid from $FORK_BLOCK still ahead from finalized $FINALIZED_BLOCK"
    sleep $BLOCK_TIME

    F_LATEST_BLOCK=$(cast bn --rpc-url "$FORK_RPC_URL" latest)
    F_SAFE_BLOCK=$(cast bn --rpc-url "$FORK_RPC_URL" safe)
    F_FINALIZED_BLOCK=$(cast bn --rpc-url "$FORK_RPC_URL" finalized)
    echo "Fork | Latest: $F_LATEST_BLOCK, Safe: $F_SAFE_BLOCK, Finalized: $F_FINALIZED_BLOCK"

    LATEST_BLOCK=$(cast bn --rpc-url "$L1_RPC_URL" latest)
    SAFE_BLOCK=$(cast bn --rpc-url "$L1_RPC_URL" safe)
    FINALIZED_BLOCK=$(cast bn --rpc-url "$L1_RPC_URL" finalized)
    echo "L1 | Latest: $LATEST_BLOCK, Safe: $SAFE_BLOCK, Finalized: $FINALIZED_BLOCK"
done

# Disable fork
kurtosis service exec "$ENCLAVE_NAME" mitm-001 'echo > /scripts/empty.py'

LATEST_BLOCK=$(cast bn --rpc-url "$L1_RPC_URL" latest)
SAFE_BLOCK=$(cast bn --rpc-url "$L1_RPC_URL" safe)
FINALIZED_BLOCK=$(cast bn --rpc-url "$L1_RPC_URL" finalized)
echo "L1 | Latest: $LATEST_BLOCK, Safe: $SAFE_BLOCK, Finalized: $FINALIZED_BLOCK"

read -r -p "Press any key to continue sending bridges.."

while true; do
    polycli ulxly bridge asset \
        --value 10 \
        --gas-limit "250000" \
        --bridge-address 0x83F138B325164b162b320F797b57f6f7E235ABAC \
        --destination-address 0xE34aaF64b29273B7D567FCFc40544c014EEe9970 \
        --destination-network 0 \
        --rpc-url "$L2_RPC_URL" \
        --private-key "$FUNDED_PRV_KEY" \
        --chain-id 10101 \
        --pretty-logs=false
    # In the following line -t for timeout, -N for just 1 character
    read -r -p "Press any key to stop sending bridges" -t 5 -N 1 input
    if [[ -n $input ]]; then
        echo
        break
    fi
done

read -r -p "Press any key to clean up !!"
docker stop fork
kurtosis enclave stop "$ENCLAVE_NAME"
kurtosis enclave rm "$ENCLAVE_NAME"
