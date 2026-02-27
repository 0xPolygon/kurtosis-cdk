#!/bin/bash

# Tested/supported combinations so far:
# rollup 11 -> 12
# rollup 11 -> 13
# rollup 12 -> 13
# rollup  9 -> 11
# rollup  9 -> 12
# rollup  9 -> 13

# Check we receive 2 params
if [ "$#" -ne 2 ]; then
    echo "Usage: upgrade_forkid.sh <source_forkid> <target_forkid>"
    exit 1
elif ! [[ $1 =~ ^[0-9]+$ ]] || ! [[ $2 =~ ^[0-9]+$ ]]; then
    echo "Forkids must be integers"
    exit 1
# check source forkid is 9, 11 or 12
elif [ "$1" -ne "9" ] && [ "$1" -ne "11" ] && [ "$1" -ne "12" ]; then
    echo "Source forkid must be 9, 11 or 12"
    exit 1
# check target forkid is 11, 12 or 13
elif [ "$2" -ne "11" ] && [ "$2" -ne "12" ] && [ "$2" -ne "13" ]; then
    echo "Target forkid must be 11, 12 or 13"
    exit 1
# check target forkid is greater than source forkid
elif [ "$1" -ge "$2" ]; then
    echo "Target forkid must be greater than source forkid"
    exit 1
fi

SOURCE_FORKID=$1
TARGET_FORKID=$2
ERIGON_IMAGE=hermeznetwork/cdk-erigon:v2.61.4-RC1

# L1 client types (override via environment variables)
L1_EL_TYPE="${L1_EL_TYPE:-reth}"
L1_CL_TYPE="${L1_CL_TYPE:-lighthouse}"
L1_EL_SERVICE="el-1-${L1_EL_TYPE}-${L1_CL_TYPE}"
STACK_NAME=upgradeCDK-$(
    tr -dc A-Za-z0-9 </dev/urandom | head -c 13
    echo
)

if [ "$TARGET_FORKID" -eq "11" ]; then
    TAG_TARGET_FORKID=v7.0.0-fork.10-fork.11
elif [ "$TARGET_FORKID" -eq "12" ]; then
    TAG_TARGET_FORKID=v8.0.0-rc.4-fork.12
elif [ "$TARGET_FORKID" -eq "13" ]; then
    TAG_TARGET_FORKID=v8.1.0-rc.2-fork.13
fi

PARAMS_FILE=".github/tests/combinations/fork${SOURCE_FORKID}-cdk-erigon-rollup.yml"

KURTOSIS_CONFIG=upgrade_from_${SOURCE_FORKID}_to_${TARGET_FORKID}_enclave_${STACK_NAME}.json
cp "$PARAMS_FILE" "$KURTOSIS_CONFIG"
sed -ni '/cdk_erigon_node_image/!p' "$KURTOSIS_CONFIG"
echo "  cdk_erigon_node_image: $ERIGON_IMAGE" >>"$KURTOSIS_CONFIG"

# DEPLOY STACK
kurtosis run --enclave "$STACK_NAME" --args-file "$KURTOSIS_CONFIG" .

# SERVICE NAMES
SVC_SEQUENCER=cdk-erigon-sequencer-001
SVC_RPC=cdk-erigon-rpc-001
SVC_CONTRACTS=contracts-001
SVC_SLESS_EXECUTOR=zkevm-stateless-executor-001
SVC_BRIDGE=zkevm-bridge-service-001
SVC_PROVER=zkevm-prover-001
SVC_CDKNODE=cdk-node-001

# send test tx
PRIV_KEY=0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625
cast send --rpc-url $(kurtosis port print "$STACK_NAME" $SVC_RPC rpc) --legacy --private-key $PRIV_KEY --value 0.01ether 0x0000000000000000000000000000000000000000

# Halt sequencer
echo "Halting sequencer..."
kurtosis service exec "$STACK_NAME" $SVC_SEQUENCER \
    "HALTON=\$(printf \"%d\\n\" \$((\$(curl -s -X POST -H \"Content-Type: application/json\" -d '{\"method\":\"zkevm_batchNumber\",\"id\":1,\"jsonrpc\":\"2.0\"}' http://localhost:8123 | jq -r .result)+2))); \
    sed -i 's/zkevm.sequencer-halt-on-batch-number: 0/zkevm.sequencer-halt-on-batch-number: '\$HALTON'/' /etc/cdk-erigon/config.yaml"
# echo \"zkevm.sequencer-halt-on-batch-number: \$HALTON\" >> /etc/erigon/erigon-sequencer.yaml"
kurtosis service stop "$STACK_NAME" $SVC_SEQUENCER
kurtosis service start "$STACK_NAME" $SVC_SEQUENCER

# Wait for sequencer to be halted
while ! kurtosis service logs -n 1 "$STACK_NAME" $SVC_SEQUENCER | grep -q "Halt sequencer on batch"; do
    echo "Waiting for sequencer to halt"
    sleep 3
done
echo "Sequencer halted !"

# Update contracts folder
kurtosis service exec "$STACK_NAME" $SVC_CONTRACTS "cd /opt/agglayer-contracts && git stash && git checkout main && git pull && git checkout $TAG_TARGET_FORKID"

# create env file for the commands we need to execute on contracts service
kurtosis service exec "$STACK_NAME" $SVC_CONTRACTS "echo 'cd /opt' > /opt/commands.sh"
kurtosis service exec "$STACK_NAME" $SVC_CONTRACTS "echo 'export ETH_RPC_URL=http://${L1_EL_SERVICE}:8545' >> /opt/commands.sh"
kurtosis service exec "$STACK_NAME" $SVC_CONTRACTS "echo 'ROLLUP_MAN=\$(cat zkevm/combined.json  | jq -r .polygonRollupManagerAddress)' >> /opt/commands.sh"
kurtosis service exec "$STACK_NAME" $SVC_CONTRACTS "echo 'ROLLUP=\$(cat zkevm/combined.json | jq -r .rollupAddress)' >> /opt/commands.sh"
kurtosis service exec "$STACK_NAME" $SVC_CONTRACTS "echo 'GENESIS=\$(cat zkevm/combined.json  | jq -r .genesis)' >> /opt/commands.sh"
kurtosis service exec "$STACK_NAME" $SVC_CONTRACTS "echo \"CONSENSUS=\\\$(cast call \\\$ROLLUP_MAN 'rollupTypeMap(uint32)(address,address,uint64,uint8,bool,bytes32)' 1 | head -1)\" >> /opt/commands.sh"
kurtosis service exec "$STACK_NAME" $SVC_CONTRACTS "echo PRIV_KEY=0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625 >> /opt/commands.sh"
kurtosis service exec "$STACK_NAME" $SVC_CONTRACTS "echo 'cd /opt/agglayer-contracts && git checkout $TAG_TARGET_FORKID' >> /opt/commands.sh"
kurtosis service exec "$STACK_NAME" $SVC_CONTRACTS "chmod +x /opt/commands.sh"

# wait for batches to be verified on sequencer
echo "Waiting for everything to verify and sync on sequencer"
DONE=0
while [ $DONE -ne 1 ]; do
    TRUSTED__ON_SEQCR=$(printf "%d" $(cast rpc --json --rpc-url $(kurtosis port print "$STACK_NAME" $SVC_SEQUENCER rpc) zkevm_batchNumber | jq -r))
    VERIFIED_ON_SEQCR=$(printf "%d" $(cast rpc --json --rpc-url $(kurtosis port print "$STACK_NAME" $SVC_SEQUENCER rpc) zkevm_verifiedBatchNumber | jq -r))
    VERIFIED_ON_CHAIN=$(kurtosis service exec "$STACK_NAME" $SVC_CONTRACTS ". /opt/commands.sh && cast call \$ROLLUP_MAN \"rollupIDToRollupData(uint32)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint64,uint64,uint8)\" 1 | head -6 | tail -1" | tail -2 | head -1)
    echo "Trusted batch number on sequencer: $TRUSTED__ON_SEQCR, Verified batch number on sequencer: $VERIFIED_ON_SEQCR, Verified batch number on chain: $VERIFIED_ON_CHAIN"
    if [ "$TRUSTED__ON_SEQCR" -ne "$VERIFIED_ON_SEQCR" ] || [ "$TRUSTED__ON_SEQCR" -ne "$VERIFIED_ON_CHAIN" ]; then
        sleep 5
    else
        DONE=1
    fi
done
echo "DONE: Sequencer status is up to date"

# wait for rpc to sync
echo "Waiting for RPC to be totally synced"
DONE=0
while [ $DONE -ne 1 ]; do
    TRUSTED__ON_RPC=$(printf "%d" $(cast rpc --json --rpc-url $(kurtosis port print "$STACK_NAME" $SVC_RPC rpc) zkevm_batchNumber | jq -r))
    VERIFIED_ON_RPC=$(printf "%d" $(cast rpc --json --rpc-url $(kurtosis port print "$STACK_NAME" $SVC_RPC rpc) zkevm_verifiedBatchNumber | jq -r))
    VERIFIED_ON_CHAIN=$(kurtosis service exec "$STACK_NAME" $SVC_CONTRACTS ". /opt/commands.sh && cast call \$ROLLUP_MAN \"rollupIDToRollupData(uint32)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint64,uint64,uint8)\" 1 | head -6 | tail -1" | tail -2 | head -1)
    echo "Trusted batch number on rpc: $TRUSTED__ON_RPC, Verified batch number on rpc: $VERIFIED_ON_RPC, Verified batch number on chain: $VERIFIED_ON_CHAIN"
    if [ "$TRUSTED__ON_RPC" -ne "$VERIFIED_ON_RPC" ] || [ "$TRUSTED__ON_RPC" -ne "$VERIFIED_ON_CHAIN" ]; then
        sleep 5
    else
        DONE=1
    fi
done
echo "DONE: RPC status is up to date"

# Stop services
echo "Stopping services..."
kurtosis service stop "$STACK_NAME" $SVC_CDKNODE
kurtosis service stop "$STACK_NAME" $SVC_PROVER
kurtosis service stop "$STACK_NAME" $SVC_BRIDGE
kurtosis service stop "$STACK_NAME" $SVC_RPC
kurtosis service stop "$STACK_NAME" $SVC_SEQUENCER
kurtosis service stop "$STACK_NAME" $SVC_SLESS_EXECUTOR

# Deploy verifier
echo "Deploying verifier..."
kurtosis service exec "$STACK_NAME" $SVC_CONTRACTS \
    ". /opt/commands.sh && \
    forge create \
    --broadcast \
    --json \
    --private-key \$PRIV_KEY \
    /opt/agglayer-contracts/contracts/mocks/VerifierRollupHelperMock.sol:VerifierRollupHelperMock > /opt/verifier-out.json"

# Add new rollup type
echo "Adding new rollup type..."
kurtosis service exec "$STACK_NAME" $SVC_CONTRACTS \
    ". /opt/commands.sh && \
    cast send \
    --json \
    --private-key \$PRIV_KEY \
    \$ROLLUP_MAN \
    'addNewRollupType(address,address,uint64,uint8,bytes32,string)' \
    \$CONSENSUS \
    \"\$(jq -r '.deployedTo' /opt/verifier-out.json)\" \
    $TARGET_FORKID 0 \$GENESIS 'new_forkid_$TARGET_FORKID' > /opt/add-rollup-type-out.json"

# Update rollup
echo "Updating rollup..."
kurtosis service exec "$STACK_NAME" $SVC_CONTRACTS \
    ". /opt/commands.sh && \
    cast send \
    --json \
    --private-key \$PRIV_KEY \
    \$ROLLUP_MAN \
    'updateRollup(address,uint32,bytes)' \
    \$ROLLUP \
    \$(printf \"%d\\n\" \$(jq -r '.logs[0].topics[1]' /opt/add-rollup-type-out.json)) \
    0x > /opt/update-rollup-type-out.json"

# Verify forkid on chain
echo "Checking on chain forkid..."
FORKID_ON_CHAIN=$(kurtosis service exec "$STACK_NAME" $SVC_CONTRACTS ". /opt/commands.sh && cast call \$ROLLUP_MAN \"rollupIDToRollupData(uint32)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint64,uint64,uint8)\" 1 | head -4 | tail -1" | tail -2 | head -1)
if [ "$FORKID_ON_CHAIN" -ne "$TARGET_FORKID" ]; then
    echo "KO: Forkid not updated on chain!"
    exit 1
else
    echo "OK: Forkid on chain: $FORKID_ON_CHAIN"
fi

# Unhalt sequencer
echo "Unhalting sequencer..."
kurtosis service start "$STACK_NAME" $SVC_SEQUENCER
kurtosis service exec "$STACK_NAME" $SVC_SEQUENCER \
    "sed -ni '/zkevm.sequencer-halt-on-batch-number/"\!"p' /etc/cdk-erigon/config.yaml; \
    echo \"zkevm.sequencer-halt-on-batch-number: 0\" >> /etc/cdk-erigon/config.yaml"
kurtosis service stop "$STACK_NAME" $SVC_SEQUENCER
kurtosis service start "$STACK_NAME" $SVC_SEQUENCER

# Wait for sequencer to become responsive
echo "Waiting for Sequencer's rpc port to become available"
until cast rpc --json --rpc-url $(kurtosis port print "$STACK_NAME" "$SVC_SEQUENCER" rpc) zkevm_getForkId &>/dev/null; do
    printf '.'
    sleep 3
done
echo

# Check forkid on Sequencer
FORKID=$SOURCE_FORKID
while [ "$FORKID" -ne "$TARGET_FORKID" ]; do
    FORKID=$(printf "%d" $(cast rpc --json --rpc-url $(kurtosis port print "$STACK_NAME" "$SVC_SEQUENCER" rpc) zkevm_getForkId | jq -r))
    echo "Current Sequencer forkid: $FORKID"
    sleep 3
done
echo "SEQUENCER SUCCESSFULLY UPGRADED TO FORKID $TARGET_FORKID"

# Start RPC as well
kurtosis service start "$STACK_NAME" $SVC_RPC

# Wait for rpc to become responsive
echo "Waiting for RPC's rpc port to become available"
until cast rpc --json --rpc-url $(kurtosis port print "$STACK_NAME" "$SVC_RPC" rpc) zkevm_getForkId &>/dev/null; do
    printf '.'
    sleep 3
done
echo

# Check forkid on RPC
FORKID=$SOURCE_FORKID
COUNTER=0
MAX_RETRIES=25
while [ "$FORKID" -ne "$TARGET_FORKID" ]; do
    ((COUNTER++))
    FORKID=$(printf "%d" $(cast rpc --json --rpc-url $(kurtosis port print "$STACK_NAME" "$SVC_RPC" rpc) zkevm_getForkId | jq -r))
    echo "Current RPC forkid: $FORKID"
    if [[ $COUNTER -ge $MAX_RETRIES ]]; then
        FORKID=$TARGET_FORKID # To break the loop
    else
        sleep 3
    fi
done
# If we reached max_retries on counter, it didn't succeed
if [[ $COUNTER -ge $MAX_RETRIES ]]; then
    echo "ERROR: RPC NOT ABLE to DETECT NEW FORKID $TARGET_FORKID"
else
    echo "SUCCESS: RPC ALSO ON FORKID $TARGET_FORKID"
fi

# clean up
echo "Cleaning up deployed enclave..."
rm "$KURTOSIS_CONFIG"
kurtosis enclave stop "$STACK_NAME"
kurtosis enclave rm "$STACK_NAME"

exit 0
