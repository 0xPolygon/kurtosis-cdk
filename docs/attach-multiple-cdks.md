# Attach Multiple CDKs to the Agglayer

By default, the Agglayer service will be deployed with the above deployment instructions. To create a devnet with multiple rollups attached to the agglayer:

```bash
kurtosis run --enclave=cdk --args-file=./.github/tests/attach-second-cdk.yml .
```

The above command will use `attach-second-cdk.yml` as the input params which have a few tweaked parameters to attach to the existing Agglayer service. After running the above additional deployment command, the `agglayer-config.toml` needs to be edited to settle the signed transactions from the rollups.

```bash
# Shell into the Agglayer service
kurtosis service shell cdk agglayer

# Edit the agglayer-config.toml file
vim /etc/zkevm/agglayer-config.toml
```

The `agglayer-config.toml` file should be changed as follows:

```bash
[full-node-rpcs]
# RPC of the first rollup node
1 = "http://cdk-erigon-rpc-001:8123"
# RPC of the second rollup node
2 = "http://cdk-erigon-rpc-002:8123"

[proof-signers]
# Sequencer address for first rollup
1 = "0x5b06837A43bdC3dD9F114558DAf4B26ed49842Ed"
# Sequencer address for second rollup
2 = "0xA670342930242407b9984e467353044f8472055e"
```

Then restart the Agglayer service.

```bash
kurtosis service stop cdk-v1 agglayer
kurtosis service start cdk-v1 agglayer
```
