## Prerequisites

1. Install [Kurtosis](https://docs.kurtosis.com/install/).

2. Install the [Foundry toolchain](https://book.getfoundry.sh/getting-started/installation).

3. Install the [polygon-cli](https://github.com/maticnetwork/polygon-cli.git).

4. Run the following script to check you have the remaining required tools and install where missing.

    ```sh
    curl -s https://raw.githubusercontent.com/0xPolygon/kurtosis-cdk/main/scripts/tool_check.sh | bash
    ```

## MacOS issues

!!! tip "Resolving MacOS issues"
    If you are running MacOS, please follow the [MacOS troubleshooting steps](mac-troubles.md) to help fix issues with the installations, and prior to trying out the RPC calls. 

## Set up 

1. Clone the repo and cd into it.

    ```sh
    git clone https://github.com/kmurphypolygon/kurtosis-cdk.git
    cd kurtosis-cdk
    ```

2. Run the Kurtosis enclave.

    ```
    kurtosis run --enclave cdk-v1 --args-file params.yml --image-download always .
    ```

    This command takes a few minutes to complete and steps up and runs an entire local CDK deployment. 
    
Once set up, we can play around with the test CDK. 

## Simple RPC calls

### Inspect the stack

```sh
kurtosis enclave inspect cdk-v1
```

You should see a long output that starts like this:

```sh
Name:            cdk-v1
UUID:            47d8679066a6
Status:          RUNNING
Creation Time:   Wed, 10 Apr 2024 13:58:13 CEST
Flags:           

========================================= Files Artifacts =========================================
UUID   Name
```

### Check port mapping

To see the port mapping within the `cdk-v1` enclave for the `zkevm-node-rpc` service and the
`trusted-rpc` port, run the following command:

```sh
kurtosis port print cdk-v1 zkevm-node-rpc-001 http-rpc
```

You should see output that looks like this:

```sh
http://127.0.0.1:65240
```

### Set an environment variable

Let's map the output from the previous step to an environment variable that we can use throughout these instructions.

```sh
export ETH_RPC_URL="$(kurtosis port print cdk-v1 zkevm-node-rpc-001 http-rpc)"
```

### Test cast commands

This is the same environment variable that `cast` uses, so you should now be able to run the following command:

```sh
cast block-number
```

You should see something like this:

```sh
890
```

### Pre-funded account

By default, the CDK is configured in test mode, and this means there is some pre-funded ETH in the admin account that has address: `0xE34aaF64b29273B7D567FCFc40544c014EEe9970`.

Check the balance with the following: 

```sh
cast balance --ether 0xE34aaF64b29273B7D567FCFc40544c014EEe9970
```

You should see something like this:

```txt
100000.000000000000000000
```

### Send transaction with cast

```sh
cast send --legacy --private-key 0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625 --value 0.01ether 0x0000000000000000000000000000000000000000
```

### Send transactions with `polygon-cli`

```sh
polycli loadtest --requests 500 --legacy --rpc-url $ETH_RPC_URL --verbosity 700 --rate-limit 5 --mode t --private-key 0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625
polycli loadtest --requests 500 --legacy --rpc-url $ETH_RPC_URL --verbosity 700 --rate-limit 10 --mode t --private-key 0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625
polycli loadtest --requests 500 --legacy --rpc-url $ETH_RPC_URL --verbosity 700 --rate-limit 10 --mode 2 --private-key 0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625
polycli loadtest --requests 500 --legacy --rpc-url $ETH_RPC_URL --verbosity 700 --rate-limit 3 --mode uniswapv3 --private-key 0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625
cast nonce 0xE34aaF64b29273B7D567FCFc40544c014EEe9970
```

### Check the logs

```sh
kurtosis service logs cdk-v1 zkevm-agglayer-001
```

In other cases, if we see an error we might want to get a shell in the
container to be able to poke around.

```sh
kurtosis service shell cdk-v1 zkevm-node-sequencer-001
```

One of the most common ways to check the status of the system is to
make sure that batches are going through the normal progression of
trusted, virtual, and verified:

```sh
cast rpc zkevm_batchNumber
cast rpc zkevm_virtualBatchNumber
cast rpc zkevm_verifiedBatchNumber
```

### Clean up

When everything is done, you might want to clean up with this command which stops everything and deletes it.

```sh
kurtosis clean -a
```

</br>