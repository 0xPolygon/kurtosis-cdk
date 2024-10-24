# Custom Docker Images for Kurtosis CDK

We maintain a suite of custom Docker images tailored specifically for deploying the CDK stack. These images serve various purposes, including hosting distinct zkEVM contracts (each fork tagged separately), adapting the bridge UI to support relative URLs, and applying specific workloads.

## Docker Images

### ZkEVM Contracts

> 🚨 From now on, the [leovct/zkevm-contracts](https://hub.docker.com/repository/docker/leovct/zkevm-contracts/general) image tags will follow the same tags as [0xPolygonHermez/zkevm-contracts](https://github.com/0xPolygonHermez/zkevm-contracts).

> **🚨 All images must be suffixed with `-fork.<id>` to work properly with Kurtosis CDK!**

| Fork ID | zkEVM Contracts Tag / Commit | Image |
| ------- | ---------------------------- | ----- |
| 13-RC1 | [v8.1.0-rc.1-fork.13](https://github.com/0xPolygonHermez/zkevm-contracts/tree/v8.1.0-rc.1-fork.13) | x |
| 12-PP-RC2 | [v9.0.0-rc.2-pp](https://github.com/0xPolygonHermez/zkevm-contracts/releases/tag/v9.0.0-rc.2-pp) | [leovct/zkevm-contracts:v9.0.0-rc.2-pp-fork.12](https://hub.docker.com/layers/leovct/zkevm-contracts/v9.0.0-rc.2-pp-fork.12/images/sha256-9cf68f7583029aa0b46463fe39c06310427c7afe55ba3301e2d57133ffbbf5f9?context=repo) |
| 12-PP-RC1 | [v9.0.0-rc.1-pp](https://github.com/0xPolygonHermez/zkevm-contracts/releases/tag/v9.0.0-rc.1-pp) | [leovct/zkevm-contracts:v9.0.0-rc.1-pp-fork.12](https://hub.docker.com/layers/leovct/zkevm-contracts/v9.0.0-rc.1-pp-fork.12/images/sha256-73fe48df04cb3cb631c2f5cd852c878b668ca49a477fe98278f2e0128d45b976?context=repo) |
| 12-RC4 | [v8.0.0-rc.4-fork.12](https://github.com/0xPolygonHermez/zkevm-contracts/releases/tag/v8.0.0-rc.4-fork.12) | [leovct/zkevm-contracts:v8.0.0-rc.4-fork.12](https://hub.docker.com/layers/leovct/zkevm-contracts/v8.0.0-rc.4-fork.12/images/sha256-544b2db63c608b851aa1fd9c4d4e28c63f4253e295a487c4140a6392799f336e?context=repo) |
| 12-RC3 | [v8.0.0-rc.3-fork.12](https://github.com/0xPolygonHermez/zkevm-contracts/releases/tag/v8.0.0-rc.3-fork.12) | [leovct/zkevm-contracts:v8.0.0-rc.3-fork.12](https://hub.docker.com/layers/leovct/zkevm-contracts/v8.0.0-rc.3-fork.12/images/sha256-f3e9a34651403f246572823249b5f698b4e5d311478f87a84cbfa11c2d091705?context=repo) |
| 12-RC2 | [v8.0.0-rc.2-fork.12](https://github.com/0xPolygonHermez/zkevm-contracts/releases/tag/v8.0.0-rc.2-fork.12) | [leovct/zkevm-contracts:v8.0.0-rc.2-fork.12](https://hub.docker.com/layers/leovct/zkevm-contracts/v8.0.0-rc.2-fork.12/images/sha256-5d835411ff43efb1008eeede0d25db79f6cb563e86d76b33274bcaebc8f9f7d0?context=repo) |
| 12-RC1 | [v8.0.0-rc.1-fork.12](https://github.com/0xPolygonHermez/zkevm-contracts/releases/tag/v8.0.0-rc.1-fork.12) | [leovct/zkevm-contracts:v8.0.0-rc.1-fork.12](https://hub.docker.com/layers/leovct/zkevm-contracts/v8.0.0-rc.1-fork.12/images/sha256-2197c0b502b93e77bee36a4b87e318a49c6b97bb74b0aca8a13767ef0e684607?context=repo) |
| 11-RC2 | [v7.0.0-rc.2-fork.10](https://github.com/0xPolygonHermez/zkevm-contracts/commits/v7.0.0-rc.2-fork.10) | [leovct/zkevm-contracts:v7.0.0-rc.2-fork.11](https://hub.docker.com/layers/leovct/zkevm-contracts/v7.0.0-rc.2-fork.11/images/sha256-8e7322525e4c0b6fd5141987d786bfd3f7fec3b0c1724843d99751df5f26f46e?context=explore) |
| 11-RC1 | [v7.0.0-rc.1-fork.10](https://github.com/0xPolygonHermez/zkevm-contracts/commits/v7.0.0-rc.1-fork.10) | [leovct/zkevm-contracts:v7.0.0-rc.1-fork.11](https://hub.docker.com/layers/leovct/zkevm-contracts/v7.0.0-rc.1-fork.11/images/sha256-c29a7bf6c6e03419e3846257d66e4606c2e3b23852b94af409853e67e75b2f36?context=explore) |
| 9-RC1 | [v6.0.0-rc.1-fork.9](https://github.com/0xPolygonHermez/zkevm-contracts/releases/tag/v6.0.0-rc.1-fork.9) | [leovct/zkevm-contracts:v6.0.0-rc.1-fork.9](https://hub.docker.com/layers/leovct/zkevm-contracts/v6.0.0-rc.1-fork.9/images/sha256-6a2e2dde8b15506d18285a203026d1c4f9c64d671e223ff08affacc93fd565fa?context=explore) |

The following images are deprecated:

| Fork ID | zkEVM Contracts Tag / Commit               | Deprecated Images |
| ------- | ------------------------------------------ | ----------------- |
| fork4   | [v1.1.0-fork.4](https://github.com/0xPolygonHermez/zkevm-contracts/releases/tag/v1.1.0-fork.4) | [leovct/zkevm-contracts:fork4](https://hub.docker.com/layers/leovct/zkevm-contracts/fork4/images/sha256-6eb71326538935778d849c404b65bb1e4d3444182b980da68dcd851d01b0973a?context=repo) |
| fork5   | [v2.0.0-fork.5](https://github.com/0xPolygonHermez/zkevm-contracts/releases/tag/v2.0.0-fork.5) | [leovct/zkevm-contracts:fork5](https://hub.docker.com/layers/leovct/zkevm-contracts/fork5/images/sha256-ee77691afe64473bd475b861b3f2b463c4ccf1eee6f164134624e288a14c7a88?context=repo) |
| fork6   | [v3.0.0-fork.6](https://github.com/0xPolygonHermez/zkevm-contracts/releases/tag/v3.0.0-fork.6) | [leovct/zkevm-contracts:fork6](https://hub.docker.com/layers/leovct/zkevm-contracts/fork6/images/sha256-67555b3c936afca1969908cc3809292de5db2407b17bf8ae7d2bee80a6edd600?context=repo) |
| fork7   | [v4.0.0-fork.7](https://github.com/0xPolygonHermez/zkevm-contracts/releases/tag/v4.0.0-fork.7) | [leovct/zkevm-contracts:fork7](https://hub.docker.com/layers/leovct/zkevm-contracts/fork7/images/sha256-80caad2bc1daddbda16874eaa81a0c7f098b6256a385d2d2d7711ebb0a6b5634?context=repo) |
| fork8   | [v5.0.1-rc.2-fork.8](https://github.com/0xPolygonHermez/zkevm-contracts/releases/tag/v5.0.1-rc.2-fork.8) | [leovct/zkevm-contracts:fork8](https://hub.docker.com/layers/leovct/zkevm-contracts/fork8/images/sha256-2c148382800b6ae205811f4e5445b1f412d00738288d32c0c72ba6dd52292aec?context=repo) |
| fork9   | [v6.0.0-rc.1-fork.9](https://github.com/0xPolygonHermez/zkevm-contracts/releases/tag/v6.0.0-rc.1-fork.9) | [leovct/zkevm-contracts:fork9](https://hub.docker.com/layers/leovct/zkevm-contracts/fork9/images/sha256-4061ef77d36053f3471703bdf57e86f9dbef971730eda2dfb9a1627c1f29e9d9?context=repo) |
| fork10  | [v7.0.0-rc.1-fork.10](https://github.com/0xPolygonHermez/zkevm-contracts/releases/tag/v7.0.0-rc.1-fork.10) | [leovct/zkevm-contracts:fork10](https://hub.docker.com/layers/leovct/zkevm-contracts/fork10/images/sha256-d4e52a843cef12f8f2ab1ff2adad1ab6356782228ed9247aac54663ad2a8b21b?context=repo) |
| fork11  | [a5eacc6](https://github.com/0xPolygonHermez/zkevm-contracts/commit/a5eacc6e51d7456c12efcabdfc1c37457f2219b2) | [leovct/zkevm-contracts:fork11](https://hub.docker.com/layers/leovct/zkevm-contracts/fork11/images/sha256-74d2d996cc9a89aac094b3a77d0ab5b78581ac866f703e7e3b771aa730929fa0?context=repo) |
| fork12  | [v8.0.0-rc.1-fork.12](https://github.com/0xPolygonHermez/zkevm-contracts/releases/tag/v8.0.0-rc.1-fork.12) | [leovct/zkevm-contracts:fork12](https://hub.docker.com/layers/leovct/zkevm-contracts/fork12/images/sha256-8c6028410e6089e99d4696a59032d553bf8a8d9e228dca9a07289c0f6df0674b?context=repo) |

### ZkEVM Bridge UI

| zkEVM Bridge UI Tag / Commit | Image |
| ---------------------------- | ----- |
| [develop@0006445](https://github.com/0xPolygonHermez/zkevm-bridge-ui/commit/0006445e1cace5c4d737523fca44af7f7261e041) | [leovct/zkevm-bridge-ui:multi-network](https://hub.docker.com/layers/leovct/zkevm-bridge-ui/multi-network/images/sha256-14b10a03862ce62d68d6e82a18416fb3f6d9ec5a24f96caf36ca0eb6d8a1b68e?context=repo) |
| [develop@0006445](https://github.com/0xPolygonHermez/zkevm-bridge-ui/commit/0006445e1cace5c4d737523fca44af7f7261e041) + [patch files](./zkevm-bridge-ui/) | [leovct/zkevm-bridge-ui:multi-network-2](https://hub.docker.com/layers/leovct/zkevm-bridge-ui/multi-network-2/images/sha256-958c78ea9f7fd5f4104cd10014ee9b5f359e9695dbdc3fff2f5b041913bf44e2?context=explore) |

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

Build the `zkevm-contracts` image.

```bash
version="v9.0.0-rc.2-pp-fork.12"
docker build . \
  --tag local/zkevm-contracts:$version \
  --build-arg ZKEVM_CONTRACTS_BRANCH=$version \
  --build-arg POLYCLI_VERSION=main \
  --file zkevm-contracts.Dockerfile
```

Check the size of the image.

```bash
$ docker images --filter "reference=local/zkevm-contracts"
REPOSITORY              TAG                      IMAGE ID       CREATED          SIZE
local/zkevm-contracts   v9.0.0-rc.2-pp-fork.12   bdf8225cfa77   7 minutes ago    2.54GB
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
  --file toolbox.Dockerfile
```

Check the size of the image.

```bash
$ docker images --filter "reference=local/toolbox"
REPOSITORY       TAG    IMAGE ID       CREATED         SIZE
local/toolbox   local   3f85f026aaf9   2 seconds ago   490MB
```
