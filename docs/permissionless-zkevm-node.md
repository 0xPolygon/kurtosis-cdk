# How to set up a permissionless zkevm node?

We'll show you how to set up a permissionless zkevm node against Cardona / Sepolia testnet. Note that you can set up such node against any other network, including kurtosis-cdk networks.

Let's create a `params.yml` file with the following content.

```yml
# Set all the deployment stages to false.
# We'll deploy the permissionless zkevm node using the additional_services flag.
deployment_stages:
  deploy_l1: false
  deploy_zkevm_contracts_on_l1: false
  deploy_databases: false
  deploy_cdk_central_environment: false
  deploy_cdk_bridge_infra: false
  deploy_cdk_bridge_ui: false
  deploy_agglayer: false
  deploy_cdk_erigon_node: false
  deploy_optimism_rollup: false
  deploy_l2_contracts: false

args:
  verbosity: debug
  consensus_contract_type: rollup
  zkevm_prover_image: hermeznetwork/zkevm-prover:v6.0.8
  zkevm_node_image: hermeznetwork/zkevm-node:v0.7.3
  additional_services:
    - pless_zkevm_node
  l1_rpc_url: CHANGE_ME
  genesis_file: ../.github/tests/nightly/pless-zkevm-node/cardona-sepolia-testnet-genesis.json
```

You will need two things:

1) An RPC url - you can use any RPC node provider.
2) The genesis file - you can take a look at `.github/tests/nightly/pless-zkevm-node`.

If you want to run the permissionless zkevm node against a kurtosis-cdk stack, you can retrieve the genesis using the following commands.

```bash
rm -r /tmp/zkevm
kurtosis files download cdk-v1 genesis /tmp
cat /tmp/genesis.json
```

To deploy the permissionless node, you can use the following command.

```bash
kurtosis run --enclave cdk --args-file params.yml .
```
