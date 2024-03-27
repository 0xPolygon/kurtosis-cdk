#!/bin/bash
#
# This script is responsible for deploying the contracts for zkEVM/CDK
# and also creating the various configuration files needed for all
# components
export MNEMONIC="{{.l1_preallocated_mnemonic}}"

# ideally this script should stop with an error if a command fails
# https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html#index-set
set -e

# We want to avoid running this script twice. In the future it might
# make more sense to exit with an error code.
if [[ -e "/opt/zkevm/.init-complete.lock" ]]; then
    2>&1 echo "This script has already been executed"
    exit
fi

2>&1 echo "Installing dependencies"
apt update
apt-get -y install jq yq
curl -s -L https://foundry.paradigm.xyz | bash
# shellcheck disable=SC1091
source /root/.bashrc
foundryup &> /dev/null

# Detect the CPU architecture and get the right version of polycli
cpu_arch="{{.cpu_arch}}"
if [[ "$cpu_arch" == "aarch64" ]]; then
    cpu_arch="arm64"
elif [[ "$cpu_arch" == "x86_64" ]]; then
    cpu_arch="amd64"
fi
pushd /opt || exit 1
wget "https://github.com/maticnetwork/polygon-cli/releases/download/{{.polycli_version}}/polycli_{{.polycli_version}}_linux_$cpu_arch.tar.gz"
tar xzf "polycli_{{.polycli_version}}_linux_$cpu_arch.tar.gz"
cp "polycli_{{.polycli_version}}_linux_$cpu_arch" /usr/local/bin/polycli
polycli version
popd

2>&1 echo "Funding important accounts on l1"

# FIXME this look might never finish.. Add a counter
until cast send --rpc-url "{{.l1_rpc_url}}" --mnemonic "{{.l1_preallocated_mnemonic}}" --value 0 "{{.zkevm_l2_sequencer_address}}"; do
     2>&1 echo "l1 rpc might nto be ready"
     sleep 5
done

# In the overall CDK setup, these 4 addresses need to be funded with ETH: sequencer, admin, agglayer, and potentially the aggregator
funding_amount="100ether"
cast send --rpc-url "{{.l1_rpc_url}}" --mnemonic "{{.l1_preallocated_mnemonic}}" --value "$funding_amount" "{{.zkevm_l2_sequencer_address}}"
cast send --rpc-url "{{.l1_rpc_url}}" --mnemonic "{{.l1_preallocated_mnemonic}}" --value "$funding_amount" "{{.zkevm_l2_aggregator_address}}"
cast send --rpc-url "{{.l1_rpc_url}}" --mnemonic "{{.l1_preallocated_mnemonic}}" --value "$funding_amount" "{{.zkevm_l2_admin_address}}"
cast send --rpc-url "{{.l1_rpc_url}}" --mnemonic "{{.l1_preallocated_mnemonic}}" --value "$funding_amount" "{{.zkevm_l2_agglayer_address}}"

cp /opt/contract-deploy/deploy_parameters.json /opt/zkevm-contracts/deployment/v2/deploy_parameters.json
cp /opt/contract-deploy/create_rollup_parameters.json /opt/zkevm-contracts/deployment/v2/create_rollup_parameters.json

pushd /opt/zkevm-contracts || exit 1
2>&1 echo "Compiling contracts"

# We're going to replace the localhost RPC with the url of our L1
sed -i 's#http://127.0.0.1:8545#{{.l1_rpc_url}}#' hardhat.config.ts

npm i
npx hardhat compile

# shellcheck disable=SC1054,SC1083
{{if .zkevm_use_gas_token_contract}}
2>&1 echo "Deploying Gas Token"
printf "[profile.default]\nsrc = 'contracts'\nout = 'out'\nlibs = ['node_modules']\n" > foundry.toml
forge build
forge create --json \
      --rpc-url "{{.l1_rpc_url}}" \
      --mnemonic "{{.l1_preallocated_mnemonic}}" \
      contracts/mocks/ERC20PermitMock.sol:ERC20PermitMock \
      --constructor-args  "CDK Gas Token" "CDK" "{{.zkevm_l2_admin_address}}" "1000000000000000000000000" > gasToken-erc20.json

# In this case, we'll configure the create rollup parameters to have a gas token
jq --slurpfile c gasToken-erc20.json '.gasTokenAddress = $c[0].deployedTo' /opt/contract-deploy/create_rollup_parameters.json > /opt/zkevm-contracts/deployment/v2/create_rollup_parameters.json
# shellcheck disable=SC1056,SC1072,SC1073,SC1009
{{end}}

2>&1 echo "Running full l1 contract deployment process"
npx hardhat run deployment/testnet/prepareTestnet.ts --network localhost &> 01_prepare_testnet.out
npx ts-node deployment/v2/1_createGenesis.ts &> 02_create_genesis.out
npx hardhat run deployment/v2/2_deployPolygonZKEVMDeployer.ts --network localhost &> 03_zkevm_deployer.out
npx hardhat run deployment/v2/3_deployContracts.ts --network localhost &> 04_deploy_contracts.out
npx hardhat run deployment/v2/4_createRollup.ts --network localhost &> 05_create_rollup.out

# at this point, all of the contracts /should/ have been deployed. Now
# we can combine all of the files and put them into the general zkevm folder
mkdir -p /opt/zkevm
cp /opt/zkevm-contracts/deployment/v2/deploy_*.json /opt/zkevm/
cp /opt/zkevm-contracts/deployment/v2/genesis.json /opt/zkevm/
cp /opt/zkevm-contracts/deployment/v2/create_rollup_output.json /opt/zkevm/
cp /opt/zkevm-contracts/deployment/v2/create_rollup_parameters.json /opt/zkevm/
popd

pushd /opt/zkevm/ || exit 1

2>&1 echo "Preping deploy outputs"
cp genesis.json genesis.original.json

jq --slurpfile rollup create_rollup_output.json '. + $rollup[0]' deploy_output.json > combined.json

# There are a bunch of fields that need to be renamed in order for the
# older fork7 code to be compatibile with some of the fork8
# automations. This schema matching can be dropped once this is
# versioned up to 8
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

# The sequencer needs to pay POL when it sequences batches. This gets
# refunded when the batches are proved. In order for this to work the
# rollup address must be approved transfer the sequencers POL
cast send --private-key "{{.zkevm_l2_sequencer_private_key}}" --legacy --rpc-url "{{.l1_rpc_url}}" "$(jq -r '.polTokenAddress' combined.json)" 'approve(address,uint256)(bool)' "$(jq -r '.rollupAddress' combined.json)" 1000000000000000000000000000

# The DAC needs to be configured with a required number of
# signatures. Right now the number of DAC nodes is not
# configurable. If we add more nodes, we'll need to make sure the urls
# and keys are sorted.
cast send --private-key "{{.zkevm_l2_admin_private_key}}" --rpc-url "{{.l1_rpc_url}}" "$(jq -r '.polygonDataCommitteeAddress' combined.json)" \
        'function setupCommittee(uint256 _requiredAmountOfSignatures, string[] urls, bytes addrsBytes) returns()' \
        1 ["http://zkevm-dac{{.deployment_suffix}}:{{.zkevm_dac_port}}"] "{{.zkevm_l2_dac_address}}"

# The DAC needs to be enabled with a call to set the DA protocol
cast send --private-key "{{.zkevm_l2_admin_private_key}}" --rpc-url "{{.l1_rpc_url}}" "$(jq -r '.rollupAddress' combined.json)" 'setDataAvailabilityProtocol(address)' "$(jq -r '.polygonDataCommitteeAddress' combined.json)"

# Grant the aggregator role to the agglayer so that it can also verify batches
# cast keccak "TRUSTED_AGGREGATOR_ROLE"
cast send --private-key "{{.zkevm_l2_admin_private_key}}" --rpc-url "{{.l1_rpc_url}}" "$(jq -r '.polygonRollupManagerAddress' combined.json)" 'grantRole(bytes32,address)' "0x084e94f375e9d647f87f5b2ceffba1e062c70f6009fdbcf80291e803b5c9edd4" "{{.zkevm_l2_agglayer_address}}"

# The parseethwallet command is creating a go-ethereum style encrypted
# keystore to be used with the zkevm / cdk-validium node
polycli parseethwallet --hexkey "{{.zkevm_l2_sequencer_private_key}}" --password "{{.zkevm_l2_keystore_password}}" --keystore tmp.keys
mv tmp.keys/UTC* sequencer.keystore
chmod a+r sequencer.keystore
rm -rf tmp.keys

polycli parseethwallet --hexkey "{{.zkevm_l2_aggregator_private_key}}" --password "{{.zkevm_l2_keystore_password}}" --keystore tmp.keys
mv tmp.keys/UTC* aggregator.keystore
chmod a+r aggregator.keystore
rm -rf tmp.keys

polycli parseethwallet --hexkey "{{.zkevm_l2_claimtxmanager_private_key}}" --password "{{.zkevm_l2_keystore_password}}" --keystore tmp.keys
mv tmp.keys/UTC* claimtxmanager.keystore
chmod a+r claimtxmanager.keystore
rm -rf tmp.keys

polycli parseethwallet --hexkey "{{.zkevm_l2_agglayer_private_key}}" --password "{{.zkevm_l2_keystore_password}}" --keystore tmp.keys
mv tmp.keys/UTC* agglayer.keystore
chmod a+r agglayer.keystore
rm -rf tmp.keys

polycli parseethwallet --hexkey "{{.zkevm_l2_dac_private_key}}" --password "{{.zkevm_l2_keystore_password}}" --keystore tmp.keys
mv tmp.keys/UTC* dac.keystore
chmod a+r dac.keystore
rm -rf tmp.keys

touch .init-complete.lock
popd
