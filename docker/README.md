# Custom Docker Images for Kurtosis CDK

We maintain a suite of custom Docker images tailored specifically for deploying the CDK stack. These images serve various purposes, including hosting distinct zkEVM contracts (each fork tagged separately), adapting the bridge UI to support relative URLs, and applying specific workloads.

We ensure the continuous availability of our custom Docker images through an automated build process. A [cron](../.github/workflows/docker-image-builder-cron.yml) job is configured to run weekly, automatically triggering the build and push of these images. This ensures that the images are regularly updated with the latest changes and dependencies. Moreover, should immediate updates or manual initiation of the image building process be required, users can access the GitHub UI for manual triggering. Alternatively, the images can be built locally by following the provided guide.

## Local Image Building

If you ever need to build these images locally, here's a brief guide.

### zkEVM Contracts

To build a local image containing all npm dependencies and zkEVM contracts compiled for fork ID 9, follow these steps:

```bash
docker build . \
  --tag local/zkevm-contracts:fork9 \
  --build-arg ZKEVM_CONTRACTS_BRANCH=v6.0.0-rc.1-fork.9 \
  --build-arg POLYCLI_VERSION=main \
  --file zkevm-contracts.Dockerfile
```

```bash
$ docker images --filter "reference=local/zkevm-contracts"
REPOSITORY              TAG       IMAGE ID       CREATED          SIZE
local/zkevm-contracts   fork9     54d894c6a5bd   10 minutes ago   2.3GB
```

Here's a quick reference matrix for mapping fork IDs to branches/releases:

| Fork ID | Branch             |
| ------- | ------------------ |
| fork4   | v1.1.0-fork.4      |
| fork5   | v2.0.0-fork.5      |
| fork6   | v3.0.0-fork.6      |
| fork7   | v4.0.0-fork.7      |
| fork8   | v5.0.1-rc.2-fork.8 |
| fork9   | develop            |

## zkEVM Bridge UI

To build the zkEVM Bridge UI image locally, use the following command:

```bash
docker build zkevm-bridge-ui \
  --tag local/zkevm-bridge-ui:multi-network \
  --build-arg ZKEVM_BRIDGE_UI_TAG=develop \
  --file zkevm-bridge-ui/zkevm-bridge-ui.Dockerfile
```

```bash
$ docker images --filter "reference=local/zkevm-bridge-ui"
REPOSITORY              TAG             IMAGE ID       CREATED          SIZE
local/zkevm-bridge-ui   multi-network   040905e1cabe   28 seconds ago   377MB
```

## Toolbox

To build the toolbox image locally, use the following command:

```bash
docker build . \
  --tag local/toolbox:0.0.1 \
  --build-arg POLYCLI_VERSION=main \
  --file toolbox.Dockerfile
```

```bash
$ docker images --filter "reference=local/toolbox"
REPOSITORY       TAG       IMAGE ID       CREATED         SIZE
local/toolbox   0.0.1     3f85f026aaf9   2 seconds ago   490MB
```
