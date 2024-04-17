# Polygon CDK Kurtosis Package

A [Kurtosis](https://github.com/kurtosis-tech/kurtosis) package that deploys a private, portable, and modular Polygon CDK devnet.

## Getting Started

To begin, you will need to install [Docker](https://docs.docker.com/get-docker/) and [Kurtosis](https://docs.kurtosis.com/install/). You can find a detailed list of requirements [here](https://docs.polygon.technology/cdk/get-started/kurtosis-experimental/quickstart/deploy-stack/#prerequisites).

Then run the following command to deploy the complete CDK stack locally. This process typically takes around ten minutes:

```bash
kurtosis clean --all
kurtosis run --enclave cdk-v1 --args-file params.yml --image-download always .
```

For more information about the CDK stack and setting up Kurtosis, visit our [documentation](https://docs.polygon.technology/cdk/get-started/kurtosis-experimental/overview/) on the Polygon Knowledge Layer.

## Contact

- For technical issues, join our [Discord](https://discord.gg/0xpolygondevs).
- For documentation issues, raise an issue on the published live doc at [our main repo](https://github.com/0xPolygon/polygon-docs).

## License

Copyright (c) 2024 PT Services DMCC

Licensed under either:

- Apache License, Version 2.0, ([LICENSE-APACHE](./LICENSE_APACHE) or http://www.apache.org/licenses/LICENSE-2.0), or
- MIT license ([LICENSE-MIT](./LICENSE-MIT) or http://opensource.org/licenses/MIT)

as your option.

The SPDX license identifier for this project is `MIT` OR `Apache-2.0`.

## Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in the work by you, as defined in the Apache-2.0 license, shall be dual licensed as above, without any additional terms or conditions.
