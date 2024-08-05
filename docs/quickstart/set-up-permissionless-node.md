---
comments: true
---

In addition to the core stack, you can also attach and synchronize a permissionless node.

## Prerequisites

1. You have followed the [deployment guide](deploy-stack.md) and have a running CDK stack.

2. Grab the genesis file artifact and add it to the `permissionless_node` kurtosis package.

```sh
rm -r /tmp/zkevm
kurtosis files download cdk-v1 genesis /tmp
cp /tmp/genesis.json templates/permissionless-node/genesis.json
```

## Add permissionless node to the enclave

Run the following command:

```sh
yq -Y --in-place 'with_entries(if .key == "deploy_zkevm_permissionless_node" then .value = true elif .value | type == "boolean" then .value = false else . end)' params.yml
kurtosis run --enclave cdk-v1 --args-file params.yml .
```

## Sync an external permissionless node

You can also use the package you have just set up to sync data from a production network.

1. Some of the parameters in the Kurtosis genesis file need to be replaced, or better still you could replace the whole genesis file with one representing the external network.

    The parameters that need to change in the file are as follows:

    ```json
      "rollupCreationBlockNumber": 22,
      "rollupManagerCreationBlockNumber": 18,
      "genesisBlockNumber": 22,
      "L1Config": {
        "chainId": 271828,
        "polygonZkEVMGlobalExitRootAddress": "0x1f7ad7caA53e35b4f0D138dC5CBF91aC108a2674",
        "polygonRollupManagerAddress": "0x2F50ef6b8e8Ee4E579B17619A92dE3E2ffbD8AD2",
        "polTokenAddress": "0xEdE9cf798E0fE25D35469493f43E88FeA4a5da0E",
        "polygonZkEVMAddress": "0x1Fe038B54aeBf558638CA51C91bC8cCa06609e91"
      }
    ```

    !!! tip
        The [run-contract-setup.sh](https://github.com/0xPolygon/kurtosis-cdk/blob/main/templates/run-contract-setup.sh) file may help you understand how these fields populate.

2. When you have the updated genesis file ready, drop it into `./templates/permissionless-node/genesis.json`.

3. In addition to the genesis setup, tweak the parameter `l1_rpc_url` in the [params.yml](https://github.com/0xPolygon/kurtosis-cdk/blob/main/params.yml) file:

    `l1_rpc_url: http://el-1-geth-lighthouse:8545` -> `l1_rpc_url: <MY_L1_URL>`

    !!! tip
        - There are other parameters that seem like they should be changed, e.g. `l1_chain_id`, but they aren't used for the permissionless setup.

4. Now you can start synchronizing with the following command:

    ```sh
    yq -Y --in-place 'with_entries(if .key == "deploy_zkevm_permissionless_node" then .value = true elif .value | type == "boolean" then .value = false else . end)' params.yml
    kurtosis run --enclave cdk-v1 --args-file params.yml .
    ```

<br/>
