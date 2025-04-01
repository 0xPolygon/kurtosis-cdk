# Fast Iteration Cycle with Kurtosis

[Kurtosis](https://github.com/kurtosis-tech/kurtosis/) is a fantastic tool for deploying blockchain devnets. It hides all the complexity of the setup and makes it easier to spin up reproducible and ephemeral devnets for testing purposes. However, as the stack evolves and the number of components skyrockets, it takes more and more time to deploy the CDK stack. Even minor configuration changes take up to ten minutes to reflect on the local devnet. This inefficiency is not developer-friendly and highlights the need for solutions to streamline the deployment process. We are actively addressing these issues, as improving the user experience is one of our main focuses.

In the meantime, here are some tips and tricks that we have found to be quite effective to iterate faster with Kurtosis.

## Speed up zkevm contract deployment to L1

You may have noticed that it takes around eight to ten minutes to deploy the stack and most of this time is spent deploying the [zkevm contracts](https://github.com/0xPolygonHermez/zkevm-contracts) on L1.

To make the contract deployment faster, we tweaked the L1 local blockchain to have faster slots (`1` second vs `12` seconds on mainnet) and faster finalized epochs (`192` seconds vs `1536` seconds with mainnet defaults). These parameters can be adjusted in `params.yml`, see `l1_seconds_per_slot` and `l1_preset`.

## Only deploy the required components

We have structured the package into distinct component blocks, including the L1, zkevm contract deployment, databases, central/trusted environment, etc. This design allows developers to deploy specific parts of the stack as needed.

For instance, when working on a [cdk node](https://github.com/0xPolygon/cdk) fix, you can leverage Kurtosis effectively by first deploying the entire stack once (perhaps during your morning coffee break). Then, by modifying the `params.yml` file to specify that only the central environment should be re-deployed so that you can run the package multiple times to debug and test your changes quickly. This approach significantly reduces deployment time from ten minutes to just one or two minutes maximum, streamlining your development process.

Here is a quick demo.

1. Deploy the stack for the first time.

```bash
kurtosis clean --all # optional
kurtosis run --enclave cdk --args-file params.yml .
```

2. Make a change to the cdk node, build a local image and update the cdk node image to deploy.

```diff
diff --git a/params.yml b/params.yml
index 5e39acd..ffd03fc 100644
--- a/params.yml
+++ b/params.yml
@@ -59,7 +59,7 @@ args:
   zkevm_prover_image: hermeznetwork/zkevm-prover:v6.0.3-RC20
   zkevm_node_image: hermeznetwork/zkevm-node:v0.7.0
   cdk_validium_node_image: 0xpolygon/cdk-validium-node:0.7.0-cdk
-  cdk_node_image: ghcr.io/0xpolygon/cdk:0.0.16
+  cdk_node_image: local/cdk:0.0.16-fix
   zkevm_da_image: 0xpolygon/cdk-data-availability:0.0.9
   zkevm_contracts_image: leovct/zkevm-contracts # the tag is automatically replaced by the value of /zkevm_rollup_fork_id/
```

3. Deploy the new cdk node component

Since you've changed the cdk node image in `params.yml`, running the package will re-deploy most of the components. To prevent this behavior, you can choose not to deploy the L1, zkevm contracts, and databases. This approach will help you save valuable time.

```diff
diff --git a/params.yml b/params.yml
index 5e39acd..42a24bb 100644
--- a/params.yml
+++ b/params.yml
@@ -3,13 +3,13 @@
 # The deployment process is divided into various stages.
 
 # Deploy local L1.
-deploy_l1: true
+deploy_l1: false
 
 # Deploy zkevm contracts on L1 (and also fund accounts).
-deploy_zkevm_contracts_on_l1: true
+deploy_zkevm_contracts_on_l1: false
 
 # Deploy zkevm node and cdk peripheral databases.
-deploy_databases: true
+deploy_databases: false
 
 # Deploy cdk central/trusted environment.
 deploy_cdk_central_environment: true
```

Then you can deploy the stack for a second time to update the cdk node.

```bash
kurtosis run --enclave cdk --args-file params.yml .
```

Notice that it skips the deployment of some components, as expected.

```bash
Printing a message
Skipping the deployment of a local L1

Printing a message
Skipping the deployment of zkevm contracts on L1

Printing a message
Skipping the deployment of databases
```

This method isn't flawless, as Kurtosis will still deploy components like the sequencer, prover, RPC, and bridge, etc. even if it is not needed. But it is significantly faster than a complete deployment that includes the L1 and zkevm contracts. Moreover, this approach allows you to retain any local modifications you've made to the L1.
