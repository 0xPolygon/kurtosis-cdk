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

## Specifying stage example

This example script show you how to specify the stages. 

!!! tip
    To run the script, you need to have [yq](https://pypi.org/project/yq/) installed.

```sh
# Disable all deployment steps.
yq -Yi '.deploy_l1 = false' params.yml
yq -Yi '.deploy_zkevm_contracts_on_l1 = false' params.yml
yq -Yi '.deploy_databases = false' params.yml
yq -Yi '.deploy_cdk_central_environment = false' params.yml
yq -Yi '.deploy_cdk_bridge_infra = false' params.yml
yq -Yi '.deploy_zkevm_permissionless_node = false' params.yml

# Deploy L1
yq -Yi '.deploy_l1 = true' params.yml
kurtosis run --enclave cdk-v1 --args-file params.yml .
yq -Yi '.deploy_l1 = false' params.yml # reset
# Perform additional tasks...

# Deploy ZkEVM Contracts on L1
yq -Yi '.deploy_zkevm_contracts_on_l1 = true' params.yml
kurtosis run --enclave cdk-v1 --args-file params.yml --image-download always .
yq -Yi '.deploy_zkevm_contracts_on_l1 = false' params.yml # reset
# Perform additional tasks...

# Deploy ZkEVM Node and CDK Peripheral Databases
yq -Yi '.deploy_databases = true' params.yml
kurtosis run --enclave cdk-v1 --args-file params.yml .
yq -Yi '.deploy_databases = false' params.yml # reset
# Perform additional tasks...

# Deploy CDK Central Environment
yq -Yi '.deploy_cdk_central_environment = true' params.yml
kurtosis run --enclave cdk-v1 --args-file params.yml .
yq -Yi '.deploy_cdk_central_environment = false' params.yml # reset
# Perform additional tasks...

# Deploy CDK Bridge Infrastructure
yq -Yi '.deploy_cdk_bridge_infra = true' params.yml
kurtosis run --enclave cdk-v1 --args-file params.yml .
yq -Yi '.deploy_cdk_bridge_infra = false' params.yml # reset
# Perform additional tasks...

# Deploy ZkEVM Permissionless Node
yq -Yi '.deploy_zkevm_permissionless_node = true' params.yml
kurtosis run --enclave cdk-v1 --args-file params.yml .
yq -Yi '.deploy_zkevm_permissionless_node = false' params.yml # reset
```

