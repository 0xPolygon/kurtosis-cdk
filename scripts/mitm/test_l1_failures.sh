ENCLAVE_NAME=test-failures
CDK_NODE_VERS=0.5.1-rc4
REAL_RPC_URL=http://anvil-001:8545

L1_PROXY_NAME=mitm
L1_PROXY_PORT=8234

# Just in case docker/stack was already running
docker stop $L1_PROXY_NAME > /dev/null 2>&1
kurtosis enclave stop $ENCLAVE_NAME > /dev/null 2>&1
kurtosis enclave rm $ENCLAVE_NAME > /dev/null 2>&1

# Add empty enclave so we can set our MITM there in advance.
kurtosis enclave add --name $ENCLAVE_NAME

# Launch mitm docker in the background
MITM_IP=$(docker network inspect kt-$ENCLAVE_NAME | jq -r .[0].IPAM.Config[0].Subnet | cut -f1-3 -d.).199
echo "" > remove_me_later.py
(sleep 10 && docker run --detach --rm --name $L1_PROXY_NAME --network kt-${ENCLAVE_NAME} --ip $MITM_IP \
    -v $(pwd)/scripts/mitm/failures.py:/failures.py:ro \
    -v $(pwd)/remove_me_later.py:/mitm.py:ro \
    -p 127.0.0.1:8545:$L1_PROXY_PORT \
    mitmproxy/mitmproxy \
    mitmdump --mode reverse:http://anvil-001:8545 -p 8234 -s /mitm.py) &

# Deploy Kurtosis stack.
kurtosis run --enclave $ENCLAVE_NAME . \
    '{ "args": {
          "l1_rpc_url": "http://'$L1_PROXY_NAME':'$L1_PROXY_PORT'",
          "cdk_node_image": "ghcr.io/0xpolygon/cdk:'$CDK_NODE_VERS'",
          "l1_engine": "anvil",
        }
    }'


wait_for_verification() {
    local timeout=$1
    local start_time=$(date +%s)

    # Get current batch:
    BATCH=$(cast rpc zkevm_batchNumber)
    BATCH=$(echo $BATCH | tr -d '"' | xargs printf "%d")
    echo "Current batch $BATCH set as target to be verified."

    VIRTUAL_BATCH=$(cast rpc zkevm_virtualBatchNumber)
    VIRTUAL_BATCH=$(echo $VIRTUAL_BATCH | tr -d '"' | xargs printf "%d")

    VERIFIED_BATCH=$(cast rpc zkevm_verifiedBatchNumber)
    VERIFIED_BATCH=$(echo $VERIFIED_BATCH | tr -d '"' | xargs printf "%d")

    # while verified batch is less than the current batch, sleep
    while [ $VERIFIED_BATCH -lt $BATCH ]; do
        # Check elapsed time
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        if [ $elapsed -ge $timeout ]; then
            echo "Timeout reached ($timeout seconds). Exiting..."
            return 1
        fi

        echo "Verified batch is $VERIFIED_BATCH, Virtual batch is $VIRTUAL_BATCH, target batch is $BATCH. Sleeping for a while..."
        sleep 10
        VIRTUAL_BATCH=$(cast rpc zkevm_virtualBatchNumber)
        VIRTUAL_BATCH=$(echo $VIRTUAL_BATCH | tr -d '"' | xargs printf "%d")
        VERIFIED_BATCH=$(cast rpc zkevm_verifiedBatchNumber)
        VERIFIED_BATCH=$(echo $VERIFIED_BATCH | tr -d '"' | xargs printf "%d")
    done
    echo "DONE. Verified batch is $VERIFIED_BATCH, Virtual batch is $VIRTUAL_BATCH, target batch was $BATCH."
    return 0
}

export ETH_RPC_URL=$(kurtosis port print $ENCLAVE_NAME cdk-erigon-sequencer-001 rpc)

TEST_PERCENTAGE=0.50
TEST_DURATION=120
TIMEOUT=300

# Test failures, 2 minutes each
classes=$(sed -n 's/^class \([A-Za-z0-9]\+\).*/\1/p'  scripts/mitm/failures.py  | grep -v Generic)
for class in $classes; do
    echo "import failures" > remove_me_later.py
    echo "addons = [failures.${class}(${TEST_PERCENTAGE})]" >> remove_me_later.py
    echo >> remove_me_later.py
    echo "Testing failure class $class for a $TEST_DURATION seconds"
    sleep $TEST_DURATION
    echo "Resuming normal operation"
    echo "" > remove_me_later.py
    wait_for_verification $TIMEOUT
    if [ $? -eq 0 ]; then
        echo "Verification successful!"
    else
        echo "Verification timed out. Restarting cdk-node and retrying..."
        kurtosis service stop $ENCLAVE_NAME cdk-node-001
        kurtosis service start $ENCLAVE_NAME cdk-node-001
        wait_for_verification $TIMEOUT
        if [ $? -eq 0 ]; then
            echo "Verification successful AFTER RESTART!"
        else
            echo "Verification was unable to complete even after restart"
            exit 1
        fi
    fi
done


# Clean UP
docker stop $L1_PROXY_NAME
kurtosis enclave stop $ENCLAVE_NAME
kurtosis enclave rm $ENCLAVE_NAME
rm remove_me_later.py
