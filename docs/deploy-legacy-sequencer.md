# Deploy Legacy Sequencer

By default, the Kurtosis CDK package uses [erigon](https://github.com/0xPolygonHermez/cdk-erigon) as the sequencer. But it is also possible to use the legacy sequencer, [zkevm-node](https://github.com/0xPolygonHermez/zkevm-node).

In order to do that, you will need to run the following command.

```bash
kurtosis run --enclave cdk-v1 --args-file params.yml . \
  '{
    "deploy_cdk_erigon_node": false,
    "args": {
      "sequencer_type": "zkevm",
      "l1_seconds_per_slot": 1
    }
  }'
```

You can run the same commands as shown in the main `README`, you will just need to change the way you retrieve the RPC URL.

```bash
export ETH_RPC_URL="$(kurtosis port print cdk-v1 zkevm-node-rpc-001 http-rpc)"
```

Then you can simply check the state of the system or send transactions to the network!

```bash
cast rpc zkevm_batchNumber
cast rpc zkevm_virtualBatchNumber
cast rpc zkevm_verifiedBatchNumber
```
