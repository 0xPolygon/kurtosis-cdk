#!/bin/bash
ENCLAVE_NAME=test-failures
REAL_RPC_URL=http://anvil-001:8545

# MITM PROXY
L1_PROXY_NAME=mitm
L1_PROXY_PORT=8234

KURTOSIS_ARGS='{
    "args": {
        "l1_engine": "anvil",
        "l1_rpc_url": "http://'$L1_PROXY_NAME':'$L1_PROXY_PORT'",
        "cdk_node_image": "ghcr.io/0xpolygon/cdk:0.5.1-rc4",
        "agglayer_contracts_image": "leovct/zkevm-contracts:v9.0.0-rc.5-pp-fork.12",
        "deploy_l2_contracts": true,
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

# TEST PARAMS
TEST_PERCENTAGE=0.50                    # % of l1 requests to fail
TEST_DURATION=180                       # amount of time to test each failure
TIMEOUT=240                             # Time to wait for everything to settle after the failure
CHECK_SC_VERIFICATION=0                 # Disable when using soverign chain
TEST_COMPONENT=agglayer                 # Set if you want to test a single component
CLASSES="HttpErrorResponse"        # Set if you want to test a specific error class


# Just in case docker/stack was already running
docker stop "$L1_PROXY_NAME" > /dev/null 2>&1
kurtosis enclave stop "$ENCLAVE_NAME" > /dev/null 2>&1
kurtosis enclave rm "$ENCLAVE_NAME" > /dev/null 2>&1

# Add empty enclave so we can set our MITM there in advance.
kurtosis enclave add --name $ENCLAVE_NAME

# Launch mitm docker in the background
MITM_IP=$(docker network inspect kt-${ENCLAVE_NAME} | jq -r .[0].IPAM.Config[0].Subnet | cut -f1-3 -d.).199
echo > remove_me_later.py
(sleep 10 && docker run --detach --rm --name $L1_PROXY_NAME --network kt-${ENCLAVE_NAME} --ip "$MITM_IP" \
    -v "$(pwd)"/scripts/mitm/failures.py:/failures.py:ro \
    -v "$(pwd)"/remove_me_later.py:/mitm.py:ro \
    -p 127.0.0.1:8545:$L1_PROXY_PORT \
    mitmproxy/mitmproxy \
    mitmdump --mode reverse:$REAL_RPC_URL -p 8234 -s /mitm.py) &

# Deploy Kurtosis stack.
kurtosis run --enclave "$ENCLAVE_NAME" . "$KURTOSIS_ARGS"
ETH_RPC_URL=$(kurtosis port print "$ENCLAVE_NAME" cdk-erigon-sequencer-001 rpc)
export ETH_RPC_URL

echo "Kurtosis stack is ready !!"
read -r -p "Press any key to continue.."

wait_for_verification() {
    local timeout=$1
    local start_time
    start_time=$(date +%s)


    # Get current batch:
    BATCH=$(cast rpc zkevm_batchNumber)
    BATCH=$(echo "$BATCH" | tr -d '"' | xargs printf "%d")
    echo "Current batch $BATCH set as target to be verified."

    VIRTUAL_BATCH=$(cast rpc zkevm_virtualBatchNumber)
    VIRTUAL_BATCH=$(echo "$VIRTUAL_BATCH" | tr -d '"' | xargs printf "%d")

    VERIFIED_BATCH=$(cast rpc zkevm_verifiedBatchNumber)
    VERIFIED_BATCH=$(echo "$VERIFIED_BATCH" | tr -d '"' | xargs printf "%d")

    # while verified batch is less than the current batch, sleep
    while [ "$VERIFIED_BATCH" -lt "$BATCH" ]; do
        # Check elapsed time
        local current_time
        current_time=$(date +%s)
        local elapsed
        elapsed=$((current_time - start_time))

        if [ "$elapsed" -ge "$timeout" ]; then
            echo "Timeout reached ($timeout seconds). Exiting..."
            return 1
        fi

        echo "Verified batch is $VERIFIED_BATCH, Virtual batch is $VIRTUAL_BATCH, target batch is $BATCH. Sleeping for a while..."
        sleep 10
        VIRTUAL_BATCH=$(cast rpc zkevm_virtualBatchNumber)
        VIRTUAL_BATCH=$(echo "$VIRTUAL_BATCH" | tr -d '"' | xargs printf "%d")
        VERIFIED_BATCH=$(cast rpc zkevm_verifiedBatchNumber)
        VERIFIED_BATCH=$(echo "$VERIFIED_BATCH" | tr -d '"' | xargs printf "%d")
    done
    echo "DONE. Verified batch is $VERIFIED_BATCH, Virtual batch is $VIRTUAL_BATCH, target batch was $BATCH."
    return 0
}


if [ -n "$TEST_COMPONENT" ]; then
    DOCKER_ID="$(docker ps | grep "$(kurtosis service inspect "$ENCLAVE_NAME" "$TEST_COMPONENT" | grep UUID | awk '{print $2}')" | awk '{print $1}')"
    COMPONENT_IP=$(docker inspect "$DOCKER_ID" | jq -r '.[0].NetworkSettings.Networks."kt-'$ENCLAVE_NAME'".IPAddress')
    SELECTED_PEERS="'$COMPONENT_IP'"
    echo "Selected peers: $SELECTED_PEERS"
fi


# Set CLASSESS if empty
if [ -z "$CLASSES" ]; then
    CLASSES=$(sed -n 's/^class \([A-Za-z0-9]\+\).*/\1/p'  scripts/mitm/failures.py  | grep -v Generic)
fi
# Test failures, 2 minutes each
for class in $CLASSES; do
    echo "import failures" > remove_me_later.py
    if [ "$class" == "RedirectRequest" ]; then
        redirect_url="http://cdk-erigon-rpc-001:8123"
        echo "addons = [failures.${class}(${TEST_PERCENTAGE}, [$SELECTED_PEERS], '${redirect_url}')]" >> remove_me_later.py
    else
        echo "addons = [failures.${class}(${TEST_PERCENTAGE}, [$SELECTED_PEERS])]" >> remove_me_later.py
    fi
    echo >> remove_me_later.py
    echo "Testing failure class $class for a $TEST_DURATION seconds"
    sleep $TEST_DURATION
    echo "Resuming normal operation"
    echo > remove_me_later.py
    if [ "$CHECK_SC_VERIFICATION" -eq 1 ]; then
        if wait_for_verification "$TIMEOUT"; then
            echo "Verification successful!"
        else
            echo "Verification timed out. Restarting cdk-node and retrying..."
            kurtosis service stop "$ENCLAVE_NAME" cdk-node-001
            kurtosis service start "$ENCLAVE_NAME" cdk-node-001
            if wait_for_verification "$TIMEOUT"; then
                echo "Verification successful AFTER RESTART!"
            else
                echo "Verification was unable to complete even after restart"
                exit 1
            fi
        fi
    else
        echo "Waiting for 20 seconds to let everything settle..."
        sleep 20
    fi
done

read -r -p "Press any key to cleanup everything.."
# Clean UP
echo "Cleaning up..."
kurtosis enclave stop "$ENCLAVE_NAME"
kurtosis enclave rm "$ENCLAVE_NAME"
docker stop "$L1_PROXY_NAME"
rm remove_me_later.py
