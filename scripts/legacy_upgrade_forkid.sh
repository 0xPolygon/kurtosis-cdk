# Ref document
# https://github.com/0xPolygon/kurtosis-cdk/blob/main/docs/fork9-to-fork12-migration.org

# VARS - GENERAL
STACK_NAME=upgrade-test
ARGS_FILE=legacy.yml
TARGET_FORKID=12
NEW_SEQUENCER_NAME=erigon-sequencer

cp .github/tests/combinations/fork9-legacy-zkevm-stack-rollup.yml "$ARGS_FILE"
kurtosis run --enclave "$STACK_NAME" --args-file "$ARGS_FILE" .

# VARS - KURTOSIS
DOCKER_NETWORK=kt-${STACK_NAME}
SVC_RPC=zkevm-node-rpc-001
SVC_SEQUENCER=zkevm-node-sequencer-001
SVC_CONTRACTS=contracts-001
PRIV_KEY=0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625

cast send --rpc-url $(kurtosis port print "$STACK_NAME" $SVC_RPC rpc) --legacy --private-key $PRIV_KEY --value 0.01ether 0x0000000000000000000000000000000000000000


haltonbn=$(($(printf "%d\n" $(cast rpc --rpc-url $(kurtosis port print "$STACK_NAME" $SVC_SEQUENCER rpc) zkevm_batchNumber | jq -r))+5))
echo "Halting on batch number: $haltonbn"
kurtosis service exec $STACK_NAME $SVC_SEQUENCER "sed -i 's/HaltOnBatchNumber = 0/HaltOnBatchNumber = '$haltonbn'/' /etc/zkevm/node-config.toml"
kurtosis service stop "$STACK_NAME" $SVC_SEQUENCER
kurtosis service start "$STACK_NAME" $SVC_SEQUENCER

# Wait for sequencer to be halted
while ! kurtosis service logs -n 1 "$STACK_NAME" $SVC_SEQUENCER | grep -q "finalizer reached stop sequencer on batch number"; do
    BN=$(printf "%d\n" $(cast rpc --rpc-url $(kurtosis port print "$STACK_NAME" $SVC_SEQUENCER rpc) zkevm_batchNumber | jq -r))
    echo "Waiting for sequencer to halt. Current batch: $BN, Halting on: $haltonbn"
    sleep 3
done
echo "Sequencer halted !"

DONE=0
while [ $DONE -ne 1 ]; do
    BN=$(printf "%d" $(cast rpc --rpc-url $(kurtosis port print "$STACK_NAME" $SVC_SEQUENCER rpc) zkevm_batchNumber | jq -r))
    VIBN=$(printf "%d" $(cast rpc --rpc-url $(kurtosis port print "$STACK_NAME" $SVC_SEQUENCER rpc) zkevm_virtualBatchNumber | jq -r))
    VFBN=$(printf "%d" $(cast rpc --rpc-url $(kurtosis port print "$STACK_NAME" $SVC_SEQUENCER rpc) zkevm_verifiedBatchNumber | jq -r))
    echo "Batch number: $BN, Virtual: $VIBN, Verified: $VFBN"
    if [ "$BN" -eq "$VIBN" ] && [ "$VIBN" -eq "$VFBN" ]; then
        DONE=1
    else
        sleep 3
    fi
done
echo "DONE: Sequencer status is up to date"


work_dir=$(mktemp -d)
pushd $work_dir

kurtosis service exec $STACK_NAME $SVC_CONTRACTS 'cat /opt/zkevm/genesis.json' | tail -n +2 > genesis.json
kurtosis service exec $STACK_NAME $SVC_CONTRACTS 'cat /opt/zkevm/combined.json' | tail -n +2 > combined.json 

mkdir conf
mkdir data
jq_script='
.genesis | map({
  (.address): {
    contractName: (if .contractName == "" then null else .contractName end),
    balance: (if .balance == "" then null else .balance end),
    nonce: (if .nonce == "" then null else .nonce end),
    code: (if .bytecode == "" then null else .bytecode end),
    storage: (if .storage == null or .storage == {} then null else (.storage | to_entries | sort_by(.key) | from_entries) end)
  }
}) | add'
batch_timestamp=$(jq '.firstBatchData.timestamp' combined.json)

jq "$jq_script" genesis.json > conf/dynamic-migrationexample-allocs.json
jq --arg bt "$batch_timestamp" '{"root": .root, "timestamp": ($bt | tonumber), "gasLimit": 0, "difficulty": 0}' genesis.json > conf/dynamic-migrationexample-conf.json

> conf/dynamic-migrationexample-chainspec.json cat <<EOF
{
  "ChainName": "dynamic-migrationexample",
  "chainId": 10101,
  "consensus": "ethash",
  "homesteadBlock": 0,
  "daoForkBlock": 0,
  "eip150Block": 0,
  "eip155Block": 0,
  "byzantiumBlock": 0,
  "constantinopleBlock": 0,
  "petersburgBlock": 0,
  "istanbulBlock": 0,
  "muirGlacierBlock": 0,
  "berlinBlock": 0,
  "londonBlock": 9999999999999999999999999999999999999999999999999,
  "arrowGlacierBlock": 9999999999999999999999999999999999999999999999999,
  "grayGlacierBlock": 9999999999999999999999999999999999999999999999999,
  "terminalTotalDifficulty": 58750000000000000000000,
  "terminalTotalDifficultyPassed": false,
  "shanghaiTime": 9999999999999999999999999999999999999999999999999,
  "cancunTime": 9999999999999999999999999999999999999999999999999,
  "normalcyBlock": 9999999999999999999999999999999999999999999999999,
  "pragueTime": 9999999999999999999999999999999999999999999999999,
  "ethash": {}
}
EOF

mkdir datafile
docker run -it --rm -v $PWD/datafile:/datafile --network $DOCKER_NETWORK golang:1.23.3-bookworm
# run docker then do this stuff

#### DOCKER STUFF
cd
git clone https://github.com/0xPolygonHermez/zkevm-node.git
cd ~/zkevm-node/tools/datastreamer/
go build main.go

> config/tool.config.toml cat <<EOF
[Online]
URI = "localhost:6900"
StreamType = 1

[Offline]
Port = 6901
Filename = "datastream.bin"
Version = 4
ChainID = 10101
WriteTimeout = "5s"
InactivityTimeout = "120s"
InactivityCheckInterval = "5s"
UpgradeEtrogBatchNumber = 0

[StateDB]
User = "master_user"
Password = "master_password"
Name = "state_db"
Host = "postgres-001"
Port = "5432"
EnableLog = false
MaxConns = 200

[MerkleTree]
URI = ""
MaxThreads = 0
CacheFile = "merkle_tree_cache.json"

[Log]
Environment = "development"
Level = "error"
Outputs = ["stdout"]
EOF

make generate-file
cp -r datastream.* /datafile/
exit
#### END OF DOCKER STUFF


docker run --rm --name ds-host --rm -it -v $PWD/datafile:/datafile --network $DOCKER_NETWORK golang:1.23.3-bookworm
# run docker then do this stuff
#### DOCKER STUFF
cd
git clone https://github.com/0xPolygonHermez/cdk-erigon.git
cd /root/cdk-erigon/zk/debug_tools/datastream-host
go run main.go --file /datafile/datastream.bin
#### END OF DOCKER STUFF

####
#### NEW TERMINAL TAB REQUIRED ON SAME FOLDER
####
STACK_NAME=upgrade-test
DOCKER_NETWORK=kt-${STACK_NAME}
SVC_EL=el-1-geth-lighthouse

# SVC_RPC=zkevm-node-rpc-001
# SVC_SEQUENCER=zkevm-node-sequencer-001
# SVC_CONTRACTS=contracts-001
# PRIV_KEY=0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625

L1_URL=http://$(kurtosis port print "$STACK_NAME" $SVC_EL rpc)
L1_CHAINID=$(cast chain-id --rpc-url $L1_URL)
ROLLUP_ADDR=$(jq -r '.rollupAddress' combined.json)
ROLLUP_MAN_ADDR=$(jq -r '.polygonRollupManagerAddress' combined.json)
GER_ADDR=$(jq -r '.polygonZkEVMGlobalExitRootAddress' combined.json)
SEQ_ADDR=$(jq -r '.firstBatchData.sequencer' combined.json)
L1_BLOCK=$(jq -r '.deploymentRollupManagerBlockNumber' combined.json)
NEW_SEQUENCER_NAME=erigon-sequencer

> conf/dynamic-migrationexample.yaml cat <<EOF
datadir: /home/erigon/erigon-data
chain: dynamic-migrationexample
http: true

zkevm.l2-chain-id: 10101
zkevm.l2-sequencer-rpc-url: http://$NEW_SEQUENCER_NAME:8123
zkevm.l2-datastreamer-url: ds-host:6900
zkevm.l1-chain-id: $L1_CHAINID
zkevm.l1-rpc-url: http://$SVC_EL:8545

# these values need to be changed!
zkevm.address-sequencer: "$SEQ_ADDR"
zkevm.address-zkevm: "$ROLLUP_ADDR"
zkevm.address-rollup: "$ROLLUP_MAN_ADDR"
zkevm.address-ger-manager: "$GER_ADDR"

zkevm.default-gas-price: 1000000000
zkevm.max-gas-price: 0
zkevm.gas-price-factor: 0.12

zkevm.l1-rollup-id: 1
zkevm.l1-first-block: $L1_BLOCK
zkevm.datastream-version: 3

externalcl: true
http.api: [eth, debug, net, trace, web3, erigon, zkevm]
http.addr: 0.0.0.0
http.vhosts: any
http.corsdomain: any
ws: true
EOF

docker run --network $DOCKER_NETWORK \
    --name erigon --rm \
    -v $PWD/data:/home/erigon/erigon-data \
    -v $PWD/conf:/home/erigon/dynamic-configs:ro \
    hermeznetwork/cdk-erigon:v2.60.6 \
    --config /home/erigon/dynamic-configs/dynamic-migrationexample.yaml


# WHEN DONE YOU CAN STOP BOTH CONTAINERS AND REUSE TERMINAL TABS

# BACK TO TERMINAL 1

SVC_EL=el-1-geth-lighthouse
L1_URL=http://$(kurtosis port print "$STACK_NAME" $SVC_EL rpc)
L1_CHAINID=$(cast chain-id --rpc-url $L1_URL)
POL_ADDR=$(jq -r .polTokenAddress combined.json)
ADMIN_ADDR=$(jq -r .admin combined.json)
ROLLUP_ADDR=$(jq -r '.rollupAddress' combined.json)
ROLLUP_MAN_ADDR=$(jq -r '.polygonRollupManagerAddress' combined.json)
GER_ADDR=$(jq -r '.polygonZkEVMGlobalExitRootAddress' combined.json)
SEQ_ADDR=$(jq -r '.firstBatchData.sequencer' combined.json)
L1_BLOCK=$(jq -r '.deploymentRollupManagerBlockNumber' combined.json)

# ERIGON SEQUENCER CONFIG FILE
> conf/sequencer.yaml cat <<EOF
datadir: /home/erigon/erigon-data
chain: dynamic-migrationexample

zkevm.l2-chain-id: 10101
zkevm.l2-sequencer-rpc-url: "http://$NEW_SEQUENCER_NAME:8123"
zkevm.l2-datastreamer-url: "$NEW_SEQUENCER_NAME:6900"
zkevm.l2-datastreamer-timeout: "0s"

zkevm.l1-cache-enabled: false
zkevm.l1-chain-id: $L1_CHAINID
zkevm.l1-rpc-url: "http://$SVC_EL:8545"
zkevm.l1-rollup-id: 1
zkevm.l1-first-block: $L1_BLOCK
zkevm.l1-matic-contract-address: "$POL_ADDR"
zkevm.l1-block-range: 20000
zkevm.l1-query-delay: 6000
zkevm.l1-highest-block-type: "latest"

zkevm.address-sequencer: "$SEQ_ADDR"
zkevm.address-zkevm: "$ROLLUP_ADDR"
zkevm.address-rollup: "$ROLLUP_MAN_ADDR"
zkevm.address-ger-manager: "$GER_ADDR"
zkevm.address-admin: "$ADMIN_ADDR"

zkevm.executor-strict: false
zkevm.witness-full: false
zkevm.sequencer-block-seal-time: "3s"
zkevm.sequencer-batch-seal-time: "12s"
zkevm.allow-pre-eip155-transactions: true
zkevm.disable-virtual-counters: false

zkevm.allow-free-transactions: false
zkevm.default-gas-price: 1000000000
zkevm.max-gas-price: 0
zkevm.gas-price-factor: 0.12

zkevm.rpc-ratelimit: 250
zkevm.data-stream-host: "127.0.0.1"
zkevm.data-stream-port: 6900

externalcl: true
private.api.addr : "localhost:9096"

txpool.disable: false
txpool.globalslots: 30000
txpool.globalbasefeeslots: 30000
txpool.globalqueue: 30000
torrent.port: 42070

http : true
http.api : [eth, debug, net, trace, web3, erigon, txpool, zkevm]
http.addr: "0.0.0.0"
http.port: 8123
http.vhosts: '*'
http.corsdomain: '*'
ws: true
rpc.batch.limit: 500

log.json: false
log.console.verbosity: “info”

debug.timers: true
EOF

# RUN THE NEW SEQUENCER
docker run --network $DOCKER_NETWORK \
    --name $NEW_SEQUENCER_NAME --rm \
    -e CDK_ERIGON_SEQUENCER=1 \
    -v $PWD/data:/home/erigon/erigon-data \
    -v $PWD/conf:/home/erigon/dynamic-configs:ro \
    -p 18123:8123 \
    hermeznetwork/cdk-erigon:v2.60.6 \
    --config /home/erigon/dynamic-configs/sequencer.yaml


# TERMINAL 2

STACK_NAME=upgrade-test
SVC_EL=el-1-geth-lighthouse
L1_URL=http://$(kurtosis port print "$STACK_NAME" $SVC_EL rpc)
L1_CHAINID=$(cast chain-id --rpc-url $L1_URL)
POL_ADDR=$(jq -r .polTokenAddress combined.json)
ADMIN_ADDR=$(jq -r .admin combined.json)
ROLLUP_ADDR=$(jq -r '.rollupAddress' combined.json)
ROLLUP_MAN_ADDR=$(jq -r '.polygonRollupManagerAddress' combined.json)
GER_ADDR=$(jq -r '.polygonZkEVMGlobalExitRootAddress' combined.json)
SEQ_ADDR=$(jq -r '.firstBatchData.sequencer' combined.json)
L1_BLOCK=$(jq -r '.deploymentRollupManagerBlockNumber' combined.json)
BRIDGE_ADDR=$(jq -r '.polygonZkEVMBridgeAddress' combined.json)

NEW_SEQUENCER_NAME=erigon-sequencer
KEYSTORE_PASS=$(kurtosis service exec $STACK_NAME zkevm-node-aggregator-001 "grep Password /etc/zkevm/node-config.toml" | head -2 | tail -1 | cut -f2 -d'=' | tr -d ' ','"')

> conf/cdknode.toml cat <<EOF
PathRWData = "/tmp"
L1URL="http://$SVC_EL:8545"
L2URL="http://$NEW_SEQUENCER_NAME:8123"
AggLayerURL="http://agglayer:4444"

ForkId = 9
ContractVersions = "elderberry"
IsValidiumMode = false

L2Coinbase =  "$SEQ_ADDR"
SequencerPrivateKeyPath = "/sequencer.keystore"
SequencerPrivateKeyPassword  = "$KEYSTORE_PASS"

AggregatorPrivateKeyPath = "/aggregator.keystore"
AggregatorPrivateKeyPassword  = "$KEYSTORE_PASS"
SenderProofToL1Addr = "0x351e560852ee001d5D19b5912a269F849f59479a"
polygonBridgeAddr = "$BRIDGE_ADDR"


RPCURL = "http://$NEW_SEQUENCER_NAME:8123"
WitnessURL = "http://$NEW_SEQUENCER_NAME:8123"

# This values can be override directly from genesis.json
rollupCreationBlockNumber = "$L1_BLOCK"
rollupManagerCreationBlockNumber = "$L1_BLOCK"
genesisBlockNumber = "$L1_BLOCK"
[L1Config]
        chainId = "$L1_CHAINID"
        polygonZkEVMGlobalExitRootAddress = "$GER_ADDR"
        polygonRollupManagerAddress = "$ROLLUP_MAN_ADDR"
        polTokenAddress = "$POL_ADDR"
        polygonZkEVMAddress = "$ROLLUP_ADDR"

[L2Config]
        GlobalExitRootAddr = "$GER_ADDR"

[Log]
Environment = "development" # "production" or "development"
Level = "info"
Outputs = ["stderr"]

[Aggregator]
        Port = "50081"
        RetryTime = "30s"
        VerifyProofInterval = "10s"
        GasOffset = 150000
        SettlementBackend = "agglayer"
[RPC]
        Port = 5576

[AggSender]
CertificateSendInterval = "1m"
CheckSettledInterval = "5s"
MaxCertSize = 102760448
SaveCertificatesToFilesPath="/tmp"

[L1InfoTreeSync]
# The initial block number from which to start syncing.
# Default: 0
InitialBlock = $L1_BLOCK
EOF

kurtosis service stop $STACK_NAME zkevm-node-synchronizer-001 zkevm-node-sequencer-001 zkevm-node-synchronizer-pless-001 zkevm-node-rpc-001 zkevm-node-rpc-pless-001 zkevm-node-aggregator-001 zkevm-node-sequence-sender-001
kurtosis files download $STACK_NAME sequencer-keystore 
kurtosis files download $STACK_NAME aggregator-keystore 

# Reusing aggr name so existing prover can be used
docker run -it --network $DOCKER_NETWORK \
    --name zkevm-node-aggregator-001 --rm \
    -v $PWD/sequencer-keystore/sequencer.keystore:/sequencer.keystore:ro \
    -v $PWD/aggregator-keystore/aggregator.keystore:/aggregator.keystore:ro \
    -v $PWD/conf/cdknode.toml:/config.toml:ro \
    ghcr.io/0xpolygon/cdk:0.5.0-rc1 \
    sh -c "cdk-node run -cfg=/config.toml -components=aggregator,sequence-sender"


# NEW TERMINAL on SAME TMP FOLDEr
STACK_NAME=upgrade-test
NEW_SEQUENCER_NAME=erigon-sequencer

# Set the new url to the agglayer
kurtosis service exec $STACK_NAME agglayer "sed -i 's/zkevm-node-rpc-001/'$NEW_SEQUENCER_NAME'/' /etc/zkevm/agglayer-config.toml"
kurtosis service stop $STACK_NAME agglayer
kurtosis service start $STACK_NAME agglayer

# required for prover to reconnect to "aggregator" (cdknode now)
kurtosis service stop $STACK_NAME zkevm-prover-001
kurtosis service start $STACK_NAME zkevm-prover-001

# Halting the NEW sequencer
echo "Halting sequencer..."
HALTBN=$(($(printf "%d" $(cast rpc --rpc-url http://localhost:18123 zkevm_batchNumber | jq -r))+5))
echo "zkevm.sequencer-halt-on-batch-number: $HALTBN" >> conf/sequencer.yaml
docker stop $NEW_SEQUENCER_NAME

# ********** MANUALLY START THE SEQUENCER AGAIN ON TERMINAL 1

DONE=0
while [ $DONE -ne 1 ]; do
    BN=$(printf "%d" $(cast rpc --rpc-url http://localhost:18123 zkevm_batchNumber | jq -r))
    VIBN=$(printf "%d" $(cast rpc --rpc-url http://localhost:18123 zkevm_virtualBatchNumber | jq -r))
    VFBN=$(printf "%d" $(cast rpc --rpc-url http://localhost:18123 zkevm_verifiedBatchNumber | jq -r))
    echo "Batch number: $BN, Virtual: $VIBN, Verified: $VFBN (Halt: $HALTBN)"
    if [ "$BN" -eq "$VIBN" ] && [ "$VIBN" -eq "$VFBN" ]; then
        DONE=1
    else
        sleep 3
    fi
done
echo "DONE: New Sequencer status is up to date"


# STOP SEQUENCER TO PROCEED WITH CONTRACT UPGRADE
docker stop $NEW_SEQUENCER_NAME


# BACK TO TERMINAL 1 (Sequencer just stopped)
kurtosis service shell "$STACK_NAME" $SVC_CONTRACTS

# DOCKER STUFF
cd /opt/zkevm-contracts
git checkout main
git pull
git stash
git checkout v8.1.0-rc.2-fork.13
git stash apply
rm -rf artifacts cache node_modules
npm i

rollup_manager_addr="$(cat /opt/zkevm/combined.json | jq -r '.polygonRollupManagerAddress')"
admin_private_key="$(cat deployment/v2/deploy_parameters.json | jq -r '.deployerPvtKey')"

cat upgrade/upgradeBanana/upgrade_parameters.json.example |
    jq --arg rum $rollup_manager_addr \
       --arg sk $admin_private_key \
       --arg tld 60 '.rollupManagerAddress = $rum | .timelockDelay = $tld | .deployerPvtKey = $sk' > upgrade/upgradeBanana/upgrade_parameters.json

npx hardhat run ./upgrade/upgradeBanana/upgradeBanana.ts --network localhost

scheduleData=$(jq -r '.scheduleData' upgrade/upgradeBanana/upgrade_output.json)
executeData=$(jq -r '.executeData' upgrade/upgradeBanana/upgrade_output.json)

time_lock_address="$(cat /opt/zkevm/combined.json | jq -r '.timelockContractAddress')"
rpc_url="http://el-1-geth-lighthouse:8545"

cast send --rpc-url "$rpc_url" --private-key "$admin_private_key" "$time_lock_address" "$scheduleData"
sleep 60
cast send --rpc-url "$rpc_url" --private-key "$admin_private_key" "$time_lock_address" "$executeData"


genesis_root="$(cat /opt/zkevm/genesis.json | jq -r '.root')"
description="migrationexample genesis"

# We're going to use the SAME verifier for this test because it's use a mock prover here anyway
# If this were a real network, we'd need to deploy the fflonk 12 verifier
verifier_addr="$(cat /opt/zkevm/combined.json | jq -r '.verifierAddress')"
cp /opt/zkevm/genesis.json tools/addRollupType/genesis.json

cat tools/addRollupType/add_rollup_type.json.example |
    jq --arg rum $rollup_manager_addr \
       --arg sk $admin_private_key \
       --arg gr $genesis_root \
       --arg vf $verifier_addr \
       --arg desc "$description" \
       --arg fid 13 \
       --arg tld 60 '
           .consensusContract = "PolygonZkEVMEtrog" |
           .polygonRollupManagerAddress = $rum |
           .timelockDelay = $tld |
           .deployerPvtKey = $sk |
           .forkID = $fid |
           .genesisRoot = $gr |
           .description = $desc |
           .verifierAddress = $vf' > tools/addRollupType/add_rollup_type.json

npx hardhat run ./tools/addRollupType/addRollupType.ts --network localhost


rollup_addr="$(cat /opt/zkevm/combined.json | jq -r '.rollupAddress')"

cat tools/updateRollup/updateRollup.json.example |
    jq --arg rum $rollup_manager_addr \
       --arg sk $admin_private_key \
       --arg ru $rollup_addr \
       --arg tld 60 '
           .polygonRollupManagerAddress = $rum |
           .timelockDelay = $tld |
           .deployerPvtKey = $sk |
           .newRollupTypeID = 2 |
           .rollupAddress = $ru' > tools/updateRollup/updateRollup.json

npx hardhat run ./tools/updateRollup/updateRollup.ts --network localhost

cast send --private-key "$admin_private_key" --rpc-url "$rpc_url" "$rollup_addr" 'setTrustedSequencerURL(string)' http://${NEW_SEQUENCER_NAME}:8123
# END OF DOCKER STUFF


sed -ni '/zkevm.sequencer-halt-on-batch-number/!p' conf/sequencer.yaml


# RUN SEQUENCER AGAIN
docker run --network $DOCKER_NETWORK \
    --name $NEW_SEQUENCER_NAME --rm \
    -e CDK_ERIGON_SEQUENCER=1 \
    -v $PWD/data:/home/erigon/erigon-data \
    -v $PWD/conf:/home/erigon/dynamic-configs:ro \
    -p 18123:8123 \
    hermeznetwork/cdk-erigon:v2.60.6 \
    --config /home/erigon/dynamic-configs/sequencer.yaml
# hurray, it detects forkid upgrade and start generating new blocks in fork13

# TERMINAL 2, RUN CDKNODE AGAIN

sed -i 's/ForkId = 9/ForkId = 13/' conf/cdknode.toml
sed -i 's/elderberry/banana/' conf/cdknode.toml

docker run -it --network $DOCKER_NETWORK \
    --name zkevm-node-aggregator-001 --rm \
    -v $PWD/sequencer-keystore/sequencer.keystore:/sequencer.keystore:ro \
    -v $PWD/aggregator-keystore/aggregator.keystore:/aggregator.keystore:ro \
    -v $PWD/conf/cdknode.toml:/config.toml:ro \
    ghcr.io/0xpolygon/cdk:0.5.0-rc1 \
    sh -c "cdk-node run -cfg=/config.toml -components=aggregator,sequence-sender"


# TERMINAL 3, Just to monitor progress:
while true; do
    BN=$(printf "%d" $(cast rpc --rpc-url http://localhost:18123 zkevm_batchNumber | jq -r))
    VIBN=$(printf "%d" $(cast rpc --rpc-url http://localhost:18123 zkevm_virtualBatchNumber | jq -r))
    VFBN=$(printf "%d" $(cast rpc --rpc-url http://localhost:18123 zkevm_verifiedBatchNumber | jq -r))
    echo "Batch number: $BN, Virtual: $VIBN, Verified: $VFBN"
    sleep 3
done


# AT THIS POINTS SEQUENCER GENERATES NEW BATCHES, AND CDKNODE SEQUENCE OK
# TO VERIFY WE SHOULD DEPLOY A NEW FORKID13 PROVER, I ASSUME THIS WORKS OK
