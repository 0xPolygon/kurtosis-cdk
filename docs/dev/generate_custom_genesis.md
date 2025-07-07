# Create custom genesis guide:
Run Anvil using the next command:
```
anvil --block-time 1 --slots-in-an-epoch 1 --chain-id 271828 --host 0.0.0.0 --port  8545 --dump-state ./state_out.json --balance 1000000000 --mnemonic "giant issue aisle success illegal bike spike question tent bar rely arctic volcano long crawl hungry vocal artwork sniff fantasy very lucky have athlete"
```

Now, run this command to distribute funds to the deployer account:
```
cast send --private-key 0xbcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31 -r http://localhost:8545 0xE34aaF64b29273B7D567FCFc40544c014EEe9970 --value 10000ether
```

Now, clone the agglayer-contracts repo: `git clone github.com/agglayer/agglayer-contracts`
Checkout to the specific version such as `v11.0.0-rc.1`

### Prepare the repo:

Now, edit the file ./deployment/v2/3_deployContracts.ts
You need to add `initializer: false` in the globalExitRoot deploy proxy (line 358):
```
polygonZkEVMGlobalExitRoot = await upgrades.deployProxy(PolygonZkEVMGlobalExitRootFactory, [], {
    constructorArgs: [precalculateRollupManager, proxyBridgeAddress],
    unsafeAllow: ['constructor', 'state-variable-immutable'],
    initializer: false,
});
```

Now edit ./deployment/v2/deploy_parameters.json
```
{
 "admin": "0xE34aaF64b29273B7D567FCFc40544c014EEe9970",
 "deployerPvtKey": "0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625",
 "emergencyCouncilAddress": "0xE34aaF64b29273B7D567FCFc40544c014EEe9970",
 "initialZkEVMDeployerOwner": "0xE34aaF64b29273B7D567FCFc40544c014EEe9970",
 "maxFeePerGas": "",
 "maxPriorityFeePerGas": "",
 "minDelayTimelock": 60,
 "multiplierGas": "",
 "pendingStateTimeout": 604799,
 "polTokenAddress": "0xEdE9cf798E0fE25D35469493f43E88FeA4a5da0E",
 "salt": "0x0000000000000000000000000000000000000000000000000000000000000001",
 "timelockAdminAddress": "0xE34aaF64b29273B7D567FCFc40544c014EEe9970",
 "trustedSequencer": "0x5b06837A43bdC3dD9F114558DAf4B26ed49842Ed",
 "trustedSequencerURL": "http://cdk-erigon-sequencer-001:8123",
 "trustedAggregator": "0xCae5b68Ff783594bDe1b93cdE627c741722c4D4d",
 "trustedAggregatorTimeout": 604799,
 "forkID": 12,
 "test": true,
 "ppVKey": "0x00199e4c35364a8ed49c9fac0f0940aa555ce166aafc1ccb24f57d245f9c962c",
 "ppVKeySelector": "0x00000004",
 "realVerifier": false,
 "defaultAdminAddress": "0xE34aaF64b29273B7D567FCFc40544c014EEe9970",
 "aggchainDefaultVKeyRoleAddress": "0xE34aaF64b29273B7D567FCFc40544c014EEe9970",
 "addRouteRoleAddress": "0xE34aaF64b29273B7D567FCFc40544c014EEe9970",
 "freezeRouteRoleAddress": "0xE34aaF64b29273B7D567FCFc40544c014EEe9970",
 "zkEVMDeployerAddress": "0x1b50e2F3bf500Ab9Da6A7DBb6644D392D9D14b99"
}
```

### Custom genesis without rollup creation and GER initialization:
Run:
```
npx hardhat run deployment/testnet/prepareTestnet.ts --network localhost 2>&1 | tee ./01_prepare_testnet.out

MNEMONIC="giant issue aisle success illegal bike spike question tent bar rely arctic volcano long crawl hungry vocal artwork sniff fantasy very lucky have athlete" npx hardhat run deployment/v2/2_deployPolygonZKEVMDeployer.ts --network localhost 2>&1 | tee ./03_zkevm_deployer.out

MNEMONIC="giant issue aisle success illegal bike spike question tent bar rely arctic volcano long crawl hungry vocal artwork sniff fantasy very lucky have athlete" npx hardhat run deployment/v2/3_deployContracts.ts --network localhost 2>&1 | tee ./04_deploy_contracts.out
```

### Custom genesis with rollup creation without GER initialization:

Now edit ./deployment/v2/create_rollup_parameters.json
```
{
    "realVerifier": "false",
    "forkID": "12",
    "programVKey": "0x00e60517ac96bf6255d81083269e72c14ad006e5f336f852f7ee3efb91b966be",
    "description": "kurtosis-devnet - kurtosis",
    "adminZkEVM": "0xE34aaF64b29273B7D567FCFc40544c014EEe9970",
    "consensusContract": "PolygonPessimisticConsensus",
    "consensusContractName": "PolygonPessimisticConsensus",
    "type":"EOA",
    "trustedSequencerURL": "http://op-el-1-op-geth-op-node-001:8545",
    "networkName": "op-sovereign",
    "trustedSequencer": "0x5b06837A43bdC3dD9F114558DAf4B26ed49842Ed",
    "chainID": "2151908",
    "rollupAdminAddress": "0xc653eCD4AC5153a3700Fb13442Bcf00A691cca16",
    "gasTokenAddress": "0x0000000000000000000000000000000000000000",
    "deployerPvtKey": "0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625",
    "aggchainManagerPvtKey": "0xa574853f4757bfdcbb59b03635324463750b27e16df897f3d00dc6bef2997ae0",
    "maxFeePerGas": "",
    "maxPriorityFeePerGas": "",
    "multiplierGas": "",
    "timelockDelay": 0,
    "timelockSalt": "",
    "rollupManagerAddress":"0xFB054898a55bB49513D1BA8e0FB949Ea3D9B4153",
    "rollupTypeId": 1,
    "proxiedTokensManager" : "0xc653eCD4AC5153a3700Fb13442Bcf00A691cca16",
    "_comment": "TODO.. It sounds like isVanilliaClient should be false.. But setting it to false cause other issues. E.g. TypeError: newRollupContract.generateInitializeTransaction is not a function",
    "isVanillaClient": false,
    "sovereignParams": {
        "bridgeManager": "0xc653eCD4AC5153a3700Fb13442Bcf00A691cca16",
        "sovereignWETHAddress": "0x0000000000000000000000000000000000000000",
        "sovereignWETHAddressIsNotMintable": false,
        "globalExitRootUpdater": "0x0b68058E5b2592b1f472AdFe106305295A332A7C",
        "globalExitRootRemover": "0xc653eCD4AC5153a3700Fb13442Bcf00A691cca16",
        "emergencyBridgePauser": "0xc653eCD4AC5153a3700Fb13442Bcf00A691cca16",
        "emergencyBridgeUnpauser": "0xc653eCD4AC5153a3700Fb13442Bcf00A691cca16",
        "proxiedTokensManager" : "0xc653eCD4AC5153a3700Fb13442Bcf00A691cca16"
    },
    "aggchainParams": {
        "aggchainManager": "0xc653eCD4AC5153a3700Fb13442Bcf00A691cca16",
        "initParams": {
            "l2BlockTime": "<no value>",
            "rollupConfigHash": "<no value>",
            "startingOutputRoot": "<no value>",
            "startingBlockNumber": 51,
            "startingTimestamp": 1750167810,
            "submissionInterval": "<no value>",
            "optimisticModeManager": "0xc653eCD4AC5153a3700Fb13442Bcf00A691cca16",
            "aggregationVkey": "<no value>",
            "rangeVkeyCommitment": "<no value>"
        },
        "useDefaultGateway": true,
        "ownedAggchainVKey": "0x1e82b1193be48c5c6ba14dda2bcc29ab4d3dc3a2379198ac1f8571040d0a7a4d",
        "aggchainVKeySelector": "0x00010001",
        "initOwnedAggchainVKey": "0x1e82b1193be48c5c6ba14dda2bcc29ab4d3dc3a2379198ac1f8571040d0a7a4d",
        "initAggchainVKeySelector": "0x00010001",
        "vKeyManager": "0xc653eCD4AC5153a3700Fb13442Bcf00A691cca16"
    }
}
```

Run:
```
npx hardhat run deployment/testnet/prepareTestnet.ts --network localhost 2>&1 | tee ./01_prepare_testnet.out

MNEMONIC="giant issue aisle success illegal bike spike question tent bar rely arctic volcano long crawl hungry vocal artwork sniff fantasy very lucky have athlete" npx ts-node deployment/v2/1_createGenesis.ts --network localhost 2>&1 | tee ./02_create_genesis.out

MNEMONIC="giant issue aisle success illegal bike spike question tent bar rely arctic volcano long crawl hungry vocal artwork sniff fantasy very lucky have athlete" npx hardhat run deployment/v2/2_deployPolygonZKEVMDeployer.ts --network localhost 2>&1 | tee ./03_zkevm_deployer.out

MNEMONIC="giant issue aisle success illegal bike spike question tent bar rely arctic volcano long crawl hungry vocal artwork sniff fantasy very lucky have athlete" npx hardhat run deployment/v2/3_deployContracts.ts --network localhost 2>&1 | tee ./04_deploy_contracts.out

MNEMONIC="giant issue aisle success illegal bike spike question tent bar rely arctic volcano long crawl hungry vocal artwork sniff fantasy very lucky have athlete" npx hardhat run deployment/v2/4_createRollup.ts --network localhost 2>&1 | tee ./05_create_rollup.out
```


### Stop Anvil
Now, let's stop the anvil to get the state of the network.

Run: 
```
jq '{ 
      config:  { chainId: 12345, homesteadBlock: 0, berlinBlock: 0, "constantinopleBlock": 0, "byzantiumBlock": 0, "petersburgBlock": 0, "istanbulBlock": 0, "eip158Block": 0, "eip155Block": 0, "eip150Block": 0 },
      nonce:   "0x0",
      difficulty: "0x1",
      gasLimit:   "0x1fffffffffffff",
      timestamp:  "0x0",
      extraData:  "0x",
      mixHash:    "0x0000000000000000000000000000000000000000000000000000000000000000",
      coinbase:   "0x0000000000000000000000000000000000000000",
      alloc: .accounts      # <- from Anvil dump
   }' state_out.json > geth_genesis.json
```
