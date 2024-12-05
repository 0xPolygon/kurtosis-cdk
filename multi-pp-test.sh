#!/bin/bash
echo "dont run this!"
exit 1;

# # Multi Chain PP Test
# To run this stuff you'll want to run most of these commands from within the kurtosis-cdk repo root.

# Start up the networks (the secret file here is the same as the normal file but with an SP1 key)
kurtosis run --enclave pp --args-file .github/tests/fork12-pessimistic-secret.yml .
kurtosis run --enclave pp --args-file .github/tests/attach-second-cdk.yml .

# Grab the combined.json files for future ref
kurtosis service exec pp contracts-001 "cat /opt/zkevm/combined-001.json"  | tail -n +2 | jq '.' > combined-001.json
kurtosis service exec pp contracts-002 "cat /opt/zkevm/combined-002.json"  | tail -n +2 | jq '.' > combined-002.json

# Let's confirm the real verifier was deployed for the first rollup. At this point, I'm just going
cast code --rpc-url http://$(kurtosis port print pp el-1-geth-lighthouse rpc) $(cat combined-001.json | jq -r '.verifierAddress')
cast code --rpc-url http://$(kurtosis port print pp el-1-geth-lighthouse rpc) $(cat combined-002.json | jq -r '.verifierAddress')

# Check that the hash of the verifier is actually the sp1 verifier. It should be f33fc6bc90b5ea5e0272a7ab87d701bdd05ecd78b8111ca4f450eeff1e6df26a
kurtosis service exec pp contracts-001 'cat /opt/zkevm-contracts/artifacts/contracts/verifiers/SP1Verifier.sol/SP1Verifier.json' | tail -n +2 | jq -r '.deployedBytecode' | sha256sum
cast code --rpc-url http://$(kurtosis port print pp el-1-geth-lighthouse rpc) $(cat combined-001.json | jq -r '.verifierAddress') | sha256sum

# At this point, the agglayer config needs to be manually updated for rollup2. This will add a second entry to the agglayer config
# TODO in the future we might as well make this values by default...
kurtosis service exec pp agglayer "sed -i 's/\[proof\-signers\]/2 = \"http:\/\/cdk-erigon-rpc-002:8123\"\n\[proof-signers\]/i' /etc/zkevm/agglayer-config.toml"
kurtosis service stop pp agglayer
kurtosis service start pp agglayer

# At this point we should be able to confirm that things look right for both chains. In particular in rollup 2 we'd want to make sure batches are being verified
polycli monitor --rpc-url $(kurtosis port print pp cdk-erigon-rpc-001 rpc)
polycli monitor --rpc-url $(kurtosis port print pp cdk-erigon-rpc-002 rpc)

# let's create a clean EOA for receiving bridges so that we can see
# things show up. This is a good way to make sure we don't mess things
# up by trying to exit more than we've deposited
cast wallet new
# Successfully created new keypair.
# Address:     0xdfC0482a44ff9A6e56ba8A37Fe5d07d3328431BC
# Private key: 0x5fa61eff44166582c8d6302c1eeeac4165057ed9d53d7786b85d6c65512ebfc3
target_address=0xdfC0482a44ff9A6e56ba8A37Fe5d07d3328431BC
target_private_key=0x5fa61eff44166582c8d6302c1eeeac4165057ed9d53d7786b85d6c65512ebfc3

# Let's setup some variables for future use
private_key="0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"
eth_address=$(cast wallet address --private-key $private_key)
l1_rpc_url=http://$(kurtosis port print pp el-1-geth-lighthouse rpc)
l2_pp_url=$(kurtosis port print pp cdk-erigon-rpc-001 rpc)
l2_fep_url=$(kurtosis port print pp cdk-erigon-rpc-002 rpc)
bridge_address=$(cat combined-001.json | jq -r .polygonZkEVMBridgeAddress)
pol_address=$(cat combined-001.json | jq -r .polTokenAddress)

# Now let's make sure we have balance everywhere
cast balance --ether --rpc-url $l1_rpc_url $eth_address
cast balance --ether --rpc-url $l2_pp_url $eth_address
cast balance --ether --rpc-url $l2_fep_url $eth_address

# Let's fund the claim tx manager for both rollups. These address come from the chain configurations (so either input_parser or the args file)
cast send --legacy --value 100ether --rpc-url $l2_pp_url --private-key $private_key 0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8
cast send --legacy --value 100ether --rpc-url $l2_fep_url --private-key $private_key 0x93F63c24735f45Cd0266E87353071B64dd86bc05

# Let's mint some POL for bridge testing
cast send \
     --rpc-url $l1_rpc_url \
     --private-key $private_key \
     $pol_address \
     'mint(address,uint256)' \
     $eth_address 10000000000000000000000

# We also need to approve
cast send \
     --rpc-url $l1_rpc_url \
     --private-key $private_key \
     $pol_address \
     'approve(address,uint256)' \
     $bridge_address 10000000000000000000000

cast call --rpc-url $l1_rpc_url $bridge_address 'WETHToken()'

# Let's go to madison county
for token_addr in $(cast az) $pol_address ; do
    for destination_network in 1 2 ; do
        for ger_update in "false" "true" ; do
            value="0"
            permit_data="0x"
            if [[ $token_addr == $(cast az) ]]; then
                value="100000000000000000000"
                permit_data="0x$(cat /dev/random | xxd -p | tr -d "\n" | head -c $((RANDOM & ~1)))"
            fi
            polycli ulxly bridge asset \
                    --private-key $private_key \
                    --value $value \
                    --bridge-address $bridge_address \
                    --destination-network $destination_network \
                    --destination-address $target_address \
                    --force-update-root $ger_update \
                    --call-data $permit_data \
                    --rpc-url $l1_rpc_url \
                    --token-address $token_addr
            polycli ulxly bridge message \
                    --private-key $private_key \
                    --value $value \
                    --bridge-address $bridge_address \
                    --destination-network $destination_network \
                    --destination-address $target_address \
                    --force-update-root $ger_update \
                    --call-data $permit_data \
                    --rpc-url $l1_rpc_url
        done
    done
done

# Let's see if our balances have grown (both should be non-zero)
cast balance --ether --rpc-url $l2_pp_url $target_address
cast balance --ether --rpc-url $l2_fep_url $target_address

# Let's check our L2 token balance (both should be non-zero)
token_hash=$(cast keccak $(cast abi-encode --packed 'f(uint32,address)' 0 $pol_address))
l2_pol_address=$(cast call --rpc-url $l2_pp_url  $bridge_address 'tokenInfoToWrappedToken(bytes32)(address)' $token_hash)
cast call --rpc-url $l2_pp_url $l2_pol_address 'balanceOf(address)(uint256)' $target_address
cast call --rpc-url $l2_fep_url $l2_pol_address 'balanceOf(address)(uint256)' $target_address

for token_addr in $(cast az) $l2_pol_address ; do
    for destination_network in 0 2 ; do
        for ger_update in "false" "true" ; do
            value="0"
            permit_data="0x"
            if [[ $token_addr == $(cast az) ]]; then
                value="100000000000000000"
                permit_data="0x$(cat /dev/random | xxd -p | tr -d "\n" | head -c $((RANDOM & ~1)))"
            fi
            polycli ulxly bridge asset \
                    --private-key $target_private_key \
                    --value $value \
                    --bridge-address $bridge_address \
                    --destination-network $destination_network \
                    --destination-address $target_address \
                    --force-update-root $ger_update \
                    --call-data $permit_data \
                    --rpc-url $l2_pp_url \
                    --token-address $token_addr
            polycli ulxly bridge message \
                    --private-key $target_private_key \
                    --value $value \
                    --bridge-address $bridge_address \
                    --destination-network $destination_network \
                    --destination-address $target_address \
                    --force-update-root $ger_update \
                    --call-data $permit_data \
                    --rpc-url $l2_pp_url
        done
    done
done

for token_addr in $(cast az) $l2_pol_address ; do
    for destination_network in 0 1 ; do
        for ger_update in "false" "true" ; do
            value="0"
            permit_data="0x"
            if [[ $token_addr == $(cast az) ]]; then
                value="100000000000000000"
                permit_data="0x$(cat /dev/random | xxd -p | tr -d "\n" | head -c $((RANDOM & ~1)))"
            fi
            polycli ulxly bridge asset \
                    --private-key $target_private_key \
                    --value $value \
                    --bridge-address $bridge_address \
                    --destination-network $destination_network \
                    --destination-address $target_address \
                    --force-update-root $ger_update \
                    --call-data $permit_data \
                    --rpc-url $l2_fep_url \
                    --token-address $token_addr
            polycli ulxly bridge message \
                    --private-key $target_private_key \
                    --value $value \
                    --bridge-address $bridge_address \
                    --destination-network $destination_network \
                    --destination-address $target_address \
                    --force-update-root $ger_update \
                    --call-data $permit_data \
                    --rpc-url $l2_fep_url
        done
    done
done



# At this point, I've encountered the error
# [agglayer] {"timestamp":"2024-11-27T20:18:52.021621Z","level":"WARN","fields":{"message":"Error during certification process of 0x24319d4ef5dda589b80498917cea4a66fd91494993fb391bfe5a02ddda84e674: native execution failed: MissingTokenBalanceProof(TokenInfo { origin_network: NetworkId(0), origin_token_address: 0x0000000000000000000000000000000000000000 })","hash":"0x24319d4ef5dda589b80498917cea4a66fd91494993fb391bfe5a02ddda84e674"},"target":"agglayer_certificate_orchestrator::network_task"}
# [agglayer] {"timestamp":"2024-11-27T20:18:59.020532Z","level":"WARN","fields":{"message":"Certificate 0x24319d4ef5dda589b80498917cea4a66fd91494993fb391bfe5a02ddda84e674 is in error: (native) proof generation error: Missing token balance proof. TokenInfo: TokenInfo { origin_network: NetworkId(0), origin_token_address: 0x0000000000000000000000000000000000000000 }","hash":"0x24319d4ef5dda589b80498917cea4a66fd91494993fb391bfe5a02ddda84e674"},"target":"agglayer_certificate_orchestrator::network_task"}







appleseed_address="0x56c069fd987CEA5A8e03E1c1AEB8089000f13bB6"

cast send --legacy --rpc-url $l1_rpc_url --value 100000000000000000000 --private-key $private_key $appleseed_address
# R0, R1, Native, Force
cast send \
    --legacy \
    --rpc-url $l1_rpc_url \
    --value 100000000000000000000 \
    --private-key $private_key \
    $bridge_address \
    "bridgeAsset(uint32,address,uint256,address,bool,bytes)" \
    1 $appleseed_address 100000000000000000000 $(cast az) true 0x

# R0, R2, Native, Force
cast send \
    --legacy \
    --rpc-url $l1_rpc_url \
    --value 100000000000000000000 \
    --private-key $private_key \
    $bridge_address \
    "bridgeAsset(uint32,address,uint256,address,bool,bytes)" \
    2 $appleseed_address 100000000000000000000 $(cast az) true 0x

function distribute() {

    local mnemonic_index="$1"
    local rpc_url="$2"
    local lxly_bridge_addr="$3"
    local cur_net="$4"

    local dest_net

    local seed_mnemonic="gallery option core excess loyal sing subject hold collect reason entry alpha"

    local mnemonic_index_1=$((2 * mnemonic_index + 1))
    local mnemonic_index_2=$((2 * mnemonic_index + 2))

    local eth_address=$(cast wallet address --mnemonic "$seed_mnemonic" --mnemonic-index $mnemonic_index)
    local eth_address_1=$(cast wallet address --mnemonic "$seed_mnemonic" --mnemonic-index $mnemonic_index_1)
    local eth_address_2=$(cast wallet address --mnemonic "$seed_mnemonic" --mnemonic-index $mnemonic_index_2)

    local balance
    local min_balance_check
    local lxly_bridge_addr

    while true; do
        balance=$(cast balance --rpc-url $rpc_url $eth_address)
        min_balance_check=$(bc <<< "$balance > 1000000000") # should probably have at least 1gwei?
        if [[ $min_balance_check -eq 1 ]]; then
            break
        fi
        sleep 10
    done

    # do some work
    # do some work
    # do some work

    if [[ $cur_net -eq 0 ]]; then
        if [[ $(($RANDOM % 2)) -eq 0 ]]; then
            dest_net=1
        else
            dest_net=2
        fi
    elif [[ $cur_net -eq 1 ]]; then
        if [[ $(($RANDOM % 2)) -eq 0 ]]; then
            dest_net=0
        else
            dest_net=2
        fi
    else
        if [[ $(($RANDOM % 2)) -eq 0 ]]; then
            dest_net=0
        else
            dest_net=1
        fi
    fi

    local is_forced=true
    if [[ $(($RANDOM % 2)) -eq 0 ]]; then
        is_forced=false
    fi

    local bridge_data="0x"
    if [[ $(($RANDOM % 2)) -eq 0 ]]; then
        bridge_data="0x$(cat /dev/random | xxd -p | tr -d "\n" | head -c $((RANDOM & ~1)))"
    fi


    if [[ $(($RANDOM % 2)) -eq 0 ]]; then
        set -x
        cast send \
             --legacy \
             --rpc-url "$rpc_url" \
             --value "$mnemonic_index" \
             --gas-limit 1000000 \
             --mnemonic "$seed_mnemonic" --mnemonic-index "$mnemonic_index" \
             "$lxly_bridge_addr" \
             "bridgeMessage(uint32,address,bool,bytes)" \
             "$dest_net" "0x56c069fd987CEA5A8e03E1c1AEB8089000f13bB6" "$is_forced" "$bridge_data"
        set +x
    else
        set -x
        cast send \
             --legacy \
             --rpc-url "$rpc_url" \
             --value "$mnemonic_index" \
             --gas-limit 1000000 \
             --mnemonic "$seed_mnemonic" --mnemonic-index "$mnemonic_index" \
             "$lxly_bridge_addr" \
             "bridgeAsset(uint32,address,uint256,address,bool,bytes)" \
             "$dest_net" "0x56c069fd987CEA5A8e03E1c1AEB8089000f13bB6" "$mnemonic_index" "$(cast az)" "$is_forced" "$bridge_data"
        set +x
    fi

    # finished
    # finished
    # finished

    balance=$(cast balance --rpc-url $rpc_url $eth_address)

    local gas_price="$(cast gas-price --rpc-url $rpc_url)"
    gas_price=$(bc <<< "$gas_price * 3 / 2") # push the gas price up for faster mining

    local leave_behind=271828
    local dist_value=$(bc <<< "($balance - $leave_behind - (2 * 21000 * $gas_price)) / 2")
    local has_enough=$(bc <<< "$dist_value > (1000000000*21000)") # let's assume we want at least enough for a tx at 1gwei
    if [[ $has_enough -eq 0 ]]; then
        echo "The address $eth_address does not have enough funds. Current balance is $balance and distribute value would be $dist_value" >&2
        exit 1
    fi

    echo "sending $dist_value from $eth_address:$mnemonic_index to $eth_address_1:$mnemonic_index_1 and $eth_address_2:$mnemonic_index_2"
    echo "current balance: $balance"

    cast send --timeout 900 --legacy --mnemonic "$seed_mnemonic" --mnemonic-index "$mnemonic_index" --rpc-url "$rpc_url" --gas-price $gas_price --value $dist_value $eth_address_1 > /dev/null
    cast send --timeout 900 --legacy --mnemonic "$seed_mnemonic" --mnemonic-index "$mnemonic_index" --rpc-url "$rpc_url" --gas-price $gas_price --value $dist_value $eth_address_2 > /dev/null
}

export -f distribute

seq 0 32768 | parallel -j32 distribute {} $l1_rpc_url $bridge_address 0 &> r0-bridge-logs.log &
seq 0 32768 | parallel -j32 distribute {} $l2_pp_url  $bridge_address 1 &> r1-bridge-logs.log &
seq 0 32768 | parallel -j32 distribute {} $l2_fep_url $bridge_address 2 &> r2-bridge-logs.log &

# Check why cdk-node is running hot
sudo /usr/sbin/profile-bpfcc --stack-storage-size 32000 -f -F 199 -p 3770750 100 > cdk-node-folded.out
~/code/FlameGraph/flamegraph.pl --title="CDK Node Profile" cdk-node-folded.out > cdk-node.2.svg

# TODO We still need to run some tests specifically with a gas token network. perhaps this test suite shoudl be updated so there is a third PP network that uses a gas token
