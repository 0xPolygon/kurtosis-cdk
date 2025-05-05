# Attach Multiple CDK-Erigon to the Agglayer

First have a running devnet:

```bash
kurtosis run --enclave=cdk .
```

Then run kurtosis again in the same enclave using a second args-file:

```bash
kurtosis run --enclave=cdk --args-file=./.github/tests/chains/cdk2.yml .
```

The above command will use `cdk2.yml` as the input params which have a few tweaked parameters to attach to the existing Agglayer service. After running the above additional deployment command, the `agglayer-config.toml` needs to be edited to settle the signed transactions from the rollups.

```bash
# Use sed to replace the [full-node-rpcs] section
kurtosis service exec cdk agglayer "sed -i '/^\[full-node-rpcs\]/a 2 = \"http://cdk-erigon-rpc-002:8123\"' /etc/zkevm/agglayer-config.toml"

# Use sed to replace the [proof-signers] section
kurtosis service exec cdk agglayer "sed -i '/^\[proof-signers\]/a 2 = \"0xA670342930242407b9984e467353044f8472055e\"' /etc/zkevm/agglayer-config.toml"
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
kurtosis service stop cdk agglayer
kurtosis service start cdk agglayer
```

Test the bridging using the [e2e repo](https://github.com/agglayer/e2e).
Make sure to set the correct env vars as the test setup, and then run:

```bash
bats tests/lxly/lxly.bats
```