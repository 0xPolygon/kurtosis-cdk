#!/bin/bash
export MNEMONIC="{{.l1_preallocated_mnemonic}}"

# die if anything fails in here
set -e

if [[ -e "/opt/zkevm/.init-complete.lock" ]]; then
    2>&1 echo "This script has already been executed"
    exit
fi

2>&1 echo "Installing dependencies"
apt update
apt-get -y install socat jq yq
curl -s -L https://foundry.paradigm.xyz | bash
source /root/.bashrc
foundryup &> /dev/null

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
until cast send --rpc-url {{.l1_rpc_url}} --mnemonic "{{.l1_preallocated_mnemonic}}" --value 0 {{.zkevm_l2_sequencer_address}}; do
     2>&1 echo "l1 rpc might nto be ready"
     sleep 5
done

cast send --rpc-url {{.l1_rpc_url}} --mnemonic "{{.l1_preallocated_mnemonic}}" --value 100ether {{.zkevm_l2_sequencer_address}}
cast send --rpc-url {{.l1_rpc_url}} --mnemonic "{{.l1_preallocated_mnemonic}}" --value 100ether {{.zkevm_l2_aggregator_address}}
cast send --rpc-url {{.l1_rpc_url}} --mnemonic "{{.l1_preallocated_mnemonic}}" --value 100ether {{.zkevm_l2_admin_address}}


cp /opt/contract-deploy/deploy_parameters.json /opt/zkevm-contracts/deployment/v2/deploy_parameters.json
cp /opt/contract-deploy/create_rollup_parameters.json /opt/zkevm-contracts/deployment/v2/create_rollup_parameters.json

pushd /opt/zkevm-contracts || exit 1
2>&1 echo "Compiling contracts"

sed -i 's#http://127.0.0.1:8545#{{.l1_rpc_url}}#' hardhat.config.ts

set -x
# https://github.com/nodejs/docker-node/issues/1668
npm ci || npm ci --no-audit --maxsockets 1
npx hardhat compile
set +x

2>&1 echo "Running full l1 contract deployment process"
npx hardhat run deployment/testnet/prepareTestnet.ts --network localhost &> 01_prepare_testnet.out
npx ts-node deployment/v2/1_createGenesis.ts &> 02_create_genesis.out
npx hardhat run deployment/v2/2_deployPolygonZKEVMDeployer.ts --network localhost &> 03_zkevm_deployer.out
npx hardhat run deployment/v2/3_deployContracts.ts --network localhost &> 04_deploy_contracts.out
npx hardhat run deployment/v2/4_createRollup.ts --network localhost &> 05_create_rollup.out

mkdir -p /opt/zkevm
cp /opt/zkevm-contracts/deployment/v2/deploy_*.json /opt/zkevm/
cp /opt/zkevm-contracts/deployment/v2/genesis.json /opt/zkevm/
cp /opt/zkevm-contracts/deployment/v2/create_rollup_output.json /opt/zkevm/
cp /opt/contract-deploy/node-config.toml /opt/zkevm/
cp /opt/contract-deploy/bridge-config.toml /opt/zkevm/
cp /opt/contract-deploy/prover-config.json /opt/zkevm/
popd

pushd /opt/zkevm/ || exit 1

2>&1 echo "Preping deploy outputs"
cp genesis.json genesis.original.json

jq --slurpfile rollup create_rollup_output.json '. + $rollup[0]' deploy_output.json > combined.json

# NOTE there is a disconnect in the necessary configurations here between the validium node and the zkevm node
jq --slurpfile c combined.json '.rollupCreationBlockNumber = $c[0].createRollupBlockNumber' genesis.json > g.json; mv g.json genesis.json
jq --slurpfile c combined.json '.rollupManagerCreationBlockNumber = $c[0].upgradeToULxLyBlockNumber' genesis.json > g.json; mv g.json genesis.json
jq --slurpfile c combined.json '.genesisBlockNumber = $c[0].createRollupBlockNumber' genesis.json > g.json; mv g.json genesis.json
jq --slurpfile c combined.json '.L1Config = {chainId:{{.l1_network_id}}}' genesis.json > g.json; mv g.json genesis.json
jq --slurpfile c combined.json '.L1Config.polygonZkEVMGlobalExitRootAddress = $c[0].polygonZkEVMGlobalExitRootAddress' genesis.json > g.json; mv g.json genesis.json
jq --slurpfile c combined.json '.L1Config.polygonRollupManagerAddress = $c[0].polygonRollupManagerAddress' genesis.json > g.json; mv g.json genesis.json
jq --slurpfile c combined.json '.L1Config.polTokenAddress = $c[0].polTokenAddress' genesis.json > g.json; mv g.json genesis.json
jq --slurpfile c combined.json '.L1Config.polygonZkEVMAddress = $c[0].rollupAddress' genesis.json > g.json; mv g.json genesis.json

# note this particular setting is different for the bridge service!!
tomlq --slurpfile c combined.json -t '.NetworkConfig.GenBlockNumber = $c[0].deploymentRollupManagerBlockNumber' bridge-config.toml > b.json; mv b.json bridge-config.toml
tomlq --slurpfile c combined.json -t '.NetworkConfig.PolygonBridgeAddress = $c[0].polygonZkEVMBridgeAddress' bridge-config.toml > b.json; mv b.json bridge-config.toml
tomlq --slurpfile c combined.json -t '.NetworkConfig.PolygonZkEVMGlobalExitRootAddress = $c[0].polygonZkEVMGlobalExitRootAddress' bridge-config.toml > b.json; mv b.json bridge-config.toml
tomlq --slurpfile c combined.json -t '.NetworkConfig.PolygonRollupManagerAddress = $c[0].polygonRollupManagerAddress' bridge-config.toml > b.json; mv b.json bridge-config.toml
tomlq --slurpfile c combined.json -t '.NetworkConfig.PolygonZkEVMAddress = $c[0].rollupAddress' bridge-config.toml > b.json; mv b.json bridge-config.toml
tomlq --slurpfile c combined.json -t '.NetworkConfig.L2PolygonBridgeAddresses = [$c[0].polygonZkEVMBridgeAddress]' bridge-config.toml > b.json; mv b.json bridge-config.toml

cast send --private-key {{.zkevm_l2_sequencer_private_key}} --legacy --rpc-url {{.l1_rpc_url}} "$(jq -r '.polTokenAddress' combined.json)" 'approve(address,uint256)(bool)' "$(jq -r '.rollupAddress' combined.json)"  1000000000000000000000000000 &> approval.out

polycli parseethwallet --hexkey {{.zkevm_l2_sequencer_private_key}} --password {{.zkevm_l2_keystore_password}} --keystore tmp.keys
mv tmp.keys/UTC* sequencer.keystore
rm -rf tmp.keys

polycli parseethwallet --hexkey {{.zkevm_l2_aggregator_private_key}} --password {{.zkevm_l2_keystore_password}} --keystore tmp.keys
mv tmp.keys/UTC* aggregator.keystore
rm -rf tmp.keys

polycli parseethwallet --hexkey {{.zkevm_l2_claimtxmanager_private_key}} --password {{.zkevm_l2_keystore_password}} --keystore tmp.keys
mv tmp.keys/UTC* claimtxmanager.keystore
rm -rf tmp.keys

touch .init-complete.lock
popd
