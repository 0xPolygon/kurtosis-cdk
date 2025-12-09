# How to edit zkEVM contracts for Kurtosis CDK

A step-by-step guide to edit the zkEVM Solidity contracts in a Polygon CDK devnet.

This document draws from the following resources:

- [Polygon CDK Kurtosis Package](../README.md)
- [Custom Docker Images for Kurtosis CDK](../docker/README.md)
- [Video guide to the Polygon CDK](https://www.youtube.com/watch?v=6ykNLEhwxIs)

## Goals

- Edit the Solidity code in repo `agglayer-contracts` in file `VerifierRollupHelperMock.sol` in function `verifyProof`.
- Rebuild the `agglayer-contracts` docker image.
- Edit this repo `kurtosis-cdk` to use our new build of `agglayer-contracts`.
- Spin up a Polygon CDK devnet and observe our changes in the active devnet.

# Set up your system

Set up your system as per instructions at [Polygon CDK Kurtosis Package](../README.md):

- Install Docker and Kurtosis.
- Run `./scripts/tool_check.sh`.

If you get an error about an incorrect version of Kurtosis then install the correct version as described in [Kurtosis documentation](https://docs.kurtosis.com/install-historical/).

Spin up a Polygon CDK devnet on your local machine. The process should complete within 10 minutes.

```bash
kurtosis clean --all
kurtosis run --enclave cdk-v1 --args-file params.yml .
```

Feel free to follow [subsequent instructions](../README.md) to play with your devnet.

Let's take a look at the Solidity code we want to change. Attach a shell to `contracts-001` container:

```bash
kurtosis service shell cdk-v1 contracts-001
```

In the attached shell take a peek at the Solidity code for `verifyProof`:

```bash
cat agglayer-contracts/contracts/mocks/VerifierRollupHelperMock.sol
```

You should see

```solidity
// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "../interfaces/IVerifierRollup.sol";

contract VerifierRollupHelperMock is IVerifierRollup {
    function verifyProof(
        bytes32[24] calldata proof,
        uint256[1] memory pubSignals
    ) public pure override returns (bool) {
        return true;
    }
}
```

Exit the attached shell when you're done examining the `contracts-001` container:

```bash
exit
```

Let's observe that proofs are passing verification as expected. Use your preferred method to view the logs for the container `agglayer`. For example, you could use the Docker Desktop graphical interface, or you could follow in a terminal via

```bash
kurtosis service logs cdk-v1 agglayer --follow
```

You should see logs like

```
2024-08-19 15:57:01   2024-08-19T19:57:01.917737Z  INFO agglayer_node::rpc: Successfully settled transaction 0x1935…95d1 => receipt TransactionReceipt { ... }
```

Tear down your devnet after you're done playing:

```bash
kurtosis clean --all
```

# Fetch and edit the docker image `agglayer-contracts`

Clone the repo [`agglayer-contracts`](https://github.com/agglayer/agglayer-contracts). Due to Docker's constraints on copying files from the local build context, it will help us later to clone this repo into a new subdirectory `docker/local-test-agglayer-contracts` of the current repo `kurtosis-cdk`:

```bash
git clone git@github.com:0xPolygonHermez/agglayer-contracts.git docker/local-test-agglayer-contracts
```

Optional: add `docker/local-test-agglayer-contracts` to your `.gitignore` file in repo `kurtosis-cdk` to suppress git messages about the repo you just cloned.

We don't want any nasty surprises, so let's checkout the version of this repo that's currently used in `kurtosis-cdk`:

```bash
cd docker/local-test-agglayer-contracts
git checkout v6.0.0-rc.1-fork.9
```

Open the file `docker/local-test-agglayer-contracts/contracts/mocks/VerifierRollupHelperMock.sol` and make a silly change:

```diff
diff --git a/contracts/mocks/VerifierRollupHelperMock.sol b/contracts/mocks/VerifierRollupHelperMock.sol
index 85e6b91..20e51c4 100644
--- a/contracts/mocks/VerifierRollupHelperMock.sol
+++ b/contracts/mocks/VerifierRollupHelperMock.sol
@@ -9,6 +9,6 @@ contract VerifierRollupHelperMock is IVerifierRollup {
         bytes32[24] calldata proof,
         uint256[1] memory pubSignals
     ) public pure override returns (bool) {
-        return true;
+        return false;
     }
 }
```

This change causes the function `verifyProof` to reject any proof it's given.

# Rebuild the docker image `agglayer-contracts`

Let's modify the repo `kurtosis-cdk` to build the docker image `agglayer-contracts` from your local file system, and then use that new image in the devnet.

You can make the following edits manually, or fetch them from the `edit-contracts-demo` branch of [Espresso's fork of `kurtosis-cdk`](https://github.com/EspressoSystems/kurtosis-cdk/tree/edit-contracts-demo).

Open the file `docker/agglayer-contracts.Dockerfile` and make the following edits:

```diff
diff --git a/docker/agglayer-contracts.Dockerfile b/docker/agglayer-contracts.Dockerfile
index 1a18e9c..531f667 100644
--- a/docker/agglayer-contracts.Dockerfile
+++ b/docker/agglayer-contracts.Dockerfile
@@ -12,10 +12,13 @@ LABEL description="Helper image to deploy zkevm contracts"
 # STEP 1: Download zkevm contracts dependencies and compile contracts.
 ARG ZKEVM_CONTRACTS_BRANCH
 WORKDIR /opt/agglayer-contracts
+
+# TEMPORARY: clone from my local storage instead of github.
+COPY local-test-agglayer-contracts .
+
 # FIX: `npm install` randomly fails with ECONNRESET and ETIMEDOUT errors by installing npm>=10.5.1.
 # https://github.com/npm/cli/releases/tag/v10.5.1
-RUN git clone --branch ${ZKEVM_CONTRACTS_BRANCH} https://github.com/agglayer/agglayer-contracts . \
-  && npm install --global npm@10.6.0 \
+RUN npm install --global npm@10.6.0 \
   && npm install \
   && npx hardhat compile
```

This change tells Docker to build the image `agglayer-contracts` from your new local version of that repo instead of fetching it from github.

Next let's rebuild our edited docker image `agglayer-contracts`. Open a terminal in your repo `kurtosis-cdk`, move to the `docker` directory, and rebuild the image:

```bash
cd docker
docker build . \
 --tag local/agglayer-contracts:v6.0.0-rc.1-fork.9 \
 --build-arg ZKEVM_CONTRACTS_BRANCH=v6.0.0-rc.1-fork.9 \
 --build-arg POLYCLI_VERSION=main \
--build-arg FOUNDRY_VERSION=nightly \
 --file agglayer-contracts.Dockerfile
```

Your new image should now be visible in docker. The command

```bash
docker images --filter "reference=local/agglayer-contracts"
```

should produce output like

```
REPOSITORY              TAG                    IMAGE ID       CREATED          SIZE
local/agglayer-contracts   v6.0.0-rc.1-fork.9     fbd050369e61   22 minutes ago   2.37GB
```

# Spin up a devnet with your new docker image

Let's spin up a new Polygon CDK devnet with your edited docker image `agglayer-contracts`.

Point your devnet to your local docker image. Open the file `params.yml` and change `leovct/agglayer-contracts` to `local/agglayer-contracts`:

```diff
diff --git a/params.yml b/params.yml
index 5293da7..5e451b6 100644
--- a/params.yml
+++ b/params.yml
@@ -55,7 +55,7 @@ args:
   zkevm_da_image: 0xpolygon/cdk-data-availability:0.0.7
   # zkevm_da_image: 0xpolygon/cdk-data-availability:0.0.6

-  zkevm_contracts_image: leovct/agglayer-contracts:v6.0.0-rc.1-fork.9
+  zkevm_contracts_image: local/agglayer-contracts:v6.0.0-rc.1-fork.9

   # agglayer_image: 0xpolygon/agglayer:0.1.3
   agglayer_image: ghcr.io/agglayer/agglayer-rs:main
```

Optional: by default, your devnet disables fancy dashboards. If you want to view your devnet from a fancy dashboard such as Grafana then open the file `params.yml` and ensure that `args.additional_services` includes `"prometheus_grafana"`.

Spin up your devnet! Just as before, move to the root directory of the repo `kurtosis-cdk` and run

```bash
kurtosis run --enclave cdk-v1 --args-file params.yml .
```

Let's verify that our edits to the Solidity code are live on this devnet. Just as before, attach a shell to `contracts-001` container and then peek at the Solidity code for `verifyProof`:

```bash
kurtosis service shell cdk-v1 contracts-001
```

Then in the attached shell do

```bash
cat agglayer-contracts/contracts/mocks/VerifierRollupHelperMock.sol
```

You should see your edits in the live code: `return false` instead of `return true`.

Observe that proofs are failing verification as expected in the logs for docker container `agglayer`. You should see logs like

```
2024-08-19 15:44:21   2024-08-19T19:44:21.884754Z ERROR agglayer_node::rpc: Failed to dry-run the verify_batches_trusted_aggregator for transaction 0x161e…4e01: Contract call reverted with data: 0x09bde339, tx_hash: "0x161e…4e01"
2024-08-19 15:44:21     at crates/agglayer-node/src/rpc/mod.rs:176
2024-08-19 15:44:21
```

Congratulations! You successfully modified the smart contract verifier and observed your change in a live devnet! 🚀
