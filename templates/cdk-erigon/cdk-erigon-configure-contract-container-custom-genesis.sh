#!/bin/bash

# deploymentRollupManagerBlockNumber field inside cdk-erigon-custom-genesis-addresses.json must be different to 0 becuase cdk-erigon and cdk-node requires this value (zkevm.l1-first-block) to be different to 0
cp /opt/contract-deploy/cdk-erigon-custom-genesis-addresses.json /opt/zkevm/combined.json

cp /opt/zkevm/combined.json /opt/zkevm-contracts/deployment/v2/deploy_output.json
cp /opt/zkevm/combined.json /opt/zkevm/deploy_output.json

global_exit_root_address=$(jq -r '.polygonZkEVMGlobalExitRootAddress' /opt/zkevm/combined.json)
cast send "$global_exit_root_address" "initialize()" --private-key "{{.zkevm_l2_admin_private_key}}" --rpc-url "{{.l1_rpc_url}}"
