ENCLAVE_NAME=test-failures
FUNDED_PRV_KEY=0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625
ETH_RPC_URL=$(kurtosis port print $ENCLAVE_NAME cdk-erigon-sequencer-001 rpc)
L1_RPC_URL=$(kurtosis port print $ENCLAVE_NAME anvil-001 rpc)

# Fund claimtxmanager
cast send --legacy --rpc-url $(kurtosis port print $ENCLAVE_NAME cdk-erigon-rpc-001 rpc) --private-key "$FUNDED_PRV_KEY" --value 10ether 0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8

# Deposit on L1 to avoid negative balance
polycli ulxly bridge asset \
    --value $(cast to-wei 90) \
    --gas-limit "1250000" \
    --bridge-address 0x83F138B325164b162b320F797b57f6f7E235ABAC \
    --destination-address 0xE34aaF64b29273B7D567FCFc40544c014EEe9970 \
    --destination-network 1 \
    --rpc-url "$L1_RPC_URL" \
    --private-key "$FUNDED_PRV_KEY" \
    --chain-id 271828 \
    --pretty-logs=false

# Start depositing on L2
while true; do
    polycli ulxly bridge asset \
        --value 10 \
        --gas-limit "250000" \
        --bridge-address 0x83F138B325164b162b320F797b57f6f7E235ABAC \
        --destination-address 0xE34aaF64b29273B7D567FCFc40544c014EEe9970 \
        --destination-network 0 \
        --rpc-url "$ETH_RPC_URL" \
        --private-key "$FUNDED_PRV_KEY" \
        --chain-id 10101 \
        --pretty-logs=false
    sleep 5
done
