#!/bin/bash

sed -i 's#http://127.0.0.1:8545#{{.l1_rpc_url}}#' /opt/zkevm-contracts/hardhat.config.ts
cp /opt/contract-deploy/deploy_parameters.json /opt/zkevm-contracts/deployment/v2/deploy_parameters.json

pushd /opt/zkevm-contracts || exit 1
MNEMONIC="{{.l1_preallocated_mnemonic}}" npx ts-node deployment/v2/1_createGenesis.ts 2>&1 | tee 02_create_genesis.out
popd || exit 1

cp /opt/zkevm-contracts/deployment/v2/genesis.json /opt/zkevm/
cp /opt/contract-deploy/create_rollup_parameters.json /opt/zkevm/
cp /opt/zkevm/combined.json /opt/zkevm/combined-001.json

cast send 0x2F50ef6b8e8Ee4E579B17619A92dE3E2ffbD8AD2 "initialize()" --private-key "{{.zkevm_l2_admin_private_key}}" --rpc-url "{{.l1_rpc_url}}"
