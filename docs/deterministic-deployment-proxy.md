# Deploy Contracts with the Deterministic Deployment Proxy

A guide to deploy contracts using the [deterministic deployment proxy](https://github.com/Arachnid/deterministic-deployment-proxy).

## Introduction

You can deploy contracts to both L1 and L2 using the deterministic deployment
proxy. Deploying the same contract to multiple chains will result in the same
contract address.

There are two ways to go about deploying contracts:

1. Manually in your local environment. This requires you to have [`foundry/cast`](https://github.com/foundry-rs/foundry) installed.
2. Using the [`run-l2-contract-setup.sh`](/templates/contract-deploy/run-l2-contract-setup.sh) script. This ensures that the contracts will be deployed with every `kurtosis run`.

## Deploying Contracts Locally

For this example, we will be deploying this contract:

```solidity
pragma solidity 0.5.8;
contract Apple {
    function banana() external pure returns (uint8) {
        return 42;
    }
}
```

To determine the contract address of the above contract, compile the bytecode
and run:

```bash
cast create2 --salt $salt --init-code $bytecode
```

To deploy a contract, send the salt and bytecode to the deterministic deployment
proxy deployer address which should be `0x4e59b44847b379578588920ca78fbf26c0b4956c`.

### Deploy Contracts on L1

The accounts using the `giant issue aisle success illegal bike spike question tent bar rely arctic volcano long crawl hungry vocal artwork sniff fantasy very lucky have athlete`
mnemonic are pre-funded on L1, so you can use those accounts to for the contract
deployments.

```bash
polycli wallet inspect --mnemonic "giant issue aisle success illegal bike spike question tent bar rely arctic volcano long crawl hungry vocal artwork sniff fantasy very lucky have athlete" | jq -r ".Addresses[0].HexPrivateKey"
```

```bash
cast send \
    --legacy \
    --rpc-url "http://$(kurtosis port print cdk el-1-geth-lighthouse rpc)" \
    --private-key "0xbcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31" \
    "0x4e59b44847b379578588920ca78fbf26c0b4956c" \
    "$salt$bytecode"
```

### Deploy Contracts on L2

This is similar to L1, just that the major difference is the pre-funded account
on L2 is the `zkevm_l2_admin_private_key`.

```bash
cast send \
    --legacy \
    --rpc-url "$(kurtosis port print cdk cdk-erigon-rpc-001 rpc)" \
    --private-key "0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625" \
    "0x4e59b44847b379578588920ca78fbf26c0b4956c" \
    "$salt$bytecode"
```

## Deploying Contracts using `run-l2-contract-setup.sh`

Most of the same concepts from above apply, you just now have access to some
different variables provided through the kurtosis such as `l1_rpc_url` and
`l2_rpc_url`.

Here's a complete example that could be appended to the `run-l2-contract-setup.sh`:

```bash
contract_method_signature="banana()(uint8)"
expected="42"
salt="0x0000000000000000000000000000000000000000000000000000000000000000"
# contract: pragma solidity 0.5.8; contract Apple {function banana() external pure returns (uint8) {return 42;}}
bytecode="6080604052348015600f57600080fd5b5060848061001e6000396000f3fe6080604052348015600f57600080fd5b506004361060285760003560e01c8063c3cafc6f14602d575b600080fd5b6033604f565b604051808260ff1660ff16815260200191505060405180910390f35b6000602a90509056fea165627a7a72305820ab7651cb86b8c1487590004c2444f26ae30077a6b96c6bc62dda37f1328539250029"
contract_address=$(cast create2 --salt $salt --init-code $bytecode)

echo_ts "Testing deterministic deployment proxy on l1"
cast send \
    --legacy \
    --rpc-url "{{.l1_rpc_url}}" \
    --private-key "$l1_private_key" \
    "$deployer_address" \
    "$salt$bytecode"
l1_actual=$(cast call --rpc-url "{{.l1_rpc_url}}" "$contract_address" "$contract_method_signature")
if [[ "$expected" != "$l1_actual" ]]; then
    echo_ts "Failed to deploy deterministic deployment proxy on l1 (expected: $expected, actual $l1_actual)"
    exit 1
fi

echo_ts "Testing deterministic deployment proxy on l2"
cast send \
    --legacy \
    --rpc-url "{{.l2_rpc_url}}" \
    --private-key "{{.zkevm_l2_admin_private_key}}" \
    "$deployer_address" \
    "$salt$bytecode"
l2_actual=$(cast call --rpc-url "{{.l2_rpc_url}}" "$contract_address" "$contract_method_signature")
if [[ "$expected" != "$l2_actual" ]]; then
    echo_ts "Failed to deploy deterministic deployment proxy on l2 (expected: $expected, actual $l2_actual)"
    exit 1
fi
```
