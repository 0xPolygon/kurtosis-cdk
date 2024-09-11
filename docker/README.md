# Custom Docker Images for Kurtosis CDK

We maintain a suite of custom Docker images tailored specifically for deploying the CDK stack. These images serve various purposes, including hosting distinct zkEVM contracts (each fork tagged separately), adapting the bridge UI to support relative URLs, and applying specific workloads.

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

<details>
<summary>Click to expand</summary>

Build the `zkevm-contracts` image.

```bash
version="v8.0.0-rc.1-fork.12"
docker build . \
  --tag local/zkevm-contracts:$version \
  --build-arg ZKEVM_CONTRACTS_BRANCH=$version \
  --build-arg POLYCLI_VERSION=main \
  --file zkevm-contracts.Dockerfile
```

```bash
$ docker images --filter "reference=local/zkevm-contracts"
REPOSITORY              TAG     IMAGE ID       CREATED          SIZE
local/zkevm-contracts   local   54d894c6a5bd   10 minutes ago   2.3GB
```

From now on, the [leovct/zkevm-contracts](https://hub.docker.com/repository/docker/leovct/zkevm-contracts/general) image tags will follow the same tags as [0xPolygonHermez/zkevm-contracts](https://github.com/0xPolygonHermez/zkevm-contracts).

| Fork ID | zkEVM Contracts Tag / Commit | Image |
| ------- | ---------------------------- | ----- |
| 9-RC1 | [v6.0.0-rc.1-fork.9](https://github.com/0xPolygonHermez/zkevm-contracts/releases/tag/v6.0.0-rc.1-fork.9) | [leovct/zkevm-contracts:v6.0.0-rc.1-fork.9](https://hub.docker.com/layers/leovct/zkevm-contracts/v6.0.0-rc.1-fork.9/images/sha256-6a2e2dde8b15506d18285a203026d1c4f9c64d671e223ff08affacc93fd565fa?context=explore) |
| 11-a5eacc6e | [a5eacc6e](https://github.com/0xPolygonHermez/zkevm-contracts/tree/a5eacc6e51d7456c12efcabdfc1c37457f2219b2) | [leovct/zkevm-contracts:a5eacc6e-fork.11](https://hub.docker.com/layers/leovct/zkevm-contracts/a5eacc6e-fork.11/images/sha256-42d9cb9d2349f245096f15c918001f5e5314623842b02e3af229f8995185ef68?context=repo) |
| 11-RC1 | [v7.0.0-rc.1-fork.10](https://github.com/0xPolygonHermez/zkevm-contracts/commits/v7.0.0-rc.1-fork.10) | [leovct/zkevm-contracts:v7.0.0-rc.1-fork.11](https://hub.docker.com/layers/leovct/zkevm-contracts/v7.0.0-rc.1-fork.11/images/sha256-c29a7bf6c6e03419e3846257d66e4606c2e3b23852b94af409853e67e75b2f36?context=explore) |
| 11-RC2 | [v7.0.0-rc.2-fork.10](https://github.com/0xPolygonHermez/zkevm-contracts/commits/v7.0.0-rc.2-fork.10) | [leovct/zkevm-contracts:v7.0.0-rc.2-fork.11](https://hub.docker.com/layers/leovct/zkevm-contracts/v7.0.0-rc.2-fork.11/images/sha256-8e7322525e4c0b6fd5141987d786bfd3f7fec3b0c1724843d99751df5f26f46e?context=explore) |
| 12-RC1 | [v8.0.0-rc.1-fork.12](https://github.com/0xPolygonHermez/zkevm-contracts/releases/tag/v8.0.0-rc.1-fork.12) | [leovct/zkevm-contracts:v8.0.0-rc.1-fork.12](https://hub.docker.com/layers/leovct/zkevm-contracts/v8.0.0-rc.1-fork.12/images/sha256-2197c0b502b93e77bee36a4b87e318a49c6b97bb74b0aca8a13767ef0e684607?context=repo) |
| 12-RC2 | [v8.0.0-rc.2-fork.12](https://github.com/0xPolygonHermez/zkevm-contracts/releases/tag/v8.0.0-rc.2-fork.12) | [leovct/zkevm-contracts:v8.0.0-rc.2-fork.12](https://hub.docker.com/layers/leovct/zkevm-contracts/v8.0.0-rc.2-fork.12/images/sha256-5d835411ff43efb1008eeede0d25db79f6cb563e86d76b33274bcaebc8f9f7d0?context=repo) |

The following tags are now deprecated:

| Fork ID | Branch                                     |
| ------- | ------------------------------------------ |
| fork4   | `v1.1.0-fork.4`                            |
| fork5   | `v2.0.0-fork.5`                            |
| fork6   | `v3.0.0-fork.6`                            |
| fork7   | `v4.0.0-fork.7`                            |
| fork8   | `v5.0.1-rc.2-fork.8`                       |
| fork9   | `v6.0.0-rc.1-fork.9`                       |
| fork10  | `v7.0.0-rc.1-fork.10`                      |
| fork11  | `a5eacc6e51d7456c12efcabdfc1c37457f2219b2` |
| fork12  | `v8.0.0-rc.1-fork.12`                      |

</details>

### ZkEVM Bridge UI

This image contains an enhanced version of the zkEVM bridge UI with relative URL support enabled.

<details>
<summary>Click to expand</summary>

Build the `zkevm-bridge-ui` image.

```bash
docker build zkevm-bridge-ui \
  --tag local/zkevm-bridge-ui:local \
  --build-arg ZKEVM_BRIDGE_UI_TAG=develop \
  --file zkevm-bridge-ui/zkevm-bridge-ui.Dockerfile
```

```bash
$ docker images --filter "reference=local/zkevm-bridge-ui"
REPOSITORY              TAG     IMAGE ID       CREATED          SIZE
local/zkevm-bridge-ui   local   040905e1cabe   28 seconds ago   377MB
```

</details>

### Toolbox

This image contains different tools to interact with blockchains such as `polycli` or `cast`.

<details>
<summary>Click to expand</summary>

Build the `toolbox` image.

```bash
docker build . \
  --tag local/toolbox:local \
  --build-arg POLYCLI_VERSION=main \
  --file toolbox.Dockerfile
```

```bash
$ docker images --filter "reference=local/toolbox"
REPOSITORY       TAG    IMAGE ID       CREATED         SIZE
local/toolbox   local   3f85f026aaf9   2 seconds ago   490MB
```

</details>
