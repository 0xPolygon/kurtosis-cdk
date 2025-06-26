#!/bin/bash

# deploymentRollupManagerBlockNumber must be different to 0 becuase cdk-erigon and cdk-node requires this value (zkevm.l1-first-block) to be different to 0
cat >/opt/zkevm/combined.json <<'EOF'
    {
        "polygonRollupManagerAddress": "0xFB054898a55bB49513D1BA8e0FB949Ea3D9B4153",
        "polygonZkEVMBridgeAddress":   "0x927aa8656B3a541617Ef3fBa4A2AB71320dc7fD7",
        "polygonZkEVMGlobalExitRootAddress": "0x2F50ef6b8e8Ee4E579B17619A92dE3E2ffbD8AD2",
        "aggLayerGatewayAddress":      "0x6c6c009cC348976dB4A908c92B24433d4F6edA43",
        "pessimisticVKeyRouteALGateway": {
            "pessimisticVKeySelector": "0x00000004",
            "verifier":                "0xf22E2B040B639180557745F47aB97dFA95B1e22a",
            "pessimisticVKey":         "0x00199e4c35364a8ed49c9fac0f0940aa555ce166aafc1ccb24f57d245f9c962c"
        },
        "polTokenAddress":            "0xEdE9cf798E0fE25D35469493f43E88FeA4a5da0E",
        "zkEVMDeployerContract":      "0x1b50e2F3bf500Ab9Da6A7DBb6644D392D9D14b99",
        "deployerAddress":            "0xE34aaF64b29273B7D567FCFc40544c014EEe9970",
        "timelockContractAddress":    "0x3D4C5989214ca3CDFf9e62778cDD56a94a05348D",
        "deploymentRollupManagerBlockNumber": 1,
        "upgradeToULxLyBlockNumber":          0,
        "admin":                 "0xE34aaF64b29273B7D567FCFc40544c014EEe9970",
        "trustedAggregator":      "0xCae5b68Ff783594bDe1b93cdE627c741722c4D4d",
        "proxyAdminAddress":      "0xd60F1BCf5566fCCD62f8AA3bE00525DdA6Ab997c",
        "salt":                   "0x0000000000000000000000000000000000000000000000000000000000000001",
        "polygonZkEVML2BridgeAddress":        "0x927aa8656B3a541617Ef3fBa4A2AB71320dc7fD7",
        "polygonZkEVMGlobalExitRootL2Address": "0xa40d5f56745a118d0906a34e69aec8c0db1cb8fa",
        "bridgeGenBlockNumber":               0
    }
EOF

cp /opt/zkevm/combined.json /opt/zkevm-contracts/deployment/v2/deploy_output.json
cp /opt/zkevm/combined.json /opt/zkevm/deploy_output.json

cast send 0x2F50ef6b8e8Ee4E579B17619A92dE3E2ffbD8AD2 "initialize()" --private-key "{{.zkevm_l2_admin_private_key}}" --rpc-url "{{.l1_rpc_url}}"
