---
comments: true
---

Rather than executing the deployment process as a monolithic operation, you can break it down into stages and run each stage separately.

### Enable or disable stages

You can enable a stage by setting the boolean value to `true` and disable it by setting it to `false`, in the [`params.yml`](https://github.com/0xPolygon/kurtosis-cdk/blob/main/params.yml) file.

!!! important
    - By default, all stages are executed.

## Deployment stages

Currently, the deployment process includes the following stages:

  1. Deploy Local L1.
  2. Deploy zkEVM contracts on L1.
  3. Deploy zkEVM node and CDK peripheral databases.
  4. Deploy CDK central/trusted environment.
  5. Deploy CDK/bridge infrastructure.
  6. Deploy permissionless node.

## Specifying stages

The example scripts below show you how to deploy the stack to enable various stage permutations. 

!!! tip
    To run the scripts, you need to have [yq](https://pypi.org/project/yq/) installed.

### Disable all deployment steps

```sh
yq -Yi '.deploy_l1 = false' params.yml
yq -Yi '.deploy_zkevm_contracts_on_l1 = false' params.yml
yq -Yi '.deploy_databases = false' params.yml
yq -Yi '.deploy_cdk_central_environment = false' params.yml
yq -Yi '.deploy_cdk_bridge_infra = false' params.yml
yq -Yi '.deploy_zkevm_permissionless_node = false' params.yml
```

### Deploy L1

```sh
yq -Yi '.deploy_l1 = true' params.yml
kurtosis run --enclave cdk-v1 --args-file params.yml .
yq -Yi '.deploy_l1 = false' params.yml # reset
# Perform additional tasks...
```

### Deploy zkEVM contracts on L1

```sh
yq -Yi '.deploy_zkevm_contracts_on_l1 = true' params.yml
kurtosis run --enclave cdk-v1 --args-file params.yml --image-download always .
yq -Yi '.deploy_zkevm_contracts_on_l1 = false' params.yml # reset
# Perform additional tasks...
```

### Deploy zkEVM node and CDK peripheral databases

```sh
yq -Yi '.deploy_databases = true' params.yml
kurtosis run --enclave cdk-v1 --args-file params.yml .
yq -Yi '.deploy_databases = false' params.yml # reset
# Perform additional tasks...
```

### Deploy CDK central environment

```sh
yq -Yi '.deploy_cdk_central_environment = true' params.yml
kurtosis run --enclave cdk-v1 --args-file params.yml .
yq -Yi '.deploy_cdk_central_environment = false' params.yml # reset
# Perform additional tasks...
```

### Deploy CDK bridge infrastructure

```sh
yq -Yi '.deploy_cdk_bridge_infra = true' params.yml
kurtosis run --enclave cdk-v1 --args-file params.yml .
yq -Yi '.deploy_cdk_bridge_infra = false' params.yml # reset
# Perform additional tasks...
```

### Deploy zkEVM permissionless node

```sh
yq -Yi '.deploy_zkevm_permissionless_node = true' params.yml
kurtosis run --enclave cdk-v1 --args-file params.yml .
yq -Yi '.deploy_zkevm_permissionless_node = false' params.yml # reset
```

<br/>