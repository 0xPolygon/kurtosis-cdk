---
sidebar_position: 1
---

# Overview

This section explains how to customize your Polygon CDK devnet deployment.

## Running With Custom Arguments

You can pass custom arguments using the `--args-file` flag:

```bash
kurtosis run --enclave cdk --args-file params.yml .
```

Alternatively, you can specify arguments directly on the command line:

```bash
kurtosis run --enclave cdk . '{"args": {"verbosity": "debug"}}"'
```

:::warning
Do not combine an args file with on-the-fly arguments as Kurtosis cannot merge parameters from both sources and will use only the on-the-fly arguments.
:::

## Example Configurations

Below are some sample configurations to help you get started. Feel free to copy and adapt these examples to fit your use case. You can find more examples in the `.github/tests/` directory.

### [CDK OP Geth](./examples/cdk-opgeth.md)

Based on [op-geth](https://github.com/ethereum-optimism/op-geth).

Designed for fast, high-throughput deployments and OP Stack familiarity, with native Agglayer integration.

### [CDK Erigon](./examples/cdk-erigon.md)

Based on [cdk-erigon](https://github.com/0xPolygonHermez/cdk-erigon).

Optimized for customization and zk security, it provides native token support, custom gas metering, multiple modes (rollup, validium and sovereign), and extensive configuration options.

### [Observability](./examples/observability.md)

Deploy the default stack with debugging and observability tools.

### [Bridge UI](./examples/bridge-ui.md)

Deploy the [bridge hub API](https://github.com/agglayer/agglayer-bridge-hub-api) and its [dedicated UI](https://github.com/agglayer/agglayer-dev-ui) to easily bridge funds from L1 to L2, and vice-versa in, the browser.
