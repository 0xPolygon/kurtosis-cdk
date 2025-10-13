# 🍌 Deploying Fork 12 Contracts with Kurtosis CDK

By default, the Kurtosis CDK stack deploys the [fork 9](https://github.com/0xPolygonHermez/zkevm-contracts/releases/tag/v6.0.0-rc.1-fork.9) (elderberry) contracts. If you want to deploy the [fork 12](https://github.com/0xPolygonHermez/zkevm-contracts/releases/tag/v8.0.0-rc.1-fork.12) (banana) contracts instead, follow these steps.

## 1. Update the Configuration File

Modify the `params.yml` file to specify the fork 12 settings.

```bash
yq -Y --in-place '.args.zkevm_rollup_fork_id = "12"' params.yml
yq -Y --in-place '.args.zkevm_prover_image = "hermeznetwork/zkevm-prover:v8.0.0-RC5-fork.12"' params.yml
yq -Y --in-place '.args.cdk_erigon_node_image = "hermeznetwork/cdk-erigon:fe54243ce2cd0563396b509ff19e178178e9d712"' params.yml
```

## 2. Deploy the CDK Stack

Execute the following command to deploy the CDK stack with fork 12 contracts:

```bash
kurtosis run --enclave cdk --args-file params.yml .
```

## 3. Verify the Deployment

Once the environment is running, verify that fork 12 is deployed by executing the following commands:

```bash
rollup_manager_address="$(kurtosis service exec cdk contracts-001 'cat /opt/output/combined.json' | tail -n +2 | jq --raw-output '.polygonRollupManagerAddress')"
rpc_url="$(kurtosis port print cdk el-1-geth-lighthouse rpc)"
sig="rollupIDToRollupData(uint32)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint64,uint64,uint8)"
cast call --rpc-url $rpc_url $rollup_manager_address $sig 1
```

You should expect the 4th value (fork id) to be equal to `12`, confirming that fork 12 is successfully deployed.

```bash
0x1Fe038B54aeBf558638CA51C91bC8cCa06609e91
10101 [1.01e4]
0xf22E2B040B639180557745F47aB97dFA95B1e22a
12
0x0000000000000000000000000000000000000000000000000000000000000000
1
0
0
0
0
1
0
```
