# Deploy Kurtosis CDK with Sepolia as L1

Deploying to Sepolia requires changing the L1-related parameters.

## params.yml
Change `deploy_l1` to `false`.
```
# Deploy local L1.
deploy_l1: false
```

Change the `l1_chain_id`, `l1_preallocated_mnemonic`, `l1_rpc_url`, `l1_ws_url`, and `l1_funding_amount` as needed.
```
l1_chain_id: 11155111
# The first account for the mnemonic should have enough funds to cover the deployment costs and the l1_funding_amount transfers to L1 addresses.
l1_preallocated_mnemonic: <mnemonic_for_a_funded_L1_account>
# The amount of initial funding to L1 addresses performing services like the Sequencer, Aggregator, Admin, Agglayer, Claimtxmanager. 
l1_funding_amount: 1ether
l1_rpc_url: <Sepolia_RPC_URL>
l1_ws_url: <Sepolia_WS_URL>
```

## cdk_bridge_infra.star

Comment out the below:
```
...
# l1rpc_service = plan.get_service("el-1-geth-lighthouse")
...
# "l1rpc_ip": l1rpc_service.ip_address,
# "l1rpc_port": l1rpc_service.ports["rpc"].number,
```

## templates/bridge-infra/haproxy.cfg

Comment out the below:
```
...
    # acl url_l1rpc path_beg /l1rpc
...
    # use_backend backend_l1rpc if url_l1rpc
...   
# backend backend_l1rpc
#     http-request set-path /
#     server server1 {{.l1rpc_ip}}:{{.l1rpc_port}}
```

## Debugging

If there are issues during the contract deployment stage such as:

```!
polygonZkEVMDeployer already deployed on:  0xe5CF69183CFCF0571E733D59a1a53d4E6ceD6E85
[2024-05-09 14:21:26] Step 4: Deploying contracts
> @0xpolygonhermez/zkevm-contracts@3.0.0 npx
> hardhat run deployment/v2/3_deployContracts.ts --network localhost
#######################
Proxy admin was already deployed to: 0xD2e85a0f5884b63F4Ed1C127f7ED818373b496b5
Error: Proxy admin was deployed, but the owner is not the deployer, deployer address: 0xE34aaF64b29273B7D567FCFc40544c014EEe9970, proxyAdmin: 0xaB02c39dd8755c9c5cFcde15996E504Fb0B1F295
    at main (/opt/zkevm-contracts/deployment/v2/3_deployContracts.ts:190:15)
    at processTicksAndRejections (node:internal/process/task_queues:95:5)
[2024-05-09 14:21:30] Step 5: Creating rollup
> @0xpolygonhermez/zkevm-contracts@3.0.0 npx
> hardhat run deployment/v2/4_createRollup.ts --network localhost
Error: Cannot find module './deploy_output.json'
Require stack:
- /opt/zkevm-contracts/deployment/v2/4_createRollup.ts
    at Function.Module._resolveFilename (node:internal/modules/cjs/loader:1143:15)
```

Try changing the `salt` value in `deploy_parameters.yml` and do a fresh deployment again. Successful deployment should have logs like below:

```!
Deploying zkevm contracts on L1
Command returned with exit code '0' and the following output:
--------------------
[2024-05-10 01:03:39] Waiting for the L1 RPC to be available

blockHash               0x02dd2e746e726de2f80c1761d54a92b44811e0bc604c8019d4ba1a53b1c964c5
blockNumber             5870999
contractAddress         
cumulativeGasUsed       385156
effectiveGasPrice       3000458876
from                    0x5A13035786d906732509D1a0815906c7124fB58C
gasUsed                 21000
logs                    []
logsBloom               0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
root                    
status                  1
transactionHash         0xcbcf45e37a0933b1f173d8fa40697502589a5a02de22253bbbb876fca36da0e1
transactionIndex        4
type                    2
to                      0x5b06837A43bdC3dD9F114558DAf4B26ed49842Ed
[2024-05-10 01:03:56] L1 RPC is now available
[2024-05-10 01:03:56] Funding important accounts on l1
[2024-05-10 01:03:56] Funding admin account

blockHash               0xc70a02e31b507ccbd8fd20a6fb8f114d8a5921f248e93a968d53de9f86cc6682
blockNumber             5871001
contractAddress         
cumulativeGasUsed       174182
effectiveGasPrice       3000390130
from                    0x5A13035786d906732509D1a0815906c7124fB58C
gasUsed                 21000
logs                    []
logsBloom               0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
root                    
status                  1
transactionHash         0xd10a88461254c80f6de784a7efd3f1fea60dd0f153dce3dabfba31875edc12be
transactionIndex        3
type                    2
to                      0xE34aaF64b29273B7D567FCFc40544c014EEe9970
[2024-05-10 01:04:18] Funding sequencer account

blockHash               0x95422a87457d9517cd9e5e6d5bc08f60e5478e624cfba1d9265dfce5651b23a1
blockNumber             5871002
contractAddress         
cumulativeGasUsed       114685
effectiveGasPrice       3000362694
from                    0x5A13035786d906732509D1a0815906c7124fB58C
gasUsed                 21000
logs                    []
logsBloom               0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
root                    
status                  1
transactionHash         0xb19e8b429d38dabeb259accf8096146991367317de68afd1365b0b8238a6606b
transactionIndex        3
type                    2
to                      0x5b06837A43bdC3dD9F114558DAf4B26ed49842Ed
[2024-05-10 01:04:28] Funding aggregator account

blockHash               0x8a10e9ee8047ce2292eb6dc280ae714c86dc87558be52610b20e1883fdcb38ac
blockNumber             5871004
contractAddress         
cumulativeGasUsed       709250
effectiveGasPrice       3000365802
from                    0x5A13035786d906732509D1a0815906c7124fB58C
gasUsed                 21000
logs                    []
logsBloom               0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
root                    
status                  1
transactionHash         0x6f59dfe631d245dc9afbd31860686b8f00018436305a8da539e8e4aefab165d0
transactionIndex        5
type                    2
to                      0xCae5b68Ff783594bDe1b93cdE627c741722c4D4d
[2024-05-10 01:04:51] Funding agglayer account

blockHash               0x12b0a753afa3716647d5289a7096dbfbd93d2335dd87a88fdfa6119c37dd56a8
blockNumber             5871005
contractAddress         
cumulativeGasUsed       1560625
effectiveGasPrice       3000360192
from                    0x5A13035786d906732509D1a0815906c7124fB58C
gasUsed                 21000
logs                    []
logsBloom               0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
root                    
status                  1
transactionHash         0x34cd108ad87b358b4cf53155306c85530bd6000c24b44fe2105e3d44eb17df4e
transactionIndex        1
type                    2
to                      0x351e560852ee001d5D19b5912a269F849f59479a
[2024-05-10 01:05:02] Funding claimtxmanager account

blockHash               0x078f1881f3d4205dd351e1aacd8d6d7045b9b99627936e64e31cfd45f386dae4
blockNumber             5871006
contractAddress         
cumulativeGasUsed       350178
effectiveGasPrice       3000336941
from                    0x5A13035786d906732509D1a0815906c7124fB58C
gasUsed                 21000
logs                    []
logsBloom               0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
root                    
status                  1
transactionHash         0xc04ef70f2f23a754ec480c6f023832b8983363746e002771d8da9efb1884e96e
transactionIndex        9
type                    2
to                      0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8
/opt/zkevm-contracts /opt
[2024-05-10 01:05:17] Deploying zkevm contracts to L1
[2024-05-10 01:05:17] Step 1: Preparing tesnet

> @0xpolygonhermez/zkevm-contracts@3.0.0 npx
> hardhat run deployment/testnet/prepareTestnet.ts --network localhost

#######################

pol deployed to: 0x66aB447a8D8D13E6d2f9E3B317FED8668cc10075
[2024-05-10 01:05:38] Step 2: Creating genesis

> @0xpolygonhermez/zkevm-contracts@3.0.0 npx
> ts-node deployment/v2/1_createGenesis.ts

Warning: Potentially unsafe deployment of contracts/PolygonZkEVMGlobalExitRootL2.sol:PolygonZkEVMGlobalExitRootL2

    You are using the `unsafeAllow.state-variable-immutable` flag.

Warning: Potentially unsafe deployment of contracts/PolygonZkEVMGlobalExitRootL2.sol:PolygonZkEVMGlobalExitRootL2

    You are using the `unsafeAllow.constructor` flag.

[2024-05-10 01:05:42] Step 3: Deploying PolygonZKEVMDeployer

> @0xpolygonhermez/zkevm-contracts@3.0.0 npx
> hardhat run deployment/v2/2_deployPolygonZKEVMDeployer.ts --network localhost

#######################

polygonZkEVMDeployer already deployed on:  0xe5CF69183CFCF0571E733D59a1a53d4E6ceD6E85
[2024-05-10 01:05:44] Step 4: Deploying contracts

> @0xpolygonhermez/zkevm-contracts@3.0.0 npx
> hardhat run deployment/v2/3_deployContracts.ts --network localhost

#######################

Proxy admin deployed to: 0xD73b976745bBABbd20674f8937452412b9739CBF
#######################

bridge impl deployed to: 0xA39B543Ee657c5e89F17adD608552b7970E4cBDd

#######################
##### Deployment TimelockContract  #####
#######################
minDelayTimelock: 3600
timelockAdminAddress: 0xE34aaF64b29273B7D567FCFc40544c014EEe9970
Rollup Manager: 0x010822310E62c42B6FDD7A56fe2173b1F0548446
#######################

Polygon timelockContract deployed to: 0xc841dC5bce9412f492ec287Ca0b2c757c458bCC6

#######################
#####  Checks TimelockContract  #####
#######################
polygonZkEVM (Rollup Manager): 0x010822310E62c42B6FDD7A56fe2173b1F0548446
#######################

PolygonZkEVMBridge deployed to: 0xe7D2a1A57C88AD0373d304Cf63eA9aDC780Eb83F

#######################
#####    Checks PolygonZkEVMBridge   #####
#######################
PolygonZkEVMGlobalExitRootAddress: 0xD064B30fBf9103DcFc4b7B966534943E78E8aE93
networkID: 0n
Rollup Manager: 0x010822310E62c42B6FDD7A56fe2173b1F0548446
Warning: Potentially unsafe deployment of contracts/v2/PolygonZkEVMGlobalExitRootV2.sol:PolygonZkEVMGlobalExitRootV2

    You are using the `unsafeAllow.state-variable-immutable` flag.

Warning: Potentially unsafe deployment of contracts/v2/PolygonZkEVMGlobalExitRootV2.sol:PolygonZkEVMGlobalExitRootV2

    You are using the `unsafeAllow.constructor` flag.

#######################

polygonZkEVMGlobalExitRoot deployed to: 0xD064B30fBf9103DcFc4b7B966534943E78E8aE93

#######################
##### Deployment Rollup Manager #####
#######################
deployer: 0xE34aaF64b29273B7D567FCFc40544c014EEe9970
PolygonZkEVMGlobalExitRootAddress: 0xD064B30fBf9103DcFc4b7B966534943E78E8aE93
polTokenAddress: 0x66aB447a8D8D13E6d2f9E3B317FED8668cc10075
polygonZkEVMBridgeContract: 0xe7D2a1A57C88AD0373d304Cf63eA9aDC780Eb83F
trustedAggregator: 0xCae5b68Ff783594bDe1b93cdE627c741722c4D4d
pendingStateTimeout: 604799
trustedAggregatorTimeout: 604799
admin: 0xE34aaF64b29273B7D567FCFc40544c014EEe9970
timelockContract: 0xE34aaF64b29273B7D567FCFc40544c014EEe9970
emergencyCouncilAddress: 0xE34aaF64b29273B7D567FCFc40544c014EEe9970
Warning: Potentially unsafe deployment of contracts/v2/newDeployments/PolygonRollupManagerNotUpgraded.sol:PolygonRollupManagerNotUpgraded

    You are using the `unsafeAllow.state-variable-immutable` flag.

Warning: Potentially unsafe deployment of contracts/v2/newDeployments/PolygonRollupManagerNotUpgraded.sol:PolygonRollupManagerNotUpgraded

    You are using the `unsafeAllow.constructor` flag.

#######################

polygonRollupManagerContract deployed to: 0x010822310E62c42B6FDD7A56fe2173b1F0548446

#######################
#####    Checks  Rollup Manager  #####
#######################
PolygonZkEVMGlobalExitRootAddress: 0xD064B30fBf9103DcFc4b7B966534943E78E8aE93
polTokenAddress: 0x66aB447a8D8D13E6d2f9E3B317FED8668cc10075
polygonZkEVMBridgeContract: 0xe7D2a1A57C88AD0373d304Cf63eA9aDC780Eb83F
pendingStateTimeout: 604799n
trustedAggregatorTimeout: 604799n
[2024-05-10 01:07:43] Step 5: Creating rollup

> @0xpolygonhermez/zkevm-contracts@3.0.0 npx
> hardhat run deployment/v2/4_createRollup.ts --network localhost

#######################

Verifier deployed to: 0x2D4ad6bD18B4F6a31CE440B6F4f0D535D9D4C02e
#######################

Added new Rollup Type deployed
#######################

Created new Rollup: 0xCfD26022600CE3b9CA4296D2f2DCB667B85d05E1
Warning: Potentially unsafe deployment of contracts/v2/consensus/validium/PolygonDataCommittee.sol:PolygonDataCommittee

    You are using the `unsafeAllow.constructor` flag.

[2024-05-10 01:09:26] Combining contract deploy files
/opt
/opt/zkevm /opt
[2024-05-10 01:09:26] Creating combined.json
[2024-05-10 01:09:26] Approving the rollup address to transfer POL tokens on behalf of the sequencer

blockHash               0xebfbeec560249c5a85211560e504872f3136a345ffb15c4050f1520a65b729db
blockNumber             5871029
contractAddress         
cumulativeGasUsed       21579165
effectiveGasPrice       11182118
from                    0x5b06837A43bdC3dD9F114558DAf4B26ed49842Ed
gasUsed                 46267
logs                    [{"address":"0x66ab447a8d8d13e6d2f9e3b317fed8668cc10075","topics":["0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925","0x0000000000000000000000005b06837a43bdc3dd9f114558daf4b26ed49842ed","0x000000000000000000000000cfd26022600ce3b9ca4296d2f2dcb667b85d05e1"],"data":"0x0000000000000000000000000000000000000000033b2e3c9fd0803ce8000000","blockHash":"0xebfbeec560249c5a85211560e504872f3136a345ffb15c4050f1520a65b729db","blockNumber":"0x5995b5","transactionHash":"0xbc244825e172a4db0bfd9bbee4b6d08cabc0bfe29143207601a4db3667c3f596","transactionIndex":"0x7e","logIndex":"0x17c","removed":false}]
logsBloom               0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000008020000000000000000000000010000000000000040000000000000000000000000000000000080000000000000000000100000000000000000000000000000000010000000000000000000000001000000000000040000100000000000000000
root                    
status                  1
transactionHash         0xbc244825e172a4db0bfd9bbee4b6d08cabc0bfe29143207601a4db3667c3f596
transactionIndex        126
type                    0
to                      0x66aB447a8D8D13E6d2f9E3B317FED8668cc10075
[2024-05-10 01:09:54] Setting the data availability committee

blockHash               0xbffc93a4c6a5b9119577c4ab4237f84a686db6364bc40b4e0dd8408c6fe8df4b
blockNumber             5871030
contractAddress         
cumulativeGasUsed       795333
effectiveGasPrice       3000467524
from                    0xE34aaF64b29273B7D567FCFc40544c014EEe9970
gasUsed                 146938
logs                    [{"address":"0x139359d5f2c27e10c2a0bbf3eaabefee697fbe72","topics":["0x831403fd381b3e6ac875d912ec2eee0e0203d0d29f7b3e0c96fc8f582d6db657"],"data":"0xe4e05261d6d69a2de8d0b41196695761a8e911eb19355d391a8ce19d9a9f7cbe","blockHash":"0xbffc93a4c6a5b9119577c4ab4237f84a686db6364bc40b4e0dd8408c6fe8df4b","blockNumber":"0x5995b6","transactionHash":"0x1da02320c283ce31b98beeb261ecbb82a627c1cb4c26ebed4c1a33694ee0c903","transactionIndex":"0x4","logIndex":"0x3","removed":false}]
logsBloom               0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000400000000000000001
root                    
status                  1
transactionHash         0x1da02320c283ce31b98beeb261ecbb82a627c1cb4c26ebed4c1a33694ee0c903
transactionIndex        4
type                    2
to                      0x139359d5F2c27E10c2a0bbf3eAabEFEe697Fbe72
[2024-05-10 01:10:03] Setting the data availability protocol

blockHash               0xf69cb9130f1ed963d5862f45ce4d742ae4e5ce2eb5fbda96b227c15d7a868971
blockNumber             5871031
contractAddress         
cumulativeGasUsed       243659
effectiveGasPrice       3000440604
from                    0xE34aaF64b29273B7D567FCFc40544c014EEe9970
gasUsed                 32178
logs                    [{"address":"0xcfd26022600ce3b9ca4296d2f2dcb667b85d05e1","topics":["0xd331bd4c4cd1afecb94a225184bded161ff3213624ba4fb58c4f30c5a861144a"],"data":"0x000000000000000000000000139359d5f2c27e10c2a0bbf3eaabefee697fbe72","blockHash":"0xf69cb9130f1ed963d5862f45ce4d742ae4e5ce2eb5fbda96b227c15d7a868971","blockNumber":"0x5995b7","transactionHash":"0x8c79ae2f6a79d3dc2a5ee6f30a666d27ddf4e2b29e0a6de3e4da5aecef126acf","transactionIndex":"0x2","logIndex":"0x9","removed":false}]
logsBloom               0x00008000000000000000010000000000001000000000001000000400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000
root                    
status                  1
transactionHash         0x8c79ae2f6a79d3dc2a5ee6f30a666d27ddf4e2b29e0a6de3e4da5aecef126acf
transactionIndex        2
type                    2
to                      0xCfD26022600CE3b9CA4296D2f2DCB667B85d05E1
[2024-05-10 01:10:12] Granting the aggregator role to the agglayer so that it can also verify batches

blockHash               0xb15815813a5ee4e8891566473d5326e0ca02eca9ea134148586293387197db74
blockNumber             5871032
contractAddress         
cumulativeGasUsed       786716
effectiveGasPrice       3000475237
from                    0xE34aaF64b29273B7D567FCFc40544c014EEe9970
gasUsed                 58519
logs                    [{"address":"0x010822310e62c42b6fdd7a56fe2173b1f0548446","topics":["0x2f8788117e7eff1d82e926ec794901d17c78024a50270940304540a733656f0d","0x084e94f375e9d647f87f5b2ceffba1e062c70f6009fdbcf80291e803b5c9edd4","0x000000000000000000000000351e560852ee001d5d19b5912a269f849f59479a","0x000000000000000000000000e34aaf64b29273b7d567fcfc40544c014eee9970"],"data":"0x","blockHash":"0xb15815813a5ee4e8891566473d5326e0ca02eca9ea134148586293387197db74","blockNumber":"0x5995b8","transactionHash":"0xf56626c13692c95efae770a414303718ecf009a1bf72f4f75a41858fa75b57b9","transactionIndex":"0x7","logIndex":"0xb","removed":false}]
logsBloom               0x00000004000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000000000004000000000000040000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000110000000000008000000000000000000000000000001000000030000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000001000000000000000
root                    
status                  1
transactionHash         0xf56626c13692c95efae770a414303718ecf009a1bf72f4f75a41858fa75b57b9
transactionIndex        7
type                    2
to                      0x010822310E62c42B6FDD7A56fe2173b1F0548446

--------------------
```