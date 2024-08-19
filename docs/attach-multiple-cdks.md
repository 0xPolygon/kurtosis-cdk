## Attach Multiple CDKs to the Agglayer

**Optional - deploy another CDK and attach to the agglayer service**

```bash
kurtosis run --enclave cdk-v1 --args-file agglayer-attach-cdk-params.yml .
```

Once the deployments are done, shell into the agglayer service using `kurtosis service shell cdk-v1 zkevm-agglayer-001`.

```bash
# Install vim
apt update
apt install --yes vim

# Edit the agglayer-config.toml file
vim /etc/zkevm/agglayer-config.toml
```

An example is shown below.

```toml
[FullNodeRPCs]
# Change the RPCs as necessary for Erigon/zkEVM RPCs
# First CDK RPC
1 = "http://zkevm-node-rpc-001:8123"
# 1 = "http://cdk-erigon-node-001:8123"
# Second CDK RPC
2 = "http://zkevm-node-rpc-002:8123"
# 2 = "http://cdk-erigon-node-002:8123"

[ProofSigners]
# First CDK Sequencer Address
1 = "0x5b06837A43bdC3dD9F114558DAf4B26ed49842Ed"
# Second CDK Sequencer Address
2 = "0xF4ee37aAc3ccd6B71A4a795700b065d2CA479581"
```

Then restart the `agglayer` service.

```bash
kurtosis service stop cdk-v1 zkevm-agglayer-001
kurtosis service start cdk-v1 zkevm-agglayer-001
```
