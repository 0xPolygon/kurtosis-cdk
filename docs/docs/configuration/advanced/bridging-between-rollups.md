---
sidebar_position: 2
---

# Bridge Between Multiple Rollups in a Single Kurtosis Enclave

## Introduction

After following [Attaching Multiple Rollups in a Single Kurtosis Enclave](./attaching-multiple-rollups.md), you will have multiple rollups inside single Kurtosis enclave.

This guide will go through bridging assets between these rollups.

### Use Cases

- Teams looking to test cross-rollup bridging

### Testing

If you don't have a running enclave with multiple rollups, follow the [Attaching Multiple Rollups in a Single Kurtosis Enclave](./attaching-multiple-rollups.md) guide.

Assuming you have a functional network with multiple rollups, you can quickly bridge between rollups using `polycli ulxly`.

In Kurtosis CDK, the `bridge-service` has a built-in bridge transaction claimer which will autoclaim valid bridge transactions in the rollup. This particular address requires funds to make these bridge claims.
```bash
kurtosis_enclave_name=cdk

# Fund CDK-Erigon Validium zkevm_l2_claimtxmanager_address
cast send --legacy --value 1ether \
    --rpc-url "$(kurtosis port print $kurtosis_enclave_name cdk-erigon-rpc-001 rpc)" \
    --private-key "12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625" \
    "0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8"

# Fund CDK-Erigon Rollup zkevm_l2_claimtxmanager_address
cast send --legacy --value 1ether \
    --rpc-url "$(kurtosis port print $kurtosis_enclave_name cdk-erigon-rpc-002 rpc)" \
    --private-key "12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625" \
    "0x1a1C53bA714643B53b39D82409915b513349a1ff"

# Fund CDK-Erigon PP zkevm_l2_claimtxmanager_address
cast send --legacy --value 1ether \
    --rpc-url "$(kurtosis port print $kurtosis_enclave_name cdk-erigon-rpc-003 rpc)" \
    --private-key "12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625" \
    "0x1359D1eAf25aADaA04304Ee7EFC5b94C43e0e1D5"
```

Now that the claimer address is funded, we can attempt to bridge from L1 -> L2 first.
But we also need to know the below variables to make the bridge call. We'll grab `combined.json` from the `contracts-001` service for this.

```bash
# Get the contracts-001 service name and uuid
contracts_uuid=$(kurtosis enclave inspect --full-uuids $kurtosis_enclave_name | grep contracts-001 | awk '{print $1}')
contracts_container_name=contracts-001--$contracts_uuid

# Get the deployment details
docker cp $contracts_container_name:/opt/zkevm/combined.json .
l1_bridge_address=$(jq -r '.polygonZkEVMBridgeAddress' combined.json)
```

```bash
# L1 -> CDK-Erigon Validium
l2_eth_address=0xC0FFEE0000000000000000000000000000000000
network_id=1
l1_prefunded_mnemonic="giant issue aisle success illegal bike spike question tent bar rely arctic volcano long crawl hungry vocal artwork sniff fantasy very lucky have athlete"
l1_private_key=$(cast wallet private-key --mnemonic "$l1_prefunded_mnemonic")
l1_rpc_url=http://$(kurtosis port print $kurtosis_enclave_name el-1-geth-lighthouse rpc)

polycli ulxly bridge asset \
    --bridge-address "$l1_bridge_addr" \
    --destination-address "$l2_eth_address" \
    --destination-network "$network_id" \
    --private-key "$l1_private_key" \
    --rpc-url "$l1_rpc_url" \
    --value "100000000000000"
```

Repeat the steps for CDK-Erigon Rollup and PP.
```bash
# L1 -> CDK-Erigon Rollup
l2_eth_address=0xC0FFEE0000000000000000000000000000000000
network_id=2
l1_prefunded_mnemonic="giant issue aisle success illegal bike spike question tent bar rely arctic volcano long crawl hungry vocal artwork sniff fantasy very lucky have athlete"
l1_private_key=$(cast wallet private-key --mnemonic "$l1_prefunded_mnemonic")
l1_rpc_url=http://$(kurtosis port print $kurtosis_enclave_name el-1-geth-lighthouse rpc)

polycli ulxly bridge asset \
    --bridge-address "$l1_bridge_addr" \
    --destination-address "$l2_eth_address" \
    --destination-network "$network_id" \
    --private-key "$l1_private_key" \
    --rpc-url "$l1_rpc_url" \
    --value "100000000000000"
```

```bash
# L1 -> CDK-Erigon PP
l2_eth_address=0xC0FFEE0000000000000000000000000000000000
network_id=3
l1_prefunded_mnemonic="giant issue aisle success illegal bike spike question tent bar rely arctic volcano long crawl hungry vocal artwork sniff fantasy very lucky have athlete"
l1_private_key=$(cast wallet private-key --mnemonic "$l1_prefunded_mnemonic")
l1_rpc_url=http://$(kurtosis port print $kurtosis_enclave_name el-1-geth-lighthouse rpc)

polycli ulxly bridge asset \
    --bridge-address "$l1_bridge_addr" \
    --destination-address "$l2_eth_address" \
    --destination-network "$network_id" \
    --private-key "$l1_private_key" \
    --rpc-url "$l1_rpc_url" \
    --value "100000000000000"
```

You can also check the bridge service url to make sure these bridges are visible and claimable.
```bash
# CDK-Erigon Validium
curl -s $(kurtosis port print $kurtosis_enclave_name zkevm-bridge-service-001 rpc)/bridges/0xC0FFEE0000000000000000000000000000000000 | jq '.'

# CDK-Erigon Rollup
curl -s $(kurtosis port print $kurtosis_enclave_name zkevm-bridge-service-002 rpc)/bridges/0xC0FFEE0000000000000000000000000000000000 | jq '.'

# CDK-Erigon PP
curl -s $(kurtosis port print $kurtosis_enclave_name zkevm-bridge-service-003 rpc)/bridges/0xC0FFEE0000000000000000000000000000000000 | jq '.'
```

These deposits should be autoclaimed. Now once they are claimed on L2, we can bridge them back to L1.
```bash
# CDK-Erigon Validium -> L1
l2_bridge_address=$(jq -r '.polygonZkEVMBridgeAddress' combined.json)
l1_eth_address=0xC0FFEE0000000000000000000000000000000000
l2_private_key="12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"
l2_rpc_url="$(kurtosis port print "$kurtosis_enclave_name" cdk-erigon-rpc-001 rpc)"

polycli ulxly bridge asset \
    --bridge-address "$l2_bridge_addr" \
    --destination-address "$l1_eth_address" \
    --destination-network 0 \
    --private-key "$l2_private_key" \
    --rpc-url "$l2_rpc_url" \
    --value "10000000"
```

Similarly for Rollup,
```bash
# CDK-Erigon Rollup -> L1
l2_bridge_address=$(jq -r '.polygonZkEVMBridgeAddress' combined.json)
l1_eth_address=0xC0FFEE0000000000000000000000000000000000
l2_private_key="12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"
l2_rpc_url="$(kurtosis port print "$kurtosis_enclave_name" cdk-erigon-rpc-002 rpc)"

polycli ulxly bridge asset \
    --bridge-address "$l2_bridge_addr" \
    --destination-address "$l1_eth_address" \
    --destination-network 0 \
    --private-key "$l2_private_key" \
    --rpc-url "$l2_rpc_url" \
    --value "10000000"
```

And PP,
```bash
# CDK-Erigon PP -> L1
l2_bridge_address=$(jq -r '.polygonZkEVMBridgeAddress' combined.json)
l1_eth_address=0xC0FFEE0000000000000000000000000000000000
l2_private_key="12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"
l2_rpc_url="$(kurtosis port print "$kurtosis_enclave_name" cdk-erigon-rpc-003 rpc)"

polycli ulxly bridge asset \
    --bridge-address "$l2_bridge_addr" \
    --destination-address "$l1_eth_address" \
    --destination-network 0 \
    --private-key "$l2_private_key" \
    --rpc-url "$l2_rpc_url" \
    --value "10000000"
```

Again, check these deposits to L1 become claimable after some time.
```bash
# CDK-Erigon Validium
curl -s $(kurtosis port print $kurtosis_enclave_name zkevm-bridge-service-001 rpc)/bridges/0xC0FFEE0000000000000000000000000000000000 | jq '.'

# CDK-Erigon Rollup
curl -s $(kurtosis port print $kurtosis_enclave_name zkevm-bridge-service-002 rpc)/bridges/0xC0FFEE0000000000000000000000000000000000 | jq '.'

# CDK-Erigon PP
curl -s $(kurtosis port print $kurtosis_enclave_name zkevm-bridge-service-003 rpc)/bridges/0xC0FFEE0000000000000000000000000000000000 | jq '.'
```

Then manually trigger the claims on L1, since there is no autoclaimer. Change the necessary variables this time.
**Make sure the deposits are claimable.**
```bash
# CDK-Erigon Validium -> L1
l2_rpc_url="$(kurtosis port print "$kurtosis_enclave_name" cdk-erigon-rpc-001 rpc)"
initial_deposit_count=$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'depositCount()(uint256)')
network_id=1
bridge_service_url=$(kurtosis port print $kurtosis_enclave_name zkevm-bridge-service-001 rpc)

polycli ulxly claim asset \
    --bridge-address "$l1_bridge_addr" \
    --private-key "$l1_private_key" \
    --rpc-url "$l1_rpc_url" \
    --deposit-count "$initial_deposit_count" \
    --deposit-network "$network_id" \
    --bridge-service-url "$bridge_service_url"
```

Same for Rollup,
```bash
# CDK-Erigon Validium -> L1
l2_rpc_url="$(kurtosis port print "$kurtosis_enclave_name" cdk-erigon-rpc-002 rpc)"
initial_deposit_count=$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'depositCount()(uint256)')
network_id=2
bridge_service_url=$(kurtosis port print $kurtosis_enclave_name zkevm-bridge-service-002 rpc)

polycli ulxly claim asset \
    --bridge-address "$l1_bridge_addr" \
    --private-key "$l1_private_key" \
    --rpc-url "$l1_rpc_url" \
    --deposit-count "$initial_deposit_count" \
    --deposit-network "$network_id" \
    --bridge-service-url "$bridge_service_url"
```

And PP,
```bash
# CDK-Erigon Validium -> L1
l2_rpc_url="$(kurtosis port print "$kurtosis_enclave_name" cdk-erigon-rpc-003 rpc)"
initial_deposit_count=$(cast call --rpc-url "$l2_rpc_url" "$l2_bridge_addr" 'depositCount()(uint256)')
network_id=3
bridge_service_url=$(kurtosis port print $kurtosis_enclave_name zkevm-bridge-service-003 rpc)

polycli ulxly claim asset \
    --bridge-address "$l1_bridge_addr" \
    --private-key "$l1_private_key" \
    --rpc-url "$l1_rpc_url" \
    --deposit-count "$initial_deposit_count" \
    --deposit-network "$network_id" \
    --bridge-service-url "$bridge_service_url"
```