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
docker build . \
  --tag local/zkevm-contracts:local \
  --build-arg ZKEVM_CONTRACTS_BRANCH=v7.0.0-rc.1-fork.10 \
  --build-arg POLYCLI_VERSION=main \
  --file zkevm-contracts.Dockerfile
```

```bash
$ docker images --filter "reference=local/zkevm-contracts"
REPOSITORY              TAG     IMAGE ID       CREATED          SIZE
local/zkevm-contracts   local   54d894c6a5bd   10 minutes ago   2.3GB
```

Here's a quick reference matrix for mapping fork IDs to branches/releases:

| Fork ID | Branch              |
| ------- | ------------------- |
| fork4   | v1.1.0-fork.4       |
| fork5   | v2.0.0-fork.5       |
| fork6   | v3.0.0-fork.6       |
| fork7   | v4.0.0-fork.7       |
| fork8   | v5.0.1-rc.2-fork.8  |
| fork9   | v6.0.0-rc.1-fork.9  |
| fork10  | v7.0.0-rc.1-fork.10 |
| fork12  | v8.0.0-rc.1-fork.12 |

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
