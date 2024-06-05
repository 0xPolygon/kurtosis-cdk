#!/bin/bash
set -e

## L1 Configuration
# The L1 chain id.
yq -Y --in-place '.args.l1_chain_id = "2442"' params.yml
# The L1 RPC endpoint
yq -Y --in-place '.args.l1_rpc_url = "<l1-rpc-url>"' params.yml

## L2 Configuration
# The RPC endpoint of the sequencer on L2.
yq -Y --in-place '.args.zkevm_rpc_url = "https://rpc.cardona.zkevm-rpc.com"' params.yml
# The endpoint of the datastreamer on L2.
yq -Y --in-place '.args.zkevm_datastreamer_url = "datastream.cardona.zkevm-rpc.com:6900"' params.yml
# The L2 chain id.
yq -Y --in-place '.args.zkevm_rollup_chain_id = "10101"' params.yml

## Contracts
# The address of the Sequencer EOA.
yq -Y --in-place '.args.zkevm_l2_sequencer_address = "0x761d53b47334bEe6612c0Bd1467FB881435375B2"' params.yml
# The address of the Admin EOA (contract deployer).
yq -Y --in-place '.args.zkevm_l2_admin_address = "0xff6250d0E86A2465B0C1bF8e36409503d6a26963"' params.yml
# The address of the Rollup contract.
yq -Y --in-place '.args.zkevm_rollup_address = "0xA13Ddb14437A8F34897131367ad3ca78416d6bCa"' params.yml
# The address of the Polygon Rollup Manager contract.
yq -Y --in-place '.args.zkevm_rollup_manager_address = "0x2F50ef6b8e8Ee4E579B17619A92dE3E2ffbD8AD2"' params.yml
# The address of the Global Exit Root Manager contract.
yq -Y --in-place '.args.zkevm_global_exit_root_address = "0xAd1490c248c5d3CbAE399Fd529b79B42984277DF"' params.yml
# The address of the Matic contract.
yq -Y --in-place '.args.pol_token_address = "0x1850Dd35dE878238fb1dBa7aF7f929303AB6e8E4"' params.yml
# The first block to start syncing from on the L1
yq -Y --in-place '.args.genesis_block_number = "4789190"' params.yml

## Node Configuration
# The configuration files to run cdk-erigon as an RPC.
yq -Y --in-place '.args.cdk_erigon_rpc_chain_config_file = "data/cdk-erigon-rpc-cardona/dynamic-cardona-conf.json"' params.yml
yq -Y --in-place '.args.cdk_erigon_rpc_chain_allocs_file = "data/cdk-erigon-rpc-cardona/dynamic-cardona-allocs.json"' params.yml
