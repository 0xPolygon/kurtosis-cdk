# Kurtosis CDK repo

## Documentation

The Kurtosis docs are live on the Polygon Knowledge Layer here: https://docs.polygon.technology/cdk/get-started/kurtosis-experimental/overview/.

The docs are running on the [mkdocs-material platform](https://squidfunk.github.io/mkdocs-material/) and are imported into the main site.

Follow the steps below to run the Kurtosis docs locally.

### Run docs site locally

#### Prerequisites

1. [Python 3.12](https://www.python.org/downloads/).
2. [`virtualenv`](https://pypi.org/project/virtualenv/): Install using `pip3 install virtualenv`.

#### Setup

1. Clone the repository.
2. `cd` to the root.
3. Run the `scripts/serve_docs.sh` script. You may need to make the script executable: `chmod +x scripts/serve_docs.sh`

```sh
sh scripts/serve_docs.sh
```

The site comes up at http://127.0.0.1:8000/

### Style guide

We are using the [Microsoft Style Guide](https://learn.microsoft.com/en-us/style-guide/welcome/).

### Contributing

1. Add your doc to the `docs` folder and add a menu item in the `config.yml` file.
2. Make sure the site builds correctly.
3. Raise a ticket on the docs team [slack channel](https://slack.com/shortcuts/Ft0613JADARL/ea28ee64d7fcc12fd40b0eb310b583d3), or [JIRA board](https://polygon.atlassian.net/jira/software/projects/DOCS/boards/79) to let us know, and we'll review it and approve.

### Contact

- For technical issues, join our [Discord](https://discord.gg/0xpolygondevs).
- For documentation issues, raise an issue on the published live doc at [our main repo](https://github.com/0xPolygon/polygon-docs).


## License

Copyright (c) 2024 PT Services DMCC

Licensed under either:

- Apache License, Version 2.0, ([[./LICENSE-APACHE][LICENSE-APACHE]] or http://www.apache.org/licenses/LICENSE-2.0), or
- MIT license ([[./LICENSE-MIT][LICENSE-MIT]] or http://opensource.org/licenses/MIT)

as your option.

The SPDX license identifier for this project is ~MIT OR Apache-2.0~.

## Contribution

Unless you explicitly state otherwise, any contribution intentionally
submitted for inclusion in the work by you, as defined in the
Apache-2.0 license, shall be dual licensed as above, without any
additional terms or conditions.
