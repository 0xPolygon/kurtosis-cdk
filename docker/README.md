# Custom Docker Images for Kurtosis CDK

We maintain a suite of custom Docker images tailored specifically for deploying the CDK stack. These images serve various purposes, including hosting distinct zkEVM contracts (each fork tagged separately), adapting the bridge UI to support relative URLs, and applying specific workloads.

## Docker Images

### ZkEVM Contracts

- They are [hosted](https://hub.docker.com/repository/docker/leovct/zkevm-contracts/general) on the Docker Hub.
- They share the same tags as [0xPolygonHermez/zkevm-contracts](https://github.com/0xPolygonHermez/zkevm-contracts).
- They have been suffixed with `-fork.<id>` to work properly with Kurtosis CDK. For example, pessimistic tags have been prefixed with `-fork.12`, e.g. the zkevm-contracts tag `v9.0.0-rc.2-pp` corresponds to `leovct/zkevm-contracts:v9.0.0-rc.2-pp-fork.12`.
- Because of some dependency breaking changes with `foundry`, we have introduced patch images. They are not compatible with all the versions of kurtosis-cdk!

  | Patch Version | Foundry Version | Polycli Version | Compatibility with kurtosis-cdk |
  | ------------- | --------------- | --------------- | --------------- |
  | None | [nightly-31dd1f77fd9156d09836486d97963cec7f555343](https://github.com/foundry-rs/foundry/releases/tag/nightly-31dd1f77fd9156d09836486d97963cec7f555343) | [v0.1.64](https://github.com/0xPolygon/polygon-cli/releases/tag/v0.1.64) | <= `v0.2.22` |
  | `patch1` | [nightly-27cabbd6c905b1273a5ed3ba7c10acce90833d76](https://github.com/foundry-rs/foundry/tree/nightly-27cabbd6c905b1273a5ed3ba7c10acce90833d76) | [v0.1.64](https://github.com/0xPolygon/polygon-cli/releases/tag/v0.1.64) | > `v0.2.22` |

### ZkEVM Bridge UI

Kurtosis CDK's zkevm bridge UI images are [hosted](https://hub.docker.com/repository/docker/leovct/zkevm-bridge-ui/general) on the Docker Hub.

| zkEVM Bridge UI Tag / Commit | Image |
| ---------------------------- | ----- |
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

This image contains all the npm dependencies and zkevm contracts compiled for a specific fork id.

> Automate the build process using this CI [workflow](https://github.com/0xPolygon/kurtosis-cdk/actions/workflows/docker-image-builder.yml). Images will be automatically [pushed](https://hub.docker.com/repository/docker/leovct/zkevm-contracts/general) to the Docker Hub.

Build the `zkevm-contracts` image.

```bash
version="v8.0.0-rc.4-fork.12"
docker build . \
  --tag local/zkevm-contracts:$version \
  --build-arg ZKEVM_CONTRACTS_BRANCH=$version \
  --build-arg POLYCLI_VERSION=main \
  --build-arg FOUNDRY_VERSION=nightly \
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

Build the `toolbox` image.

```bash
docker build . \
  --tag local/toolbox:local \
  --build-arg POLYCLI_VERSION=main \
  --build-arg FOUNDRY_VERSION=nightly \
  --file toolbox.Dockerfile
```

Check the size of the image.

```bash
$ docker images --filter "reference=local/toolbox"
REPOSITORY       TAG    IMAGE ID       CREATED         SIZE
local/toolbox   local   3f85f026aaf9   2 seconds ago   490MB
```
