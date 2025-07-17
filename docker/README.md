# Custom Docker Images for Kurtosis CDK

We maintain a suite of custom Docker images tailored specifically for deploying the CDK stack. These images serve various purposes, including hosting distinct zkEVM contracts (each fork tagged separately), adapting the bridge UI to support relative URLs, and applying specific workloads.

## Docker Images

### ZkEVM Contracts

- They are [hosted](https://hub.docker.com/repository/docker/leovct/zkevm-contracts/general) on the Docker Hub.
- They share the same tags as [agglayer/agglayer-contracts](https://github.com/agglayer/agglayer-contracts).
- They have been suffixed with `-fork.<id>` to work properly with Kurtosis CDK. For example, pessimistic tags have been prefixed with `-fork.12`, e.g. the zkevm-contracts tag `v9.0.0-rc.2-pp` corresponds to `leovct/zkevm-contracts:v9.0.0-rc.2-pp-fork.12`.

### ZkEVM Bridge UI

Kurtosis CDK's zkevm bridge UI images are [hosted](https://hub.docker.com/repository/docker/leovct/zkevm-bridge-ui/general) on the Docker Hub.

| zkEVM Bridge UI Tag / Commit                                                                                          | Image                                  |
| --------------------------------------------------------------------------------------------------------------------- | -------------------------------------- |
| [develop@0006445](https://github.com/0xPolygonHermez/zkevm-bridge-ui/commit/0006445e1cace5c4d737523fca44af7f7261e041) | `leovct/zkevm-bridge-ui:multi-network` |

## Custom Docker Images

If you ever need to build these images locally, here's a brief guide.

Provision an Ubuntu/Debian VM.

Switch to admin.

```bash
sudo su
```

Install docker.

```bash
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" |tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt install --yes docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-compose
docker run hello-world
```

Clone the repository.

```bash
mkdir /tmp/kurtosis-cdk
git clone https://github.com/0xPolygon/kurtosis-cdk /tmp/kurtosis-cdk
```

Move to the `docker` folder.

```bash
pushd /tmp/kurtosis-cdk/docker
```

### ZkEVM Contracts

This image contains all the npm dependencies and agglayer contracts compiled for a specific fork id.

Build the `zkevm-contracts` image.

```bash
version="v11.0.0-rc.2"
docker build . \
  --tag local/zkevm-contracts:$version-fork.12 \
  --build-arg AGGLAYER_CONTRACTS_BRANCH=$version \
  --file zkevm-contracts.Dockerfile
```

Check the size of the image.

```bash
$ docker images --filter "reference=local/zkevm-contracts"
REPOSITORY              TAG                   IMAGE ID       CREATED          SIZE
local/zkevm-contracts   v8.0.0-rc.4-fork.12   bdf8225cfa77   7 minutes ago    2.54GB
```

(Optional) Push image to the Docker Hub.

```bash
docker login
docker tag local/zkevm-contracts:$version leovct/zkevm-contracts:$version
docker push leovct/zkevm-contracts:$version
```

### ZkEVM Bridge UI

This image contains an enhanced version of the zkEVM bridge UI with relative URL support enabled.

Build the `zkevm-bridge-ui` image.

```bash
docker build zkevm-bridge-ui \
  --tag local/zkevm-bridge-ui:local \
  --build-arg ZKEVM_BRIDGE_UI_TAG=develop \
  --file zkevm-bridge-ui/zkevm-bridge-ui.Dockerfile
```

Check the size of the image.

```bash
$ docker images --filter "reference=local/zkevm-bridge-ui"
REPOSITORY              TAG     IMAGE ID       CREATED          SIZE
local/zkevm-bridge-ui   local   040905e1cabe   28 seconds ago   377MB
```

### Toolbox

This image contains different tools to interact with blockchains such as `polycli` or `cast`.

| toolbox | polycli | foundry |
| ------- | ------- | ------- |
| 0.0.8   | v0.1.73 | stable  |
| 0.0.9   | v0.1.81 | v1.2.3  |
| 0.0.10  | v0.1.82 | v1.2.3  |

Build the `toolbox` image.

```bash
docker build . \
  --tag local/toolbox:local \
  --build-arg POLYCLI_VERSION="v0.1.82" \
  --build-arg FOUNDRY_VERSION="v1.2.3" \
  --file toolbox.Dockerfile
```

Check the size of the image.

```bash
$ docker images --filter "reference=local/toolbox"
REPOSITORY       TAG    IMAGE ID       CREATED         SIZE
local/toolbox   local   3f85f026aaf9   2 seconds ago   448MB
```

### Status Checker

This is an optional image for the [`status-checker`](https://github.com/0xPolygon/status-checker)
to be used when running `kurtosis-cdk` in offline environments.

Build the `status-checker` image from the `kurtosis-cdk` root directory.

```bash
docker build . \
  --tag local/status-checker:local \
  --file docker/status-checker.Dockerfile

# https://hub.docker.com/r/minhdvu/status-checker
docker buildx build . \
  -t minhdvu/status-checker:v0.2.8 \
  -t minhdvu/status-checker:latest \
  --platform=linux/amd64,linux/arm64 \
  --push \
  --builder=container \
  -f ./docker/status-checker.Dockerfile
```

Check the size of the image.

```bash
$ docker images --filter "reference=local/status-checker"
REPOSITORY             TAG       IMAGE ID       CREATED         SIZE
local/status-checker   local     2554266f5834   9 minutes ago   1.77GB
```
