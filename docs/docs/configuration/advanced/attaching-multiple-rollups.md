---
sidebar_position: 3
---

# Attaching Multiple Rollups in a Single Kurtosis Enclave

## Introduction

By default, our Kurtosis setups only attach a single rollup per enclave. However, many advanced scenarios—such as L2-to-L2 bridging, cross-rollup messaging, or proving mode comparisons—require running multiple rollups within a single enclave.

This guide should walk through the setup and configuration required to launch three distinct rollups in a single Kurtosis enclave, each using different proving and execution logic.

### What's Deployed?

- L1 Ethereum blockchain ([lighthouse/geth](https://github.com/ethpandaops/ethereum-package))
- Agglayer stack ([contracts](https://github.com/agglayer/agglayer-contracts), [agglayer service](https://github.com/agglayer/agglayer), and [mock prover](https://github.com/agglayer/provers))
- L2 Optimism blockchain ([op-geth](https://github.com/ethereum-optimism/op-geth) / [op-node](https://github.com/ethereum-optimism/optimism/tree/develop/op-node)) enhanced with [AggKit](https://github.com/agglayer/aggkit) for seamless Agglayer connectivity
- L2 CDK-Erigon blockchain ([cdk-erigon](https://github.com/0xPolygonHermez/cdk-erigon), [zkevm-pool-manager](https://github.com/0xPolygon/zkevm-pool-manager), [zkevm-prover](https://github.com/0xPolygonHermez/zkevm-prover)and executor, [cdk-node](https://github.com/0xPolygon/cdk)). Three different CDK-Erigon consensus will be used in the guide:
  - Validium
  - Rollup
  - PP

### Use Cases

- Teams needing a more production-like scenario where multiple rollups exist already
- Teams looking to test cross-rollup bridging

### Deployment

By default, the Kurtosis CDK environment spins up an OP Geth environment. This needs to be changed to deploy a CDK Erigon Validium environment first.

To deploy this environment:

First export the `kurtosis_enclave_name` and `kurtosish_hash` values to environment variables.
```bash
kurtosis_enclave_name=cdk
kurtosish_hash=e05e8cdcfee52a106ec6850b8956b77171cdd948 # Kurtosis tag v0.3.4 + v9.0.0-rc.2-pp contracts + CDK-Erigon Validium by default
```

Then create a `.yml` file to use as the `--args-file` input.
```yaml title="initial-cdk-erigon-validium.yml"
args:
  verbosity: debug
  agglayer_image: ghcr.io/agglayer/agglayer:0.2.5
  zkevm_contracts_image: leovct/zkevm-contracts:v9.0.0-rc.6-pp-fork.12
  zkevm_prover_image: hermeznetwork/zkevm-prover:v8.0.0-RC16-fork.12
  additional_services:
    - tx_spammer
  sequencer_type: erigon
  agglayer_prover_sp1_key: '0xcbe64481eedcb08c0d37df9cb0121e91dbac11c0f015fbe2bedb7875c020778d' # Dummy key for mock prover.
```

Run the deployment.
```bash
# Spin up cdk-erigon validium
kurtosis run \
         --enclave "$kurtosis_enclave_name" \
         --args-file ./initial-cdk-erigon-validium.yml \
         "github.com/0xPolygon/kurtosis-cdk@$kurtosis_hash"
```

Repeat the steps for Rollup consensus.
```yaml title="initial-cdk-erigon-rollup.yml"
deployment_stages:
  deploy_l1: false
  deploy_agglayer: false
  deploy_cdk_bridge_ui: false
args:
  verbosity: debug
  zkevm_contracts_image: leovct/zkevm-contracts:v9.0.0-rc.6-pp-fork.12
  zkevm_prover_image: hermeznetwork/zkevm-prover:v8.0.0-RC16-fork.12
  additional_services:
    - tx_spammer
  consensus_contract_type: rollup
  sequencer_type: erigon
  agglayer_prover_sp1_key: '0xcbe64481eedcb08c0d37df9cb0121e91dbac11c0f015fbe2bedb7875c020778d' # Dummy key for mock prover.
  deployment_suffix: '-002'
  zkevm_rollup_chain_id: 20202
  zkevm_rollup_id: 2
  zkevm_l2_sequencer_address: '0x3bd49B59d0d61e83FA5C7856312b9bfEddbCbDA8'
  zkevm_l2_sequencer_private_key: '0xf1b0412da5d68afa81e8301d93c56b125ee764e2fab4e919afb81ae14babc5e3'
  zkevm_l2_aggregator_address: '0x3BAEE05bd44f4Ee84709C7Df6861A3528f4c8286'
  zkevm_l2_aggregator_private_key: '0x8bcbeae7253c993102e8269f2b48639a832095e0a0235b609472b7b9286290b9'
  zkevm_l2_claimtxmanager_address: '0x1a1C53bA714643B53b39D82409915b513349a1ff'
  zkevm_l2_claimtxmanager_private_key: '0xcc8de19498a724ec38c7c774d447a51e629ee947ec360f16913ab3000f5ad676'
  zkevm_l2_timelock_address: '0xb2BCBC707c88f1a41d3DBb982b9A8996cA83Df82'
  zkevm_l2_timelock_private_key: '0xfbfd097f603d5ed2f1bf79a756d021e8c2a1771bb13ea42a36f534ac731739d3'
  zkevm_l2_loadtest_address: '0x51406206342270c822b5d9dfb261279eEdF0Af20'
  zkevm_l2_loadtest_private_key: '0x72e05c95e8c0b0380c1353dbfd50d1d8a762861ac008b8c270963f81abf4304c'
  zkevm_l2_agglayer_address: '0xB8b680902bba8e04C78660D33a97a87E4CC4e797'
  zkevm_l2_agglayer_private_key: '0x6fadecf5f47e84428042d36ecbfb1d05c587d658cb0d66e10151561e74340e81'
  zkevm_l2_dac_address: '0x64a19B5D36664fa68dc8bAC6574A5B272F08ACc1'
  zkevm_l2_dac_private_key: '0x29506f6abfd8ff62b29af422c4a0af1dbc989d7154220da916e565c8cc04ce47'
  zkevm_l2_proofsigner_address: '0xD3F0C080A75f537B361A3Eadf24EE5d6F72a15B3'
  zkevm_l2_proofsigner_private_key: '0x89ac1075d2f7c27ba296fb4d625b0e10f272f8f7fa96320f7f0832a41b18e54b'
  zkevm_l2_l1testing_address: '0xcd9Ac30C72a8757F446F814aFfbc32847c2CD17D'
  zkevm_l2_l1testing_private_key: '0xbdbfded25015702c72558c5a3cea747713734d3535fe832b4cd4f1bb882977ea'
  zkevm_l2_claimsponsor_address: '0xB2c5d585cc8c1f9FC51035941CFdA42DB83E9886'
  zkevm_l2_claimsponsor_private_key: '0x4c545e05d1e85a36d316b92a4de4588c60fe3c5dbb2c235306d1ce4e439b751a'
```

```bash
# Spin up cdk-erigon rollup
kurtosis run \
         --enclave "$kurtosis_enclave_name" \
         --args-file ./initial-cdk-erigon-rollup.yml \
         "github.com/0xPolygon/kurtosis-cdk@$kurtosis_hash"    
```


Repeat the steps for PP consensus.
```yaml title="initial-cdk-erigon-pp.yml"
deployment_stages:
  deploy_l1: false
  deploy_agglayer: false
  deploy_cdk_bridge_ui: false
args:
  deployment_suffix: '-003'
  zkevm_rollup_chain_id: 30303
  zkevm_rollup_id: 3
  verbosity: debug
  zkevm_contracts_image: leovct/zkevm-contracts:v9.0.0-rc.6-pp-fork.12
  zkevm_prover_image: hermeznetwork/zkevm-prover:v8.0.0-RC16-fork.12
  additional_services:
    - tx_spammer
  consensus_contract_type: pessimistic
  erigon_strict_mode: false
  gas_token_enabled: false
  zkevm_use_real_verifier: false
  enable_normalcy: true
  agglayer_prover_sp1_key: '0x58301ea64f48a91e21f900bacf599eb61ec9331455db34f9b4279d5c652f368f'
  agglayer_prover_primary_prover: network-prover
  sequencer_type: erigon
  zkevm_l2_sequencer_address: '0x0d59BC8C02A089D48d9Cd465b74Cb6E23dEB950D'
  zkevm_l2_sequencer_private_key: '0xf6385a27e7710349617340c6f9310e88f0aad10d01646a9bb204177431babcd8'
  zkevm_l2_aggregator_address: '0x2D20D9081fb403E856355F2cddd1C4863D0109cb'
  zkevm_l2_aggregator_private_key: '0x2cb77c2cca48d3fee64c14d73564fd6e90676a4f6da6545681e10c8b9b22fce2'
  zkevm_l2_claimtxmanager_address: '0x1359D1eAf25aADaA04304Ee7EFC5b94C43e0e1D5'
  zkevm_l2_claimtxmanager_private_key: '0xb0244fcbf83d7aaa2d51dc78a55233058af31797a974d25f724de041f3484418'
  zkevm_l2_timelock_address: '0x7803E33388C695E7cbd85eD55f4abe6455E9ce2e'
  zkevm_l2_timelock_private_key: '0xe12e739b58489a2c2f49c472169ba20eb89d039e71f04d5342ab645dc3fb6540'
  zkevm_l2_loadtest_address: '0x5198d92d278Fd36e5745C308F728d256198A0e3d'
  zkevm_l2_loadtest_private_key: '0xcc594c53eca19f9e56200cadf60c94757b0bdee1fc4bc73552ba879d51fd82b3'
  zkevm_l2_agglayer_address: '0x9b5A1f2bC7bb48419d9f6407CFcA454F87884072'
  zkevm_l2_agglayer_private_key: '0x7b1164f53f633e940089031a3c265c308d2bcf4756bc8dcf9046bf00e21ec3b1'
  zkevm_l2_dac_address: '0xA9875E9B9FE3BD46da758ba69a5d4B9dFCA6F133'
  zkevm_l2_dac_private_key: '0x5d1a923f60e2423932f782dab9510e1c2fd64b0f29b0893978864191ecdd6f4f'
  zkevm_l2_proofsigner_address: '0x3AA075513578d86dC63f9344cD9489b948d7686a'
  zkevm_l2_proofsigner_private_key: '0xfd402dcc8c7fc7ce0df59fe12f33da7ac2ed760a619188ff16974fde16f9b00e'
  zkevm_l2_l1testing_address: '0x943413d3b2E1B6aF09a758c35b6F5d23a4d6d262'
  zkevm_l2_l1testing_private_key: '0x27d8ab2d65296d0da072b172ca9ca874583f9930adb6ac3222fd9494ae7c7f0d'
  zkevm_l2_claimsponsor_address: '0xeA06890A8A547aDd71f98A6845542eb3B63C2862'
  zkevm_l2_claimsponsor_private_key: '0xb97112e36cfcde131faa110430eed6593b75406e5d6991d8db3ed0f492a73b6f'
```

```bash
# Spin up cdk-erigon pp
kurtosis run \
         --enclave "$kurtosis_enclave_name" \
         --args-file ./initial-cdk-erigon-pp.yml \
         "github.com/0xPolygon/kurtosis-cdk@$kurtosis_hash"    
```

### Agglayer Config Setup

Identify the agglayer service running within the Kurtosis enclave.
```bash
# Modify agglayer config
agglayer_uuid=$(kurtosis enclave inspect --full-uuids $kurtosis_enclave_name | grep -E "^[0-9a-f]{32}[[:space:]]+agglayer([[:space:]]+|$)" | awk '{print $1}')
agglayer_container_name=agglayer--$agglayer_uuid
```

Modify the agglayer config.
```bash
# Add lines under [full-node-rpcs]
docker exec -it $agglayer_container_name sed -i '/^\[full-node-rpcs\]/a # RPC of the second rollup node\n2 = "http://cdk-erigon-rpc-002:8123"' /etc/zkevm/agglayer-config.toml

# # Add lines under [proof-signers]
docker exec -it $agglayer_container_name sed -i '/^\[proof-signers\]/a # Sequencer address for second rollup\n2 = "0x3bd49B59d0d61e83FA5C7856312b9bfEddbCbDA8"' /etc/zkevm/agglayer-config.toml
```

Restart the agglayer service for the changes to take effect.
```bash
kurtosis service stop $kurtosis_enclave_name agglayer
kurtosis service start $kurtosis_enclave_name agglayer
```

### Monitor the logs for errors 

Install [Polycli | A Swiss Army knife of blockchain tools](https://github.com/0xPolygon/polygon-cli/releases).
As of [v0.1.80](https://github.com/0xPolygon/polygon-cli/releases/tag/v0.1.80) `polycli dockerlogger` is available for easily monitoring logs of an entire docker network.

Try using the tool with something like below.
```bash
polycli dockerlogger --network kt-cdk --service agglayer,cdk-node --levels error,warn
```