# Custom Docker Images for Kurtosis CDK

We manage several custom Docker images tailored for deploying the CDK stack. These include containers for hosting various zkEVM contracts (each fork tagged separately), adapting the bridge UI to accommodate relative URLs, and applying workloads. A [cron](../.github/workflows/docker-image-builder-cron.yml) job automatically builds and pushes these images every day.

## Local Image Building

If you ever need to build these images locally, here's a brief guide.

### zkEVM Contracts

To build a local image containing all npm dependencies and zkEVM contracts compiled for fork ID 9, follow these steps:

```bash
docker build . \
  --tag local/zkevm-contracts:fork9 \
  --build-arg ZKEVM_CONTRACTS_BRANCH=develop \
  --build-arg POLYCLI_VERSION=main \
  --file zkevm-contracts.Dockerfile
```

```bash
$ docker images --filter "reference=local/zkevm-contracts"
REPOSITORY              TAG       IMAGE ID       CREATED          SIZE
local/zkevm-contracts   fork8     4bd7c527e919   4 minutes ago    2.32GB
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
  --tag local/zkevm-bridge-ui:0.0.1 \
  --build-arg ZKEVM_BRIDGE_UI_TAG=develop \
  --file zkevm-bridge-ui/zkevm-bridge-ui.Dockerfile
```

```bash
$ docker images --filter "reference=local/zkevm-bridge-ui"
REPOSITORY              TAG       IMAGE ID       CREATED          SIZE
local/zkevm-bridge-ui   0.0.1     447325d3b871   5 minutes ago   379MB
```
