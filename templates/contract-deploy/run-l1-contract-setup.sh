#!/bin/bash
# This script is responsible for deploying the contracts for zkEVM/CDK.

# --------------------------------------------------------------------------------------------------
#   _____ _   _ _   _  ____ _____ ___ ___  _   _ ____  
#  |  ___| | | | \ | |/ ___|_   _|_ _/ _ \| \ | / ___| 
#  | |_  | | | |  \| | |     | |  | | | | |  \| \___ \ 
#  |  _| | |_| | |\  | |___  | |  | | |_| | |\  |___) |
#  |_|    \___/|_| \_|\____| |_| |___\___/|_| \_|____/ 
#
# --------------------------------------------------------------------------------------------------

echo_ts() {
    green="\e[32m"
    end_color="\e[0m"

    timestamp=$(date +"[%Y-%m-%d %H:%M:%S]")
    echo -e "$green$timestamp$end_color $1" >&2
}

wait_for_rpc_to_be_available() {
    counter=0
    max_retries=20
    until cast send --rpc-url "{{.l1_rpc_url}}" --mnemonic "{{.l1_preallocated_mnemonic}}" --value 0 "{{.zkevm_l2_sequencer_address}}" &> /dev/null; do
        ((counter++))
        echo_ts "Can't send L1 transfers yet... Retrying ($counter)..."
        if [[ $counter -ge $max_retries ]]; then
            echo_ts "Exceeded maximum retry attempts. Exiting."
            exit 1
        fi
        sleep 5
    done
}

wait_for_finalized_block() {
    counter=0
    max_retries=100
    until cast block --rpc-url "{{.l1_rpc_url}}" finalized &> /dev/null; do
        ((counter++))
        echo_ts "No finalized block yet... Retrying ($counter)..."
        if [[ $counter -ge $max_retries ]]; then
            echo_ts "Exceeded maximum retry attempts. Exiting."
            exit 1
        fi
        sleep 5
    done
}

fund_address_on_l1() {
    name="$1"
    address="$2"
    echo_ts "Funding $name address"
    cast send \
        --rpc-url "{{.l1_rpc_url}}" \
        --mnemonic "{{.l1_preallocated_mnemonic}}" \
        --value "{{.l1_funding_amount}}" \
        "$address"
}

deploy_gas_token_contract() {
    echo_ts "Deploying gas token to L1"
    forge create \
        --json \
        --rpc-url "{{.l1_rpc_url}}" \
        --mnemonic "{{.l1_preallocated_mnemonic}}" \
        contracts/mocks/ERC20PermitMock.sol:ERC20PermitMock \
        --constructor-args  "CDK Gas Token" "CDK" "{{.zkevm_l2_admin_address}}" "1000000000000000000000000"
}

deploy_zkevm_contracts() {
    echo_ts "Deploying the zkevm contracts..."

    echo_ts "Step 0: Preparing tesnet"
    npx hardhat run deployment/testnet/prepareTestnet.ts --network localhost 2>&1 | tee 01_prepare_testnet.out

    echo_ts "Step 1: Creating genesis"
    MNEMONIC="{{.l1_preallocated_mnemonic}}" npx ts-node deployment/v2/1_createGenesis.ts 2>&1 | tee 02_create_genesis.out
    if [[ ! -e deployment/v2/genesis.json ]]; then
        echo_ts "The genesis file was not created after running createGenesis."
        exit 1
    fi

    echo_ts "Step 2: Deploying PolygonZKEVMDeployer"
    npx hardhat run deployment/v2/2_deployPolygonZKEVMDeployer.ts --network localhost 2>&1 | tee 03_zkevm_deployer.out

    echo_ts "Step 3: Deploying contracts"
    npx hardhat run deployment/v2/3_deployContracts.ts --network localhost 2>&1 | tee 04_deploy_contracts.out
    if [[ ! -e deployment/v2/deploy_output.json ]]; then
        echo_ts "The deploy_output.json file was not created after running deployContracts."
        exit 1
    fi
}

deploy_rollup_contract() {
    echo_ts "Step 4: Creating Rollup/Validium"
    npx hardhat run deployment/v2/4_createRollup.ts --network localhost 2>&1 | tee 05_create_rollup.out
    if [[ ! -e deployment/v2/create_rollup_output.json ]]; then
        echo_ts "The create_rollup_output.json file was not created after running createRollup."
        exit 1
    fi
}

# --------------------------------------------------------------------------------------------------
#   __  __    _    ___ _   _ 
#  |  \/  |  / \  |_ _| \ | |
#  | |\/| | / _ \  | ||  \| |
#  | |  | |/ ___ \ | || |\  |
#  |_|  |_/_/   \_\___|_| \_|
#
# --------------------------------------------------------------------------------------------------

global_log_level="{{.global_log_level}}"
if [[ $global_log_level == "debug" ]]; then
    set -x
fi

if [[ -e "/opt/zkevm/.init-complete{{.deployment_suffix}}.lock" ]]; then
    echo_ts "Skipping. This script has already been executed."
    exit 0
fi

# If we had a genesis, and combined that were created outside of
# kurtosis entirely, we'll use those and exit. This is like a
# permissionless use case
if [[ -e "/opt/contract-deploy/genesis.json" && -e "/opt/contract-deploy/combined.json" ]]; then
    echo_ts "Skipping. We have a genesis and combined output file from a previous deployment."
    cp /opt/contract-deploy/* /opt/zkevm/
    exit 0
fi

echo_ts "Waiting for the L1 RPC to be available..."
wait_for_rpc_to_be_available "{{.l1_rpc_url}}"
echo_ts "The L1 RPC is now available!"

# --------------------------------------------------------------------------------------------------
#    ____ ___  _   _ _____ ____      _    ____ _____   ____  _____ ____  _     _____   ____  __ _____ _   _ _____ 
#   / ___/ _ \| \ | |_   _|  _ \    / \  / ___|_   _| |  _ \| ____|  _ \| |   / _ \ \ / /  \/  | ____| \ | |_   _|
#  | |  | | | |  \| | | | | |_) |  / _ \| |     | |   | | | |  _| | |_) | |  | | | \ V /| |\/| |  _| |  \| | | |  
#  | |__| |_| | |\  | | | |  _ <  / ___ \ |___  | |   | |_| | |___|  __/| |__| |_| || | | |  | | |___| |\  | | |  
#   \____\___/|_| \_| |_| |_| \_\/_/   \_\____| |_|   |____/|_____|_|   |_____\___/ |_| |_|  |_|_____|_| \_| |_|  
#
# --------------------------------------------------------------------------------------------------
echo_ts "Funding important accounts on l1"
fund_account_on_l1 "admin" "{{.zkevm_l2_admin_address}}"
fund_account_on_l1 "sequencer" "{{.zkevm_l2_sequencer_address}}"
fund_account_on_l1 "aggregator" "{{.zkevm_l2_aggregator_address}}"
fund_account_on_l1 "agglayer" "{{.zkevm_l2_agglayer_address}}"
fund_account_on_l1 "l1testing" "{{.zkevm_l2_l1testing_address}}"

echo_ts "Funding important addresses on L1..."
fund_address_on_l1 "admin" "{{.zkevm_l2_admin_address}}"
fund_address_on_l1 "sequencer" "{{.zkevm_l2_sequencer_address}}"
fund_address_on_l1 "aggregator" "{{.zkevm_l2_aggregator_address}}"
fund_address_on_l1 "agglayer" "{{.zkevm_l2_agglayer_address}}"
fund_address_on_l1 "l1testing" "{{.l1_deposit_account}}"
echo_ts "Addresses funded!"

echo_ts "Setting up local zkevm-contracts repository for deployment..."
pushd /opt/zkevm-contracts || exit 1
cp /opt/contract-deploy/deploy_parameters.json /opt/zkevm-contracts/deployment/v2/deploy_parameters.json
cp /opt/contract-deploy/create_rollup_parameters.json /opt/zkevm-contracts/deployment/v2/create_rollup_parameters.json
sed -i 's#http://127.0.0.1:8545#{{.l1_rpc_url}}#' hardhat.config.ts
# Setup a foundry project in case we do a gas token or dac deployment.
printf "[profile.default]\nsrc = 'contracts'\nout = 'out'\nlibs = ['node_modules']\n" > foundry.toml

# Deploy the gas token.
# TODO: This should be configurable. We should be able to specify a token address that has already been deployed.
# {{if .zkevm_use_gas_token_contract}}
deploy_gas_token_contract > gasToken-erc20.json
jq --slurpfile c gasToken-erc20.json '.gasTokenAddress = $c[0].deployedTo' /opt/contract-deploy/create_rollup_parameters.json > /opt/zkevm-contracts/deployment/v2/create_rollup_parameters.json
# {{end}}

# Deploy the zkevm contracts.
is_first_rollup=0 # An indicator if this deployment is doing the first setup of the agglayer.
if [[ ! -e /opt/zkevm/combined.json ]]; then
    deploy_zkevm_contracts
    is_first_rollup=1
else
    echo_ts "Skipping the deployment of the zkevm-contracts."
    cp /opt/zkevm/genesis.json /opt/zkevm-contracts/deployment/v2/
    cp /opt/zkevm/deploy_output.json /opt/zkevm-contracts/deployment/v2/
fi
deploy_rollup_contract

# --------------------------------------------------------------------------------------------------
#    ____ ___  _   _ _____ ___ ____    ____ _____ _   _ _____ ____      _  _____ ___ ___  _   _ 
#   / ___/ _ \| \ | |  ___|_ _/ ___|  / ___| ____| \ | | ____|  _ \    / \|_   _|_ _/ _ \| \ | |
#  | |  | | | |  \| | |_   | | |  _  | |  _|  _| |  \| |  _| | |_) |  / _ \ | |  | | | | |  \| |
#  | |__| |_| | |\  |  _|  | | |_| | | |_| | |___| |\  | |___|  _ <  / ___ \| |  | | |_| | |\  |
#   \____\___/|_| \_|_|   |___\____|  \____|_____|_| \_|_____|_| \_\/_/   \_\_| |___\___/|_| \_|
#
# --------------------------------------------------------------------------------------------------

# Combine contract deploy files.
# At this point, all of the contracts /should/ have been deployed.
# Now we can combine all of the files and put them into the general zkevm folder.
echo_ts "Combining contract deploy files"
mkdir -p /opt/zkevm
cp /opt/zkevm-contracts/deployment/v2/genesis.json /opt/zkevm/
cp /opt/zkevm-contracts/deployment/v2/create_rollup_{output,parameters}.json /opt/zkevm/
cp /opt/zkevm-contracts/deployment/v2/deploy_{output,parameters}.json /opt/zkevm/
popd || exit 1

echo_ts "Creating combined.json"
pushd /opt/zkevm/ || exit 1

cp genesis.json genesis.original.json
jq --slurpfile rollup create_rollup_output.json '. + $rollup[0]' deploy_output.json > combined.json
jq '.polygonZkEVML2BridgeAddress = .polygonZkEVMBridgeAddress' combined.json > c.json; mv c.json combined.json

# Add the L2 GER Proxy address in combined.json (for panoptichain).
zkevm_global_exit_root_l2_address=$(jq -r '.genesis[] | select(.contractName == "PolygonZkEVMGlobalExitRootL2 proxy") | .address' /opt/zkevm/genesis.json)
jq --arg a "$zkevm_global_exit_root_l2_address" '.polygonZkEVMGlobalExitRootL2Address = $a' combined.json > c.json; mv c.json combined.json

# There are a bunch of fields that need to be renamed in order for the
# older fork7 code to be compatible with some of the fork8
# automations. This schema matching can be dropped once this is
# versioned up to 8
# DEPRECATED we will likely remove support for anything before fork 9 soon
fork_id="{{.zkevm_rollup_fork_id}}"
if [[ fork_id -lt 8 ]]; then
    jq '.polygonRollupManagerAddress = .polygonRollupManager' combined.json > c.json; mv c.json combined.json
    jq '.deploymentRollupManagerBlockNumber = .deploymentBlockNumber' combined.json > c.json; mv c.json combined.json
    jq '.upgradeToULxLyBlockNumber = .deploymentBlockNumber' combined.json > c.json; mv c.json combined.json
    jq '.polygonDataCommitteeAddress = .polygonDataCommittee' combined.json > c.json; mv c.json combined.json
    jq '.createRollupBlockNumber = .createRollupBlock' combined.json > c.json; mv c.json combined.json
fi

# NOTE there is a disconnect in the necessary configurations here between the validium node and the zkevm node
jq --slurpfile c combined.json '.rollupCreationBlockNumber = $c[0].createRollupBlockNumber' genesis.json > g.json; mv g.json genesis.json
jq --slurpfile c combined.json '.rollupManagerCreationBlockNumber = $c[0].upgradeToULxLyBlockNumber' genesis.json > g.json; mv g.json genesis.json
jq --slurpfile c combined.json '.genesisBlockNumber = $c[0].createRollupBlockNumber' genesis.json > g.json; mv g.json genesis.json
jq --slurpfile c combined.json '.L1Config = {chainId:{{.l1_chain_id}}}' genesis.json > g.json; mv g.json genesis.json
jq --slurpfile c combined.json '.L1Config.polygonZkEVMGlobalExitRootAddress = $c[0].polygonZkEVMGlobalExitRootAddress' genesis.json > g.json; mv g.json genesis.json
jq --slurpfile c combined.json '.L1Config.polygonRollupManagerAddress = $c[0].polygonRollupManagerAddress' genesis.json > g.json; mv g.json genesis.json
jq --slurpfile c combined.json '.L1Config.polTokenAddress = $c[0].polTokenAddress' genesis.json > g.json; mv g.json genesis.json
jq --slurpfile c combined.json '.L1Config.polygonZkEVMAddress = $c[0].rollupAddress' genesis.json > g.json; mv g.json genesis.json
jq --slurpfile c combined.json '.bridgeGenBlockNumber = $c[0].createRollupBlockNumber' combined.json > c.json; mv c.json combined.json

echo_ts "Final combined.json is ready:"
cp combined.json "combined{{.deployment_suffix}}.json"
jq . combined.json

# --------------------------------------------------------------------------------------------------
#    ____ ___  _   _ _____ ____      _    ____ _____    ____ ___  _   _ _____ ___ ____ _   _ ____      _  _____ ___ ___  _   _ 
#   / ___/ _ \| \ | |_   _|  _ \    / \  / ___|_   _|  / ___/ _ \| \ | |  ___|_ _/ ___| | | |  _ \    / \|_   _|_ _/ _ \| \ | |
#  | |  | | | |  \| | | | | |_) |  / _ \| |     | |   | |  | | | |  \| | |_   | | |  _| | | | |_) |  / _ \ | |  | | | | |  \| |
#  | |__| |_| | |\  | | | |  _ <  / ___ \ |___  | |   | |__| |_| | |\  |  _|  | | |_| | |_| |  _ <  / ___ \| |  | | |_| | |\  |
#   \____\___/|_| \_| |_| |_| \_\/_/   \_\____| |_|    \____\___/|_| \_|_|   |___\____|\___/|_| \_\/_/   \_\_| |___\___/|_| \_|
#
# --------------------------------------------------------------------------------------------------

if [[ $is_first_rollup -eq 1 ]]; then
    # Grant the aggregator role to the agglayer so that it can also verify batches.
    # cast keccak "TRUSTED_AGGREGATOR_ROLE"
    echo_ts "Granting the aggregator role to the agglayer so that it can also verify batches"
    cast send \
         --private-key "{{.zkevm_l2_admin_private_key}}" \
         --rpc-url "{{.l1_rpc_url}}" \
         "$(jq -r '.polygonRollupManagerAddress' combined.json)" \
         'grantRole(bytes32,address)' \
         "0x084e94f375e9d647f87f5b2ceffba1e062c70f6009fdbcf80291e803b5c9edd4" "{{.zkevm_l2_agglayer_address}}"
fi

# The sequencer needs to pay POL when it sequences batches.
# This gets refunded when the batches are verified on L1.
# In order for this to work t,he rollup address must be approved to transfer the sequencers' POL tokens.
echo_ts "Minting POL token on L1 for the sequencer"
cast send \
    --private-key "{{.zkevm_l2_sequencer_private_key}}" \
    --legacy \
    --rpc-url "{{.l1_rpc_url}}" \
    "$(jq -r '.polTokenAddress' combined.json)" \
    'mint(address,uint256)' \
    "{{.zkevm_l2_sequencer_address}}" 1000000000000000000000000000

echo_ts "Approving the rollup address to transfer POL tokens on behalf of the sequencer"
cast send \
    --private-key "{{.zkevm_l2_sequencer_private_key}}" \
    --legacy \
    --rpc-url "{{.l1_rpc_url}}" \
    "$(jq -r '.polTokenAddress' combined.json)" \
    'approve(address,uint256)(bool)' \
    "$(jq -r '.rollupAddress' combined.json)" 1000000000000000000000000000

# {{if .is_cdk_validium}}
# The DAC needs to be configured with a required number of signatures.
# Right now the number of DAC nodes is not configurable.
# If we add more nodes, we'll need to make sure the urls and keys are sorted.
echo_ts "Setting the data availability committee"
cast send \
    --private-key "{{.zkevm_l2_admin_private_key}}" \
    --rpc-url "{{.l1_rpc_url}}" \
    "$(jq -r '.polygonDataCommitteeAddress' combined.json)" \
    'function setupCommittee(uint256 _requiredAmountOfSignatures, string[] urls, bytes addrsBytes) returns()' \
    1 ["http://zkevm-dac{{.deployment_suffix}}:{{.zkevm_dac_port}}"] "{{.zkevm_l2_dac_address}}"

# The DAC needs to be enabled with a call to set the DA protocol.
echo_ts "Setting the data availability protocol"
cast send \
    --private-key "{{.zkevm_l2_admin_private_key}}" \
    --rpc-url "{{.l1_rpc_url}}" \
    "$(jq -r '.rollupAddress' combined.json)" \
    'setDataAvailabilityProtocol(address)' \
    "$(jq -r '.polygonDataCommitteeAddress' combined.json)"
# {{end}}

# If we've configured the l1 network with the minimal preset, we should probably wait for the first
# finalized block. This isn't strictly specific to minimal preset, but if we don't have "minimal"
# configured, it's going to take like 25 minutes for the first finalized block.
l1_preset="{{.l1_preset}}"
if [[ $l1_preset == "minimal" ]]; then
    wait_for_finalized_block
fi

# The contract setup is done!
touch "/opt/zkevm/.init-complete{{.deployment_suffix}}.lock"
