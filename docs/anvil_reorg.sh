ENCLAVE_NAME=cdk
CDK_NODE_VERS=0.5.1-rc3
REAL_RPC_URL=http://el-1-geth-lighthouse:8545

# Add empty enclave so we can set our MITM there in advance.
kurtosis enclave add --name $ENCLAVE_NAME

# Kurtosis hardcodes the usage of ips, and it expects to find the first IP of the range available, it does NOT check if it's already used, and then execution fails.
MITM_IP=$(docker network inspect kt-$ENCLAVE_NAME | jq -r .[0].IPAM.Config[0].Subnet | cut -f1-3 -d.).99
# Deploy MITM, just forwarding to real L1 right now.
docker run --detach --rm --name mitm --network kt-${ENCLAVE_NAME} --ip $MITM_IP \
    mitmproxy/mitmproxy \
    mitmdump --mode reverse:http://el-1-geth-lighthouse:8545 -p 8234

# Deploy the stack.
kurtosis run --enclave $ENCLAVE_NAME . \
    '{ "args": {
          "l1_rpc_url": "http://mitm:8234",
          "cdk_node_image": "ghcr.io/0xpolygon/cdk:'$CDK_NODE_VERS'"
        }
    }'

# Everything is deployed and should be working normally at that point.
# Let's allow some time for sequencing/verifying something.
sleep 60

# Stop L1 proxy, to avoid early incosistences
docker stop mitm
sleep 3

# Vars for shadow fork
RPC_URL=http://$(kurtosis port print $ENCLAVE_NAME el-1-geth-lighthouse  rpc)
CHAINID=$(cast chain-id --rpc-url $RPC_URL)
BLOCKNUM=$(cast block-number --rpc-url $RPC_URL)

# Deploy L1 fork
docker run --detach --rm --name anvil -p 8545:8545 --network kt-${ENCLAVE_NAME} \
    ghcr.io/foundry-rs/foundry:latest \
    "anvil \
    --fork-url $REAL_RPC_URL \
    --fork-chain-id $CHAINID \
    --fork-block-number $BLOCKNUM \
    --no-rate-limit \
    --block-time 1 \
    --host 0.0.0.0 \
    --slots-in-an-epoch 5"
# Setting slots to X leads to block N-(X+1) being finalized, being N latest block

# Start MITM again pointing to shadow fork. Setting same IP just in case it got cached somewhere.
docker run --detach --rm --name mitm --network kt-${ENCLAVE_NAME} --ip $MITM_IP \
    mitmproxy/mitmproxy \
    mitmdump --mode reverse:http://anvil:8545 -p 8234


#
# SHADOW FORK WORKING HERE.
# Check logs, sequenced/verified, etc.
# Everything should be working here fine here.
#


# Let's set back the real L1, and see what happens.
docker stop mitm
sleep 5
# REORG STARTS HERE
docker run --detach --rm --name mitm --network kt-${ENCLAVE_NAME} --ip $MITM_IP \
    mitmproxy/mitmproxy \
    mitmdump --mode reverse:http://el-1-geth-lighthouse:8545 -p 8234


# CLEANUP
# docker stop anvil
# docker stop mitm
# kurtosis enclave stop $ENCLAVE_NAME
# kurtosis enclave rm $ENCLAVE_NAME
# kurtosis engine restart


# Monitoring on a separated terminal
# ENCLAVE_NAME=cdk
# RPC_URL=$(kurtosis port print $ENCLAVE_NAME cdk-erigon-sequencer-001 rpc)
# polycli monitor --rpc-url $RPC_URL
