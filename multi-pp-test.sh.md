
```sh
#!/bin/bash
echo "dont run this!"
exit 1;
```

# Multi Chain PP Test

## Infra Setup

This is an example of a system where there are two PP chains
attached to the rollup manager. One chain uses a gas token and the
other does not. Between those two chains we're going to attempt a
bunch of bridge scenarios.

To run this stuff you'll want to run most of these commands from
within the kurtosis-cdk repo root.

First we're going to do a Kurtosis run to spin up both of the
networks. The secret file here is the same as the normal file but
with an SP1 key

```sh
kurtosis run --enclave pp --args-file .github/tests/fork12-pessimistic-secret.yml .
kurtosis run --enclave pp --args-file .github/tests/attach-second-cdk.yml . # TODO investigate issue with first block startup
```

In order to proceed, we'll need to grab the combined files from both
chains. We'll specifically want the create rollup parameters file
from the second chain because we need to know the gas token address.

```sh
kurtosis service exec pp contracts-001 "cat /opt/zkevm/combined-001.json"  | tail -n +2 | jq '.' > combined-001.json
kurtosis service exec pp contracts-002 "cat /opt/zkevm/combined-002.json"  | tail -n +2 | jq '.' > combined-002.json
kurtosis service exec pp contracts-002 "cat /opt/zkevm-contracts/deployment/v2/create_rollup_parameters.json" | tail -n +2 | jq -r '.gasTokenAddress' > gas-token-address.json



cast logs --from-block 0 --to-block 1 --rpc-url https://rpc.cdk12.dev.polygon --address 0x1348947e282138d8f377b467F7D9c2EB0F335d1f 0x7f26b83ff96e1f2b6a682f133852f6798a09c465da95921460cefb3847402498


curl http://127.0.0.1:33725 \
--json '{
    "id": 1,
    "jsonrpc": "2.0",
    "method": "eth_call",
    "params": [
        {
            "chainId": "0x1ce",
            "data": "0xbab161bf",
            "from": "0x0000000000000000000000000000000000000000",
            "input": "0xbab161bf",
            "to": "0xd8886e9D827218a02B8C04323b5550f2F36BC8d5"
        },
        "latest"
    ]
}'
```

This diagnosis isn't critical, but it's nice to confirm that we are
using a real verifier.

```sh
cast code --rpc-url http://$(kurtosis port print pp el-1-geth-lighthouse rpc) $(cat combined-001.json | jq -r '.verifierAddress')
cast code --rpc-url http://$(kurtosis port print pp el-1-geth-lighthouse rpc) $(cat combined-002.json | jq -r '.verifierAddress')
```

Check that the hash of the verifier is actually the sp1 verifier. It should be f33fc6bc90b5ea5e0272a7ab87d701bdd05ecd78b8111ca4f450eeff1e6df26a

```sh
kurtosis service exec pp contracts-001 'cat /opt/zkevm-contracts/artifacts/contracts/verifiers/SP1Verifier.sol/SP1Verifier.json' | tail -n +2 | jq -r '.deployedBytecode' | sha256sum
cast code --rpc-url http://$(kurtosis port print pp el-1-geth-lighthouse rpc) $(cat combined-001.json | jq -r '.verifierAddress') | sha256sum
cast code --rpc-url http://$(kurtosis port print pp el-1-geth-lighthouse rpc) $(cat combined-002.json | jq -r '.verifierAddress') | sha256sum
```

At this point, the agglayer config needs to be manually updated for
rollup2. This will add a second entry to the agglayer config.

```sh
kurtosis service exec pp agglayer "sed -i 's/\[proof\-signers\]/2 = \"http:\/\/cdk-erigon-rpc-002:8123\"\n\[proof-signers\]/i' /etc/zkevm/agglayer-config.toml"
kurtosis service stop pp agglayer
kurtosis service start pp agglayer
```

At this point we should be able to confirm that things look right for both chains.

```sh
polycli monitor --rpc-url $(kurtosis port print pp cdk-erigon-rpc-001 rpc)
polycli monitor --rpc-url $(kurtosis port print pp cdk-erigon-rpc-002 rpc)
```

Let's create a clean EOA for receiving bridges so that we can see
things show up. This is a good way to make sure we don't mess things
up by trying to exit more than we've deposited

```sh
cast wallet new
target_address=0xbecE3a31343c6019CDE0D5a4dF2AF8Df17ebcB0f
target_private_key=0x51caa196504216b1730280feb63ddd8c5ae194d13e57e58d559f1f1dc3eda7c9
```

Let's setup some variables for future use

```sh
private_key="0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"
eth_address=$(cast wallet address --private-key $private_key)
l1_rpc_url=http://$(kurtosis port print pp el-1-geth-lighthouse rpc)
l2_pp1_url=$(kurtosis port print pp cdk-erigon-rpc-001 rpc)
l2_pp2_url=$(kurtosis port print pp cdk-erigon-rpc-002 rpc)
bridge_address=$(cat combined-001.json | jq -r .polygonZkEVMBridgeAddress)
pol_address=$(cat combined-001.json | jq -r .polTokenAddress)
gas_token_address=$(<gas-token-address.json)
l2_pp1b_url=$(kurtosis port print pp zkevm-bridge-service-001 rpc)
l2_pp2b_url=$(kurtosis port print pp zkevm-bridge-service-002 rpc)
```

Now let's make sure we have balance everywhere

```sh
cast balance --ether --rpc-url $l1_rpc_url $eth_address
cast balance --ether --rpc-url $l2_pp1_url $eth_address
cast balance --ether --rpc-url $l2_pp2_url $eth_address
```

## Initial Funding
Let's fund the claim tx manager for both rollups. These address come
from the chain configurations (so either input_parser or the args
file). The claim tx manager will automatically perform claims on our
behalf for bridge assets

```sh
cast send --legacy --value 100ether --rpc-url $l2_pp1_url --private-key $private_key 0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8
cast send --legacy --value 100ether --rpc-url $l2_pp2_url --private-key $private_key 0x93F63c24735f45Cd0266E87353071B64dd86bc05
```

Let's mint some POL token for testing purpsoes

```sh
cast send \
     --rpc-url $l1_rpc_url \
     --private-key $private_key \
     $pol_address \
     'mint(address,uint256)' \
     $eth_address 10000000000000000000000
```

We also need to approve the token so that the bridge can spend it.

```sh
cast send \
     --rpc-url $l1_rpc_url \
     --private-key $private_key \
     $pol_address \
     'approve(address,uint256)' \
     $bridge_address 10000000000000000000000
```

Let's also mint some of the gas token for our second network

```sh
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

At this point, I just want to confirm my understanding of the WETH
Token. My sense is that only the L2 bridge for a network that has a
gas token should have a WETH Token

```sh
cast call --rpc-url $l1_rpc_url $bridge_address 'WETHToken()'
cast call --rpc-url $l2_pp1_url $bridge_address 'WETHToken()'
cast call --rpc-url $l2_pp2_url $bridge_address 'WETHToken()'
```

We're going to do a little matrix of L1 to L2 bridges here. The idea
is to mix bridges across a few scenarios
- Native vs ERC20
- Bridge Message vs Bridge Asset
- GER Updating

```sh
dry_run=false
for token_addr in $(cast az) $pol_address $gas_token_address ; do
    for destination_network in 1 2 ; do
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
service for both chains

```sh
curl -s $l2_pp1b_url/bridges/$target_address | jq '.'
curl -s $l2_pp2b_url/bridges/$target_address | jq '.'
```

Some of the bridges will be claimed already, but some will need to
be claimed manually. Most of the ones that need to be claimed
manually should be `leaf_type` of `1` i.e. a message rather than an
asset.

```sh
curl -s $l2_pp1b_url/bridges/$target_address | jq '.deposits[] | select(.ready_for_claim) | select(.claim_tx_hash == "")'
curl -s $l2_pp2b_url/bridges/$target_address | jq '.deposits[] | select(.ready_for_claim) | select(.claim_tx_hash == "")'
```

We should be able to take these commands and then try to claim each
of the deposits.

```sh
curl -s $l2_pp1b_url/bridges/$target_address | jq -c '.deposits[] | select(.ready_for_claim) | select(.claim_tx_hash == "")' | while read deposit ; do
    polycli ulxly claim message \
            --bridge-address $bridge_address \
            --bridge-service-url $l2_pp1b_url \
            --rpc-url $l2_pp1_url \
            --deposit-count $(echo $deposit | jq -r '.deposit_cnt') \
            --deposit-network $(echo $deposit | jq -r '.orig_net') \
            --destination-address $(echo $deposit | jq -r '.dest_addr') \
            --private-key $private_key
done

curl -s $l2_pp2b_url/bridges/$target_address | jq -c '.deposits[] | select(.ready_for_claim) | select(.claim_tx_hash == "")' | while read deposit ; do
    polycli ulxly claim message \
            --bridge-address $bridge_address \
            --bridge-service-url $l2_pp2b_url \
            --rpc-url $l2_pp2_url \
            --deposit-count $(echo $deposit | jq -r '.deposit_cnt') \
            --deposit-network $(echo $deposit | jq -r '.orig_net') \
            --destination-address $(echo $deposit | jq -r '.dest_addr') \
            --private-key $private_key
done
```

Hopefully at this point everything has been claimed on L2. These
calls should return empty.

```sh
curl -s $l2_pp1b_url/bridges/$target_address | jq '.deposits[] | select(.ready_for_claim) | select(.claim_tx_hash == "")'
curl -s $l2_pp2b_url/bridges/$target_address | jq '.deposits[] | select(.ready_for_claim) | select(.claim_tx_hash == "")'
```

Let's see if our balances have grown (both should be non-zero)

```sh
cast balance --ether --rpc-url $l2_pp1_url $target_address
cast balance --ether --rpc-url $l2_pp2_url $target_address
```

Let's check our L2 Pol token balance (both should be non-zero)

```sh
token_hash=$(cast keccak $(cast abi-encode --packed 'f(uint32,address)' 0 $pol_address))
l2_pol_address=$(cast call --rpc-url $l2_pp1_url  $bridge_address 'tokenInfoToWrappedToken(bytes32)(address)' $token_hash)
cast call --rpc-url $l2_pp1_url $l2_pol_address 'balanceOf(address)(uint256)' $target_address
cast call --rpc-url $l2_pp2_url $l2_pol_address 'balanceOf(address)(uint256)' $target_address
```

We should also check our gas token balance on both networks. The
first network should have a balance because it's treated as ordinary
token. The other network should have nothing because the bridge
would have been received as a native token.

```sh
token_hash=$(cast keccak $(cast abi-encode --packed 'f(uint32,address)' 0 $gas_token_address))
l2_gas_address=$(cast call --rpc-url $l2_pp1_url  $bridge_address 'tokenInfoToWrappedToken(bytes32)(address)' $token_hash)
cast call --rpc-url $l2_pp1_url $l2_gas_address 'balanceOf(address)(uint256)' $target_address
cast call --rpc-url $l2_pp2_url $l2_gas_address 'balanceOf(address)(uint256)' $target_address
```

Similarly, we should confirm that on the second network we have some
wrapped ETH.

```sh
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

```sh
polycli ulxly bridge asset \
        --private-key $target_private_key \
        --value $(date +%s) \
        --bridge-address $bridge_address \
        --destination-network 0 \
        --destination-address $target_address \
        --force-update-root=true \
        --rpc-url $l2_pp1_url
```

Now let's try a native bridge from PP1 back to PP2

```sh
polycli ulxly bridge asset \
        --private-key $target_private_key \
        --value $(date +%s) \
        --bridge-address $bridge_address \
        --destination-network 2 \
        --destination-address $target_address \
        --force-update-root=true \
        --rpc-url $l2_pp1_url
```

Neither of these transactions will be claimed automatically. So
let's claim them and make sure that works fine.

```sh
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

```sh
deposit_cnt=1
polycli ulxly claim asset \
        --bridge-address $bridge_address \
        --bridge-service-url $l2_pp1b_url \
        --rpc-url $l2_pp2_url \
        --deposit-count $deposit_cnt \
        --deposit-network 1 \
        --destination-address $target_address \
        --private-key $private_key
```

Let's try the same test now, but for PP2. Remember, PP2 is a gas
token network, so when we bridge to other networks it should be
turned into an ERC20 of some kind.

```sh
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


curl -s $l2_pp2b_url/bridges/$target_address | jq '.deposits[] | select(.ready_for_claim) | select(.claim_tx_hash == "")'
```

