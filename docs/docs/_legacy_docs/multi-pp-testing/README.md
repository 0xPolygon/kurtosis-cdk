
```
#!/bin/bash
echo "don't run this!"
exit 1;
```

# Multi Chain PP Test

## Infra Setup

This is an example of a system where there are two PP chains and one
FEP chain attached to the rollup manager. One chain uses a gas token
and the others do not. Between those three chains we're going to
attempt a bunch of bridge scenarios.

To run this stuff you'll want to run most of these commands from
within the kurtosis-cdk repo root.

First we're going to do a Kurtosis run to spin up the networks. If
you're going to run this you *need an SP1 key* in the `net1.yml`
file.

```
kurtosis run --enclave pp --args-file docs/multi-pp-testing/net1.yml .
kurtosis run --enclave pp --args-file docs/multi-pp-testing/net2.yml .
kurtosis run --enclave pp --args-file docs/multi-pp-testing/net3.yml .
```

At this point we should be able to confirm that things look right
for both chains. Recently, it seems like the fork id isn't initially
detected by erigon which is causing the chain not to start up right
away.

```
polycli monitor --rpc-url $(kurtosis port print pp cdk-erigon-rpc-001 rpc)
polycli monitor --rpc-url $(kurtosis port print pp cdk-erigon-rpc-002 rpc)
polycli monitor --rpc-url $(kurtosis port print pp cdk-erigon-rpc-003 rpc)
```

In order to proceed, we'll need to grab the combined files from both
chains. We'll specifically want the create rollup parameters file
from the second chain because we need to know the gas token address.

```
kurtosis service exec pp contracts-001 "cat /opt/output/combined-001.json"  | tail -n +2 | jq '.' > combined-001.json
kurtosis service exec pp contracts-002 "cat /opt/output/combined-002.json"  | tail -n +2 | jq '.' > combined-002.json
kurtosis service exec pp contracts-002 "cat /opt/output-contracts/deployment/v2/create_rollup_parameters.json" | tail -n +2 | jq -r '.gasTokenAddress' > gas-token-address.json
kurtosis service exec pp contracts-003 "cat /opt/output/combined-003.json"  | tail -n +2 | jq '.' > combined-003.json
```

This diagnosis isn't critical, but it's nice to confirm that we are
using a real verifier for the PP networks and mock for the FEP.

```
cast code --rpc-url http://$(kurtosis port print pp el-1-geth-lighthouse rpc) $(cat combined-001.json | jq -r '.verifierAddress')
cast code --rpc-url http://$(kurtosis port print pp el-1-geth-lighthouse rpc) $(cat combined-002.json | jq -r '.verifierAddress')
cast code --rpc-url http://$(kurtosis port print pp el-1-geth-lighthouse rpc) $(cat combined-003.json | jq -r '.verifierAddress')
```

Check that the hash of the verifier is actually the sp1 verifier. It should be f33fc6bc90b5ea5e0272a7ab87d701bdd05ecd78b8111ca4f450eeff1e6df26a

```
kurtosis service exec pp contracts-001 'cat /opt/agglayer-contracts/artifacts/contracts/verifiers/SP1Verifier.sol/SP1Verifier.json' | tail -n +2 | jq -r '.deployedBytecode' | sha256sum
cast code --rpc-url http://$(kurtosis port print pp el-1-geth-lighthouse rpc) $(cat combined-001.json | jq -r '.verifierAddress') | sha256sum
cast code --rpc-url http://$(kurtosis port print pp el-1-geth-lighthouse rpc) $(cat combined-002.json | jq -r '.verifierAddress') | sha256sum
```

The third network here should use a mock verifier and should be different

```
cast code --rpc-url http://$(kurtosis port print pp el-1-geth-lighthouse rpc) $(cat combined-003.json | jq -r '.verifierAddress') | sha256sum
```

It's also worthwhile probably to confirm that the vkey matches!

```
kurtosis service exec pp agglayer "agglayer vkey"
```

Let's make sure both rollups have the same vkey

```
cast call --json --rpc-url http://$(kurtosis port print pp el-1-geth-lighthouse rpc) $(cat combined-001.json | jq -r '.polygonRollupManagerAddress') 'rollupIDToRollupDataV2(uint32 rollupID)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint8,bytes32,bytes32)' 1 | jq '.[11]'
cast call --json --rpc-url http://$(kurtosis port print pp el-1-geth-lighthouse rpc) $(cat combined-001.json | jq -r '.polygonRollupManagerAddress') 'rollupIDToRollupDataV2(uint32 rollupID)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint8,bytes32,bytes32)' 2 | jq '.[11]'
```

At this point, the agglayer config needs to be manually updated for
rollup2. This will add a second entry to the agglayer config. If the
second chain is also pessimistic, this isn't strictly necessary, but
there's no harm in it.

```
kurtosis service exec pp agglayer "sed -i 's/\[proof\-signers\]/2 = \"http:\/\/cdk-erigon-rpc-002:8123\"\n\[proof-signers\]/i' /etc/zkevm/agglayer-config.toml"
kurtosis service exec pp agglayer "sed -i 's/\[proof\-signers\]/3 = \"http:\/\/cdk-erigon-rpc-003:8123\"\n\[proof-signers\]/i' /etc/zkevm/agglayer-config.toml"
kurtosis service stop pp agglayer
kurtosis service start pp agglayer
```

Let's create a clean EOA for receiving bridges so that we can see
things show up. This is a good way to make sure we don't mess things
up by trying to exit more than we've deposited

```
cast wallet new
target_address=0xbecE3a31343c6019CDE0D5a4dF2AF8Df17ebcB0f
target_private_key=0x51caa196504216b1730280feb63ddd8c5ae194d13e57e58d559f1f1dc3eda7c9
```

Let's setup some variables for future use

```
private_key="0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"
eth_address=$(cast wallet address --private-key $private_key)
l1_rpc_url=http://$(kurtosis port print pp el-1-geth-lighthouse rpc)
l2_pp1_url=$(kurtosis port print pp cdk-erigon-rpc-001 rpc)
l2_pp2_url=$(kurtosis port print pp cdk-erigon-rpc-002 rpc)
l2_fep_url=$(kurtosis port print pp cdk-erigon-rpc-003 rpc)
bridge_address=$(cat combined-001.json | jq -r .polygonZkEVMBridgeAddress)
pol_address=$(cat combined-001.json | jq -r .polTokenAddress)
gas_token_address=$(<gas-token-address.json)
l2_pp1b_url=$(kurtosis port print pp zkevm-bridge-service-001 rpc)
l2_pp2b_url=$(kurtosis port print pp zkevm-bridge-service-002 rpc)
l2_fepb_url=$(kurtosis port print pp zkevm-bridge-service-003 rpc)
```

Now let's make sure we have balance everywhere

```
cast balance --ether --rpc-url $l1_rpc_url $eth_address
cast balance --ether --rpc-url $l2_pp1_url $eth_address
cast balance --ether --rpc-url $l2_pp2_url $eth_address
cast balance --ether --rpc-url $l2_fep_url $eth_address
```

## Initial Funding
Let's fund the claim tx manager for both rollups. These addresses come
from the chain configurations (so either input_parser or the args
file). The claim tx manager will automatically perform claims on our
behalf for bridge assets

```
cast send --legacy --value 100ether --rpc-url $l2_pp1_url --private-key $private_key 0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8
cast send --legacy --value 100ether --rpc-url $l2_pp2_url --private-key $private_key 0x93F63c24735f45Cd0266E87353071B64dd86bc05
cast send --legacy --value 100ether --rpc-url $l2_fep_url --private-key $private_key 0x8edC8CE0DB10137d513aB5767ffF13D1c51885a8
```

We should also fund the target address on L1 so that we can use this
key for L1 bridge transfers

```
cast send --value 100ether --rpc-url $l1_rpc_url --private-key $private_key $target_address
```

Let's mint some POL token for testing purposes

```
cast send \
     --rpc-url $l1_rpc_url \
     --private-key $private_key \
     $pol_address \
     'mint(address,uint256)' \
     $eth_address 10000000000000000000000
```

We also need to approve the token so that the bridge can spend it.

```
cast send \
     --rpc-url $l1_rpc_url \
     --private-key $private_key \
     $pol_address \
     'approve(address,uint256)' \
     $bridge_address 10000000000000000000000
```

Let's also mint some of the gas token for our second network

```
cast send \
     --rpc-url $l1_rpc_url \
     --private-key $private_key \
     $gas_token_address \
     'mint(address,uint256)' \
     $eth_address 10000000000000000000000
cast send \
     --rpc-url $l1_rpc_url \
     --private-key $private_key \
     $gas_token_address \
     'approve(address,uint256)' \
     $bridge_address 10000000000000000000000
```

We're also going to mint POL and Gas Token from the target account
for additional test scenarios. The logic here is that we don't want
to send Ether to the target address on L2 because we might risk
withdrawing more than we deposit

```
cast send --rpc-url $l1_rpc_url --private-key $private_key $pol_address 'mint(address,uint256)' $target_address 10000000000000000000000
cast send --rpc-url $l1_rpc_url --private-key $private_key $pol_address 'approve(address,uint256)' $bridge_address 10000000000000000000000

cast send --rpc-url $l1_rpc_url --private-key $private_key $gas_token_address 'mint(address,uint256)' $target_address 10000000000000000000000
cast send --rpc-url $l1_rpc_url --private-key $private_key $gas_token_address 'approve(address,uint256)' $bridge_address 10000000000000000000000
```

We're going to do a little matrix of L1 to L2 bridges here. The idea
is to mix bridges across a few scenarios
- Native vs ERC20
- Bridge Message vs Bridge Asset
- GER Updating

```
dry_run=false
for token_addr in $(cast az) $pol_address $gas_token_address ; do
    for destination_network in 1 2 3 ; do
        for ger_update in "false" "true" ; do
            permit_data="0x"
            value="1000000000000000000"
            if [[ $token_addr == $(cast az) ]]; then
                permit_data="0x$(cat /dev/random | xxd -p | tr -d "\n" | head -c $((RANDOM & ~1)))"
            fi
            polycli ulxly bridge asset \
                    --private-key $private_key \
                    --value $value \
                    --bridge-address $bridge_address \
                    --destination-network $destination_network \
                    --destination-address $target_address \
                    --call-data $permit_data \
                    --rpc-url $l1_rpc_url \
                    --token-address $token_addr \
                    --force-update-root=$ger_update \
                    --dry-run=$dry_run
            polycli ulxly bridge message \
                    --private-key $private_key \
                    --value $value \
                    --bridge-address $bridge_address \
                    --destination-network $destination_network \
                    --destination-address $target_address \
                    --call-data $permit_data \
                    --rpc-url $l1_rpc_url \
                    --force-update-root=$ger_update \
                    --dry-run=$dry_run
        done
    done
done
```

At this point, we should be able to see our bridges in the bridge
service for both chains. Recently, with this setup there has been an
issue with network id detection in the bridge service

```
curl -s $l2_pp1b_url/bridges/$target_address | jq '.'
curl -s $l2_pp2b_url/bridges/$target_address | jq '.'
curl -s $l2_fepb_url/bridges/$target_address | jq '.'
```

Some of the bridges will be claimed already, but some will need to
be claimed manually. Most of the ones that need to be claimed
manually should be `leaf_type` of `1` i.e. a message rather than an
asset.

```
curl -s $l2_pp1b_url/bridges/$target_address | jq '.deposits[] | select(.ready_for_claim) | select(.claim_tx_hash == "")'
curl -s $l2_pp2b_url/bridges/$target_address | jq '.deposits[] | select(.ready_for_claim) | select(.claim_tx_hash == "")'
curl -s $l2_fepb_url/bridges/$target_address | jq '.deposits[] | select(.ready_for_claim) | select(.claim_tx_hash == "")'
```

We should be able to take these commands and then try to claim each
of the deposits. This will print out some errors right now because
it's going to try to claim some deposits that are already claimed

```
polycli ulxly claim-everything \
        --bridge-address $bridge_address \
        --bridge-service-map 1=$l2_pp1b_url \
        --bridge-service-map 2=$l2_pp2b_url \
        --bridge-service-map 3=$l2_fepb_url \
        --rpc-url $l2_pp1_url \
        --destination-address $target_address \
        --private-key $private_key \
        --bridge-limit 100
polycli ulxly claim-everything \
        --bridge-address $bridge_address \
        --bridge-service-map 1=$l2_pp1b_url \
        --bridge-service-map 2=$l2_pp2b_url \
        --bridge-service-map 3=$l2_fepb_url \
        --rpc-url $l2_pp2_url \
        --destination-address $target_address \
        --private-key $private_key \
        --bridge-limit 100
polycli ulxly claim-everything \
        --bridge-address $bridge_address \
        --bridge-service-map 1=$l2_pp1b_url \
        --bridge-service-map 2=$l2_pp2b_url \
        --bridge-service-map 3=$l2_fepb_url \
        --rpc-url $l2_fep_url \
        --destination-address $target_address \
        --private-key $private_key \
        --bridge-limit 100
```

Hopefully at this point everything has been claimed on L2. These
calls should return empty.

```
curl -s $l2_pp1b_url/bridges/$target_address | jq '.deposits[] | select(.ready_for_claim) | select(.claim_tx_hash == "")'
curl -s $l2_pp2b_url/bridges/$target_address | jq '.deposits[] | select(.ready_for_claim) | select(.claim_tx_hash == "")'
curl -s $l2_fepb_url/bridges/$target_address | jq '.deposits[] | select(.ready_for_claim) | select(.claim_tx_hash == "")'
```

Let's see if our balances have grown (all should be non-zero)

```
cast balance --ether --rpc-url $l2_pp1_url $target_address
cast balance --ether --rpc-url $l2_pp2_url $target_address
cast balance --ether --rpc-url $l2_fep_url $target_address
```

Let's check our L2 Pol token balance (all should be non-zero)

```
token_hash=$(cast keccak $(cast abi-encode --packed 'f(uint32,address)' 0 $pol_address))
l2_pol_address=$(cast call --rpc-url $l2_pp1_url  $bridge_address 'tokenInfoToWrappedToken(bytes32)(address)' $token_hash)
cast call --rpc-url $l2_pp1_url $l2_pol_address 'balanceOf(address)(uint256)' $target_address
cast call --rpc-url $l2_pp2_url $l2_pol_address 'balanceOf(address)(uint256)' $target_address
cast call --rpc-url $l2_fep_url $l2_pol_address 'balanceOf(address)(uint256)' $target_address
```

We should also check our gas token balance on all networks. The
first network should have a balance because it's treated as ordinary
token. The second network should have nothing because the bridge
would have been received as a native token.

```
token_hash=$(cast keccak $(cast abi-encode --packed 'f(uint32,address)' 0 $gas_token_address))
l2_gas_address=$(cast call --rpc-url $l2_pp1_url  $bridge_address 'tokenInfoToWrappedToken(bytes32)(address)' $token_hash)
cast call --rpc-url $l2_pp1_url $l2_gas_address 'balanceOf(address)(uint256)' $target_address
cast call --rpc-url $l2_pp2_url $l2_gas_address 'balanceOf(address)(uint256)' $target_address
cast call --rpc-url $l2_fep_url $l2_gas_address 'balanceOf(address)(uint256)' $target_address
```

Similarly, we should confirm that on the second network we have some
wrapped ETH.

```
pp2_weth_address=$(cast call --rpc-url $l2_pp2_url $bridge_address 'WETHToken()(address)')
cast call --rpc-url $l2_pp2_url  $pp2_weth_address 'balanceOf(address)(uint256)' $target_address
```

## Test Bridges

At this point we have enough funds on L2s to start doing some bridge
exits, i.e moving funds out of one rollup into another. It's
important for these tests to use the `target_private_key` to ensure
we don't accidentally try to bridge funds out of L2 that weren't
bridged there initially. This is a completely valid test case, but
it might cause an issue with the agglayer that blocks our tests.

Let's try a native bridge from PP1 back to layer one

```
polycli ulxly bridge asset \
        --private-key $target_private_key \
        --value $(date +%s) \
        --bridge-address $bridge_address \
        --destination-network 0 \
        --destination-address $target_address \
        --force-update-root=true \
        --rpc-url $l2_pp1_url
```

Now let's try a native bridge from PP1 to PP2

```
polycli ulxly bridge asset \
        --private-key $target_private_key \
        --value $(date +%s) \
        --bridge-address $bridge_address \
        --destination-network 2 \
        --destination-address $target_address \
        --force-update-root=true \
        --rpc-url $l2_pp1_url
```

Now let's try a native bridge from PP1 to FEP

```
polycli ulxly bridge asset \
        --private-key $target_private_key \
        --value $(date +%s) \
        --bridge-address $bridge_address \
        --destination-network 3 \
        --destination-address $target_address \
        --force-update-root=true \
        --rpc-url $l2_pp1_url
```

None of these transactions will be claimed automatically. So
let's claim them and make sure that works fine.

```
curl -s $l2_pp1b_url/bridges/$target_address | jq '.deposits[] | select(.ready_for_claim) | select(.claim_tx_hash == "")'
deposit_cnt=0
polycli ulxly claim asset \
        --bridge-address $bridge_address \
        --bridge-service-url $l2_pp1b_url \
        --rpc-url $l1_rpc_url \
        --deposit-count $deposit_cnt \
        --deposit-network 1 \
        --destination-address $target_address \
        --private-key $private_key
```

The details of this particular claim are probably a little weird
looking because it's an L2 to L2 claim. The deposit network is 1
because that's where the bridge originated. We're using the deposit
network's bridge service. And then we're making the claim against
the network 2 RPC. The tricky thing is, the claim tx hash will never
show up in the bridge service for this particular tx now.

```
deposit_cnt=1
polycli ulxly claim asset \
        --bridge-address $bridge_address \
        --bridge-service-url $l2_pp1b_url \
        --rpc-url $l2_pp2_url \
        --deposit-count $deposit_cnt \
        --deposit-network 1 \
        --destination-address $target_address \
        --private-key $private_key

deposit_cnt=2
polycli ulxly claim asset \
        --bridge-address $bridge_address \
        --bridge-service-url $l2_pp1b_url \
        --rpc-url $l2_fep_url \
        --deposit-count $deposit_cnt \
        --deposit-network 1 \
        --destination-address $target_address \
        --private-key $private_key
```

Let's try the same test now, but for PP2. Remember, PP2 is a gas
token network, so when we bridge to other networks it should be
turned into an ERC20 of some kind.

```
polycli ulxly bridge asset \
        --private-key $target_private_key \
        --value $(date +%s) \
        --bridge-address $bridge_address \
        --destination-network 0 \
        --destination-address $target_address \
        --force-update-root=true \
        --rpc-url $l2_pp2_url

polycli ulxly bridge asset \
        --private-key $target_private_key \
        --value $(date +%s) \
        --bridge-address $bridge_address \
        --destination-network 1 \
        --destination-address $target_address \
        --force-update-root=true \
        --rpc-url $l2_pp2_url

polycli ulxly bridge weth \
        --private-key $target_private_key \
        --value $(date +%s) \
        --bridge-address $bridge_address \
        --destination-network 3 \
        --destination-address $target_address \
        --force-update-root=true \
        --token-address $pp2_weth_address \
        --rpc-url $l2_pp2_url
```

Now we should try to claim these transactions again on Layer one and PP1

```
curl -s $l2_pp2b_url/bridges/$target_address | jq '.deposits[] | select(.ready_for_claim) | select(.claim_tx_hash == "")'

deposit_cnt=0
polycli ulxly claim asset \
        --bridge-address $bridge_address \
        --bridge-service-url $l2_pp2b_url \
        --rpc-url $l1_rpc_url \
        --deposit-count $deposit_cnt \
        --deposit-network 2 \
        --destination-address $target_address \
        --private-key $private_key

deposit_cnt=1
polycli ulxly claim asset \
        --bridge-address $bridge_address \
        --bridge-service-url $l2_pp2b_url \
        --rpc-url $l2_pp1_url \
        --deposit-count $deposit_cnt \
        --deposit-network 2 \
        --destination-address $target_address \
        --private-key $private_key

deposit_cnt=2
polycli ulxly claim message \
        --bridge-address $bridge_address \
        --bridge-service-url $l2_pp2b_url \
        --rpc-url $l2_fep_url \
        --deposit-count $deposit_cnt \
        --deposit-network 2 \
        --destination-address $target_address \
        --private-key $private_key

cast call --rpc-url $l1_rpc_url $bridge_address 'depositCount() external view returns (uint256)'
```

There are some more advanced test cases in the init.sh script and
run.sh script in this folder
## State Capture Procedure

```
pushd $(mktemp -d)
mkdir agglayer-storage
docker cp agglayer--f3cc4c8d0bad44be9c0ea8eccedd0da1:/etc/zkevm/storage agglayer-storage/
mkdir cdk-001
docker cp cdk-node-001--bd52b030071a4c438cf82b6c281219e6:/tmp cdk-001/
mkdir cdk-002
docker cp cdk-node-002--3c9a92d0e1aa4259a795d7a60156188c:/tmp cdk-002/
mkdir cdk-003
docker cp cdk-node-003--60ace3d2425e43df8f0da4f8058d97f9:/tmp cdk-003/
kurtosis enclave dump pp

popd
tar caf agglayer-details.tar.xz /tmp/tmp.VKezDefjS6
```

drop table public.gorp_migrations;
drop schema sync cascade;
drop schema mt cascade;
delete from sync.claim where index = '14' and rollup_index = 0 and network_id = 2;
