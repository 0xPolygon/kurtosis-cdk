# Data Availability Modes in Kurtosis CDK

Kurtosis CDK supports two modes of data availability for deploying blockchain solutions: `rollup` and `cdk-validium`. The choice between these modes depends on your specific requirements for data availability and security. In the future, we would like to support external DA protocols such as Avail, Celestia and Near.

The two options are:

- `rollup`: Transaction data is stored on-chain on Layer 1 (L1). This approach leverages the security of the main L1 chain (e.g. Ethereum) to ensure data integrity and availability.

> In this mode, the components will run the `zkevm_node_image` and the consensus contract will be `PolygonZkEVMEtrog`.

- `cdk-validium`: Transaction data is stored off-chain using a dedicated CDK Data Availability (DA) layer and a Data Availability Committee (DAC). This approach reduces the load on the main chain and can offer improved scalability and lower costs.

> In this mode, the components will run the `cdk_node_image`, the consensus contract will be `PolygonValidiumEtrog` and the CDK DAC will be deployed and configured.

For more detailed information and technical specifications, refer to the [Polygon Knowledge Layer](https://docs.polygon.technology/cdk/spec/validium-vs-rollup/).
