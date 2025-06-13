---
sidebar_position: 1
---

# FAQ

Find answers to common questions and troubleshooting tips for the package.

If your question isn't answered here, please check the [full documentation](../introduction/overview.md) or open an [issue](https://github.com/0xPolygon/kurtosis-cdk/issues/new).

## Common Questions

### How to get the L1 RPC url?

After starting your environment, run:

```bash
echo "http://$(kurtosis port print cdk el-1-geth-lighthouse rpc)"
```

### How to get the L2 RPC url?

After starting your environment, run:

```bash
kurtosis port print cdk op-el-1-op-geth-op-node-001 rpc
```

This is in the case you deployed a heimdall/bor devnet, otherwise you may need to update the name of the service.

### How to send a transaction to the network?

You can use [cast](https://book.getfoundry.sh/reference/cast/cast-send):

```bash
export ETH_RPC_URL=$(kurtosis port print cdk op-el-1-op-geth-op-node-001 rpc)
pk="0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"
cast send --private-key $pk --value 0.01ether $(cast address-zero)
```

where `0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625` is the admin private key used to deploy Agglater contracts on L1.

### How to find logs or debug services?

To follow logs for a service:

```bash
kurtosis service logs cdk agglayer --follow
```

To open a shell in a service:

```bash
kurtosis service shell cdk agglayer
```

### How to list all the services and ports?

```bash
kurtosis enclave inspect cdk
```

### How to monitor the devnet?

To monitor the devnet, add [Prometheus](https://prometheus.io/) and [Grafana](https://grafana.com/grafana/) as additional services in your configuration:

```yaml title="params.yml"
args:
  additional_services:
    - blockscout
    - observability
    - status_checker
```

After deploying, retrieve the service URLs with:

```bash
kurtosis port print cdk prometheus http
kurtosis port print cdk grafana http
```

Open the printed URLs in your browser to access the metrics and dashboards.

### How to clean up or remove the devnet?

To remove the enclave and all its contents:

```bash
kurtosis enclave rm --force cdk
```

You can also clean all the enclaves using:

```bash
kurtosis clean --all
```

## Common Errors

### Tried pulling image 'xyz' with platform '' but failed

When deploying the devnet on an `arm64` architecture, you may encounter the following issue:

```bash
There was an error validating Starlark code
...
Caused by: Tried pulling image 'jhkimqd/zkevm-contracts:v10.1.0-rc.5-fork.12' with platform '' but failed
...
```

Some of our images are built for `amd64` only. That's why you see a warning like this at the top of the deployment:

```bash
WARNING: Container images with different architecture than expected(arm64):
> jhkimqd/op-deployer:v0.4.0-rc.2 - amd64
> badouralix/curl-jq - amd64
> leovct/e2e:78df008-cdk - amd64
> jhkimqd/zkevm-contracts:v10.1.0-rc.5-fork.12 - amd64
> us-docker.pkg.dev/oplabs-tools-artifacts/images/proxyd:v4.14.2 - amd64
> leovct/toolbox:0.0.8 - amd64
```

**Solution:** Pull the image by specifying the `amd64` platform.

```bash
docker pull --platform linux/amd64 jhkimqd/zkevm-contracts:v10.1.0-rc.5-fork.12
```
