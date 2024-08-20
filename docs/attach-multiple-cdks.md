## Attach Multiple CDKs to the Agglayer

By default, the Agglayer service will be deployed with the above deployment instructions. To create a devnet with multiple rollups attached to the agglayer:

```bash
kurtosis run --enclave cdk-v1 --args-file agglayer-attach-cdk-params.yml .
```

The above command will use `agglayer-attach-cdk-params.yml` as the input params which have a few tweaked parameters to attach to the existing Agglayer service.
After running the above additional deployment command, the `agglayer-config.toml` needs to be edited to settle the signed transactions from the rollups.

```bash
# Shell into the Agglayer service
kurtosis service shell cdk-v1 zkevm-agglayer-001

# Edit the agglayer-config.toml file
vim /etc/zkevm/agglayer-config.toml
```

The `agglayer-config.toml` file should be changed as follows:
```bash
[FullNodeRPCs]
# RPC of the first rollup node
1 = "http://cdk-erigon-node-001:8123"
# RPC of the second rollup node
2 = "http://cdk-erigon-node-002:8123"

[ProofSigners]
# Sequencer address for first rollup
1 = "0x5b06837A43bdC3dD9F114558DAf4B26ed49842Ed"
# Sequencer address for second rollup
2 = "0xF4ee37aAc3ccd6B71A4a795700b065d2CA479581"
```

Then restart the Agglayer service
```bash
kurtosis service stop cdk-v1 zkevm-agglayer-001
kurtosis service start cdk-v1 zkevm-agglayer-001
```
