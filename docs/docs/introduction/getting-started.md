---
sidebar_position: 3
---

# Getting Started

Get up and running with the package in just a few steps.

:::info
Make sure you have installed the [required tools](./installation.md)!
:::

## Deploy the Devnet

Let's deploy a local Polygon CDK devnet.

```bash
kurtosis run --enclave cdk github.com/0xPolygon/kurtosis-cdk
```

where `cdk` is the name of the enclave, you can choosse any name you like.

## Inspect the Devnet

First, you will need to figure out which port Kurtosis is using for the L2 RPC. You can get a general feel for the entire network layout by running the following command.

```bash
kurtosis enclave inspect cdk
```

## Retrieve the L2 RPC URL

Let's store the L2 RPC URL in an environment variable for use with `cast`.

```bash
export ETH_RPC_URL=$(kurtosis port print cdk op-el-1-op-geth-op-node-001 rpc)
echo $ETH_RPC_URL
```

:::tip
If you want to get the L1 RPC URL, you can use a similar command:

```bash
kurtosis port print cdk el-1-geth-lighthouse rpc
```

:::

## Query the network

Get the latest block number using cast from the [foundry toolchain](https://github.com/foundry-rs/foundry).

```bash
cast block-number
```

## Send transactions

The admin private key, used to deploy Agglayer contracts on L1, is automatically pre-funded with some ether on L1 and L2. You can check its balance using the following command:

```bash
pk="0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"
cast balance --ether $(cast wallet address --private-key $pk)
```

Let's send some transactions now!

```bash
cast send --private-key $pk --value 0.01ether $(cast address-zero)
```

:::tip
You may want to generate a new wallet and fund it using the admin private key to avoid nonce issues!
:::

Let's send even more transactions using [polycli](https://github.com/0xPolygon/polygon-cli)!

We will use `polycli loadtest` to perform ether transactions and transfer ERC20 tokens between random accounts, as well as execute UniswapV3 swaps. The tool will automatically deploy ERC20 contracts along with the complete [UniswapV3 contract suite](https://docs.uniswap.org/contracts/v3/overview).

```bash
polycli loadtest --private-key $pk --legacy --verbosity 700 --mode t --requests 500 --rate-limit 50 --concurrency 5
polycli loadtest --private-key $pk --legacy --verbosity 700 --mode 2 --requests 500 --rate-limit 10
polycli loadtest --private-key $pk --legacy --verbosity 700 --mode uniswapv3 --requests 500 --rate-limit 3
```

## Check the Logs

Pretty often, you will want to check the output from the service. Here is how you can grab some logs:

```bash
kurtosis service logs cdk agglayer --follow
```

## Get Shell Access

In other cases, if you see an error, you might want to get a shell in the service to be able to poke around.

```bash
kurtosis service shell cdk agglayer
```

## Bridge Ether

:::info
We rely on [bats](https://github.com/bats-core/bats-core), a bash testing framework to run most of our e2e tests. The next steps assume you have it installed.
:::

### Clone the Test Suite

First, clone the [agglayer/e2e](https://github.com/agglayer/e2e) repository.

```bash
git clone https://github.com/agglayer/e2e.git
cd e2e
```

### L1-to-L2 Bridge

Then, run the L1-to-L2 bridge test to bridge some ether from L1 to L2.

```bash
bats --filter 'bridge native ETH from L1 to L2' tests/agglayer/bridges.bats
```

After the tests complete, you should see output similar to:

```bash
The command was successfully executed and returned '0'.
1..1
ok 1 bridge native ETH from L1 to L2
```

### L2-to-L1 Bridge

You can perform the reverse operation by running the L2-to-L1 bridge test.

```bash
bats --filter 'bridge native ETH from L2 to L1' tests/agglayer/bridges.bats
```

After the tests complete, you should see output similar to:

```bash
The command was successfully executed and returned '0'.
1..1
ok 1 bridge native ETH from L2 to L1
```

## Clean Up the Environment

```bash
kurtosis enclave rm --force cdk
```

You're now ready to start exploring and customizing your devnet!

Check out the next sections for configuration options, usage guides, and more advanced workflows.
