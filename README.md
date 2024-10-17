# Polygon CDK Kurtosis Package

A [Kurtosis](https://github.com/kurtosis-tech/kurtosis) package that deploys a private, portable, and modular [Polygon CDK](https://docs.polygon.technology/cdk/) devnet over [Docker](https://www.docker.com/) or [Kubernetes](https://kubernetes.io/).

Specifically, this package will deploy:

1. A local L1 chain, fully customizable with multi-client support, using the [ethereum-package](https://github.com/ethpandaops/ethereum-package).
2. A local L2 chain, using the [Polygon Chain Development Kit](https://docs.polygon.technology/cdk/) (CDK), with customizable components such as sequencer, sequence sender, aggregator, rpc, prover, dac, etc. It will first deploy the [Polygon zkEVM smart contracts](https://github.com/0xPolygonHermez/zkevm-contracts) on the L1 chain before deploying the different components.
3. The [zkEVM bridge](https://github.com/0xPolygonHermez/zkevm-bridge-service) infrastructure to facilitate asset bridging between the L1 and L2 chains, and vice-versa.
4. The [Agglayer](https://github.com/agglayer/agglayer-go), an in-development interoperability protocol, that allows for trustless cross-chain token transfers and message-passing, as well as more complex operations between L2 chains, secured by zk proofs.
5. [Additional services](docs/additional-services.md) such as transaction spammer, monitoring tools, permissionless nodes etc.

> 🚨 This package is currently designed as a **development tool** for testing configurations and scenarios within the Polygon CDK stack. **It is not recommended for long-running or production environments such as testnets or mainnet**. If you need help, you can [reach out to the Polygon team](https://polygon.technology/interest-form) or [talk to an Implementation Partner (IP)](https://ecosystem.polygon.technology/spn/cdk/).

## Table of Contents

- [Getting Started](#getting-started)
- [Supported Configurations](#supported-configurations)
- [Advanced Use Cases](#advanced-use-cases)
- [Contact](#contact)
- [License](#license)
- [Contribution](#contribution)

## Supported Configurations

The package is flexible and supports various configurations for deploying and testing the Polygon CDK stack. The table provided illustrates the different combinations of sequencers and sequence sender/aggregator components that can be used, along with their current support status in Kurtosis.

> The team is actively working on enabling the use cases that are currently not possible.

| Stack | Sequencer | Sequence Sender / Aggregator | Supported by Kurtosis? |
| ----- | --------- | ---------------------------- | ---------------------- |
| New CDK stack | [cdk-erigon](https://github.com/0xPolygonHermez/cdk-erigon) | [cdk-node](https://github.com/0xPolygon/cdk) | ✅ |
| New sequencer with new zkevm stack | [cdk-erigon](https://github.com/0xPolygonHermez/cdk-erigon) | [zkevm-sequence-sender](https://github.com/0xPolygonHermez/zkevm-sequence-sender) + [zkevm-aggregator](https://github.com/0xPolygonHermez/zkevm-aggregator) | ❌ (WIP) - Check the [kurtosis-cdk-erigon](https://github.com/xavier-romero/kurtosis-cdk-erigon) package |
| New sequencer with legacy zkevm stack | [cdk-erigon](https://github.com/0xPolygonHermez/cdk-erigon) | [zkevm-node](https://github.com/0xPolygonHermez/zkevm-node) | ❌ (WIP) |
| Legacy sequencer with new cdk stack | [zkevm-node](https://github.com/0xPolygonHermez/zkevm-node) | [cdk-node](https://github.com/0xPolygon/cdk) | ❌ (WIP) |
| Legacy sequencer with new zkevm stack | [zkevm-node](https://github.com/0xPolygonHermez/zkevm-node) | [zkevm-sequence-sender](https://github.com/0xPolygonHermez/zkevm-sequence-sender) + [zkevm-aggregator](https://github.com/0xPolygonHermez/zkevm-aggregator) | ❌ (WIP) |
| Legacy zkevm stack | [zkevm-node](https://github.com/0xPolygonHermez/zkevm-node) | [zkevm-node](https://github.com/0xPolygonHermez/zkevm-node) | ✅ |

To understand how to configure Kurtosis for these use cases, refer to the [documentation](.github/tests/README.md) and review the test files located in the `.github/tests/` directory.

## Getting Started

### Prerequisites

To begin, you will need to install [Docker](https://docs.docker.com/get-docker/) (>= [v4.27.0](https://docs.docker.com/desktop/release-notes/#4270) for Mac users) and [Kurtosis](https://docs.kurtosis.com/install/).

If you intend to interact with and debug the stack, you may also want to consider a few additional optional tools such as:

- [jq](https://github.com/jqlang/jq)
- [yq](https://pypi.org/project/yq/) (v3)
- [cast](https://book.getfoundry.sh/getting-started/installation)
- [polycli](https://github.com/0xPolygon/polygon-cli)

### Deploy

Once that is good and installed on your system, you can run the following command to deploy the complete CDK stack locally. This process typically takes around eight to ten minutes.

```bash
kurtosis run --enclave cdk github.com/0xPolygon/kurtosis-cdk
```

The default deployment includes [cdk-erigon](https://github.com/0xPolygonHermez/cdk-erigon) as the sequencer, and [cdk-node](https://github.com/0xPolygon/cdk) functioning as the sequence sender and aggregator. You can verify the default versions of these components and the default fork ID by reviewing input_parser.star. You can check the default versions of the deployed components and the default fork ID by looking at 
[input_parser.star](./input_parser.star).

To make customizations to the CDK environment, clone this repo, make any desired configuration changes, and then run:

```bash
# Delete all stop and clean all currently running enclaves
kurtosis clean --all

# Run this command from the root of the repository to start the network
kurtosis run --enclave cdk .
```

![CDK Erigon Architecture Diagram](./docs/architecture-diagram/cdk-erigon-architecture-diagram.png)

### Interact

Let's do a simple L2 RPC test call.

First, you will need to figure out which port Kurtosis is using for the RPC. You can get a general feel for the entire network layout by running the following command:

```bash
kurtosis enclave inspect cdk
```

That output, while quite useful, might also be a little overwhelming. Let's store the RPC URL in an environment variable.

> You may need to adjust the various commands slightly if you deployed the legacy [zkevm-node](https://github.com/0xPolygonHermez/zkevm-node) as the sequencer. You should target the `zkevm-node-rpc-001` service instead of `cdk-erigon-node-001`.

```bash
export ETH_RPC_URL="$(kurtosis port print cdk cdk-erigon-node-001 rpc)"
```

That is the same environment variable that `cast` uses, so you should now be able to run this command. Note that the steps below will assume you have the [Foundry toolchain](https://book.getfoundry.sh/getting-started/installation) installed.

```bash
cast block-number
```

By default, the CDK is configured in `test` mode, which means there is some pre-funded value in the admin account with address `0xE34aaF64b29273B7D567FCFc40544c014EEe9970`.

```bash
cast balance --ether 0xE34aaF64b29273B7D567FCFc40544c014EEe9970
```

Okay, let’s send some transactions...

```bash
private_key="0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"
cast send --legacy --private-key "$private_key" --value 0.01ether 0x0000000000000000000000000000000000000000
```

Okay, let’s send even more transactions... Note that this step will assume you have [polygon-cli](https://github.com/maticnetwork/polygon-cli) installed.

```bash
polycli loadtest --rpc-url "$ETH_RPC_URL" --legacy --private-key "$private_key" --verbosity 700 --requests 50000 --rate-limit 50 --concurrency 5 --mode t
polycli loadtest --rpc-url "$ETH_RPC_URL" --legacy --private-key "$private_key" --verbosity 700 --requests 500 --rate-limit 10 --mode 2
polycli loadtest --rpc-url "$ETH_RPC_URL" --legacy --private-key "$private_key" --verbosity 700 --requests 500 --rate-limit 3  --mode uniswapv3
```

Pretty often, you will want to check the output from the service. Here is how you can grab some logs:

```bash
kurtosis service logs cdk agglayer --follow
```

In other cases, if you see an error, you might want to get a shell in the service to be able to poke around.

```bash
kurtosis service shell cdk contracts-001
jq . /opt/zkevm/combined.json
```

One of the most common ways to check the status of the system is to make sure that batches are going through the normal progression of [trusted, virtual, and verified](https://docs.polygon.technology/cdk/concepts/transaction-finality/):

```bash
cast rpc zkevm_batchNumber
cast rpc zkevm_virtualBatchNumber
cast rpc zkevm_verifiedBatchNumber
```

If the number of verified batches is increasing, then it means the system works properly.

To access the `zkevm-bridge` user interface, open this URL in your web browser.

```bash
open "$(kurtosis port print cdk zkevm-bridge-proxy-001 web-ui)"
```

When everything is done, you might want to clean up with this command which stops the local devnet and deletes it.

```bash
kurtosis clean --all
```

For more information about the CDK stack, visit the [Polygon Knowledge Layer](https://docs.polygon.technology/cdk/).

## Advanced Use Cases

This section features documentation specifically designed for advanced users, outlining complex operations and techniques.

- How to deploy [additional services](docs/additional-services.md) alongside the CDK stack, such as transaction spammer, monitoring tools, permissionless nodes etc.
- How to [attach multiple CDK chains to the AggLayer](docs/attach-multiple-cdks.md).
- How to use CDK policies ([doc1](docs/cdk-policies/doc1.md) and [doc2](docs/cdk-policies/doc2.md)).
- How to use the different [data availability modes](docs/data-availability-modes.md).
- How to [deploy the stack to an external L1](docs/deploy-using-sepolia.org) such as Sepolia.
- How to [edit the zkevm contracts](docs/edit-contracts.md).
- How to [perform an environment migration](docs/environment-migration.org) with clean copies of the databases.
- How to [iterate and debug quickly](docs/fast-iteration-cycle.md) with Kurtosis.
- How to use zkevm contracts [fork 12](docs/fork12.md).
- How to [integrate a third-party data availability committee](docs/integrate-da.md) (DAC).
- How to [migrate from fork 7 to fork 9](docs/migrate/forkid-7-to-9.md).
- How to [upgrade forks for isolated CDK chains](docs/migrate/upgrade.md).
- How to use a [native token](docs/native-token/native-token.md).
- How to [play with the network](docs/network-ops.org) to introduce latencies.
- How to [set up a permissionless zkevm node](docs/permissionless-zkevm-node.md).
- How to [run a debugger](docs/running-a-debugger/running-a-debugger.org).
- How to work with the [timelock](docs/timelock.org).
- How to [trigger a reorg](docs/trigger-a-reorg/trigger-a-reorg.md).

## Contact

- For technical issues, join our [Discord](https://discord.gg/0xpolygonrnd).
- For documentation issues, raise an issue on the published live doc at [our main repo](https://github.com/0xPolygon/polygon-docs).

## License

Copyright (c) 2024 PT Services DMCC

Licensed under either:

- Apache License, Version 2.0, ([LICENSE-APACHE](./LICENSE-APACHE) or <http://www.apache.org/licenses/LICENSE-2.0>), or
- MIT license ([LICENSE-MIT](./LICENSE-MIT) or <http://opensource.org/licenses/MIT>)

as your option.

The SPDX license identifier for this project is `MIT` OR `Apache-2.0`.

## Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in the work by you, as defined in the Apache-2.0 license, shall be dual licensed as above, without any additional terms or conditions.
