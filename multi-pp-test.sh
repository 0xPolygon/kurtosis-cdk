#!/bin/bash
echo "dont run this!"
exit 1;

# # Multi Chain PP Test
#
# ## Infra Setup
#
# This is an example of a system where there are two PP chains
# attached to the rollup manager. One chain uses a gas token and the
# other does not. Between those two chains we're going to attempt a
# bunch of bridge scenarios.
#
# To run this stuff you'll want to run most of these commands from
# within the kurtosis-cdk repo root.
#
# First we're going to do a Kurtosis run to spin up both of the
# networks. The secret file here is the same as the normal file but
# with an SP1 key
kurtosis run --enclave pp --args-file .github/tests/fork12-pessimistic-secret.yml .
kurtosis run --enclave pp --args-file .github/tests/attach-second-cdk.yml .

# At this point we should be able to confirm that things look right
# for both chains. Recently, it seems like the fork id isn't initially
# detected by erigon which is causing the chain not to start up right
# away.
polycli monitor --rpc-url $(kurtosis port print pp cdk-erigon-rpc-001 rpc)
polycli monitor --rpc-url $(kurtosis port print pp cdk-erigon-rpc-002 rpc)

# In order to proceed, we'll need to grab the combined files from both
# chains. We'll specifically want the create rollup parameters file
# from the second chain because we need to know the gas token address.
kurtosis service exec pp contracts-001 "cat /opt/zkevm/combined-001.json"  | tail -n +2 | jq '.' > combined-001.json
kurtosis service exec pp contracts-002 "cat /opt/zkevm/combined-002.json"  | tail -n +2 | jq '.' > combined-002.json
kurtosis service exec pp contracts-002 "cat /opt/zkevm-contracts/deployment/v2/create_rollup_parameters.json" | tail -n +2 | jq -r '.gasTokenAddress' > gas-token-address.json

# This diagnosis isn't critical, but it's nice to confirm that we are
# using a real verifier.
cast code --rpc-url http://$(kurtosis port print pp el-1-geth-lighthouse rpc) $(cat combined-001.json | jq -r '.verifierAddress')
cast code --rpc-url http://$(kurtosis port print pp el-1-geth-lighthouse rpc) $(cat combined-002.json | jq -r '.verifierAddress')

# Check that the hash of the verifier is actually the sp1 verifier. It should be f33fc6bc90b5ea5e0272a7ab87d701bdd05ecd78b8111ca4f450eeff1e6df26a
kurtosis service exec pp contracts-001 'cat /opt/zkevm-contracts/artifacts/contracts/verifiers/SP1Verifier.sol/SP1Verifier.json' | tail -n +2 | jq -r '.deployedBytecode' | sha256sum
cast code --rpc-url http://$(kurtosis port print pp el-1-geth-lighthouse rpc) $(cat combined-001.json | jq -r '.verifierAddress') | sha256sum
cast code --rpc-url http://$(kurtosis port print pp el-1-geth-lighthouse rpc) $(cat combined-002.json | jq -r '.verifierAddress') | sha256sum

# It's also worth while probably to confirm that the vkey matches!
kurtosis service exec pp agglayer "agglayer vkey"
cast call --rpc-url http://$(kurtosis port print pp el-1-geth-lighthouse rpc) $(cat combined-001.json | jq -r '.polygonRollupManagerAddress') 'rollupTypeMap(uint32)(address,address,uint64,uint8,bool,bytes32,bytes32)' 1

# Let's make sure both rollups have the same vkey

cast call --rpc-url http://$(kurtosis port print pp el-1-geth-lighthouse rpc) $(cat combined-001.json | jq -r '.polygonRollupManagerAddress') 'rollupIDToRollupDataV2(uint32 rollupID)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint8,bytes32,bytes32)' 1
cast call --rpc-url http://$(kurtosis port print pp el-1-geth-lighthouse rpc) $(cat combined-001.json | jq -r '.polygonRollupManagerAddress') 'rollupIDToRollupDataV2(uint32 rollupID)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint8,bytes32,bytes32)' 2


# At this point, the agglayer config needs to be manually updated for
# rollup2. This will add a second entry to the agglayer config. If the
# second chain is also pessimistic, this isn't strictly necessary, but
# there's no harm in it.
kurtosis service exec pp agglayer "sed -i 's/\[proof\-signers\]/2 = \"http:\/\/cdk-erigon-rpc-002:8123\"\n\[proof-signers\]/i' /etc/zkevm/agglayer-config.toml"
kurtosis service stop pp agglayer
kurtosis service start pp agglayer

# Let's create a clean EOA for receiving bridges so that we can see
# things show up. This is a good way to make sure we don't mess things
# up by trying to exit more than we've deposited
cast wallet new
target_address=0xbecE3a31343c6019CDE0D5a4dF2AF8Df17ebcB0f
target_private_key=0x51caa196504216b1730280feb63ddd8c5ae194d13e57e58d559f1f1dc3eda7c9

# Let's setup some variables for future use
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

# Now let's make sure we have balance everywhere
cast balance --ether --rpc-url $l1_rpc_url $eth_address
cast balance --ether --rpc-url $l2_pp1_url $eth_address
cast balance --ether --rpc-url $l2_pp2_url $eth_address

# ## Initial Funding
# Let's fund the claim tx manager for both rollups. These address come
# from the chain configurations (so either input_parser or the args
# file). The claim tx manager will automatically perform claims on our
# behalf for bridge assets
cast send --legacy --value 100ether --rpc-url $l2_pp1_url --private-key $private_key 0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8
cast send --legacy --value 100ether --rpc-url $l2_pp2_url --private-key $private_key 0x93F63c24735f45Cd0266E87353071B64dd86bc05

# We should also fund the target address on L1 so that we can use this
# key for L1 bridge transfers
cast send --value 100ether --rpc-url $l1_rpc_url --private-key $private_key $target_address

# Let's mint some POL token for testing purpsoes
cast send \
     --rpc-url $l1_rpc_url \
     --private-key $private_key \
     $pol_address \
     'mint(address,uint256)' \
     $eth_address 10000000000000000000000

# We also need to approve the token so that the bridge can spend it.
cast send \
     --rpc-url $l1_rpc_url \
     --private-key $private_key \
     $pol_address \
     'approve(address,uint256)' \
     $bridge_address 10000000000000000000000

# Let's also mint some of the gas token for our second network
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

# We're also going to mint POL and Gas Token from the target account
# for additional test scenarios. The logic here is that we don't want
# to send Ether to the target address on L2 because we might risk
# withdrawing more than we deposit
cast send --rpc-url $l1_rpc_url --private-key $target_private_key $pol_address 'mint(address,uint256)' $target_address 10000000000000000000000
cast send --rpc-url $l1_rpc_url --private-key $target_private_key $pol_address 'approve(address,uint256)' $bridge_address 10000000000000000000000

cast send --rpc-url $l1_rpc_url --private-key $target_private_key $gas_token_address 'mint(address,uint256)' $target_address 10000000000000000000000
cast send --rpc-url $l1_rpc_url --private-key $target_private_key $gas_token_address 'approve(address,uint256)' $bridge_address 10000000000000000000000

# We're going to do a little matrix of L1 to L2 bridges here. The idea
# is to mix bridges across a few scenarios
# - Native vs ERC20
# - Bridge Message vs Bridge Asset
# - GER Updating
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

# At this point, we should be able to see our bridges in the bridge
# service for both chains. Recently, with this setup there has been an
# issue with network id detection in the bridge service
curl -s $l2_pp1b_url/bridges/$target_address | jq '.'
curl -s $l2_pp2b_url/bridges/$target_address | jq '.'

# Some of the bridges will be claimed already, but some will need to
# be claimed manually. Most of the ones that need to be claimed
# manually should be `leaf_type` of `1` i.e. a message rather than an
# asset.
curl -s $l2_pp1b_url/bridges/$target_address | jq '.deposits[] | select(.ready_for_claim) | select(.claim_tx_hash == "")'
curl -s $l2_pp2b_url/bridges/$target_address | jq '.deposits[] | select(.ready_for_claim) | select(.claim_tx_hash == "")'

# We should be able to take these commands and then try to claim each
# of the deposits.
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

# Hopefully at this point everything has been claimed on L2. These
# calls should return empty.
curl -s $l2_pp1b_url/bridges/$target_address | jq '.deposits[] | select(.ready_for_claim) | select(.claim_tx_hash == "")'
curl -s $l2_pp2b_url/bridges/$target_address | jq '.deposits[] | select(.ready_for_claim) | select(.claim_tx_hash == "")'

# Let's see if our balances have grown (both should be non-zero)
cast balance --ether --rpc-url $l2_pp1_url $target_address
cast balance --ether --rpc-url $l2_pp2_url $target_address

# Let's check our L2 Pol token balance (both should be non-zero)
token_hash=$(cast keccak $(cast abi-encode --packed 'f(uint32,address)' 0 $pol_address))
l2_pol_address=$(cast call --rpc-url $l2_pp1_url  $bridge_address 'tokenInfoToWrappedToken(bytes32)(address)' $token_hash)
cast call --rpc-url $l2_pp1_url $l2_pol_address 'balanceOf(address)(uint256)' $target_address
cast call --rpc-url $l2_pp2_url $l2_pol_address 'balanceOf(address)(uint256)' $target_address

# We should also check our gas token balance on both networks. The
# first network should have a balance because it's treated as ordinary
# token. The other network should have nothing because the bridge
# would have been received as a native token.
token_hash=$(cast keccak $(cast abi-encode --packed 'f(uint32,address)' 0 $gas_token_address))
l2_gas_address=$(cast call --rpc-url $l2_pp1_url  $bridge_address 'tokenInfoToWrappedToken(bytes32)(address)' $token_hash)
cast call --rpc-url $l2_pp1_url $l2_gas_address 'balanceOf(address)(uint256)' $target_address
cast call --rpc-url $l2_pp2_url $l2_gas_address 'balanceOf(address)(uint256)' $target_address

# Similarly, we should confirm that on the second network we have some
# wrapped ETH.
pp2_weth_address=$(cast call --rpc-url $l2_pp2_url $bridge_address 'WETHToken()(address)')
cast call --rpc-url $l2_pp2_url  $pp2_weth_address 'balanceOf(address)(uint256)' $target_address


# ## Test Bridges
#
# At this point we have enough funds on L2s to start doing some bridge
# exits, i.e moving funds out of one rollup into another. It's
# important for these tests to use the `target_private_key` to ensure
# we don't accidentally try to bridge funds out of L2 that weren't
# bridged there initially. This is a completely valid test case, but
# it might cause an issue with the agglayer that blocks our tests.
#
# Let's try a native bridge from PP1 back to layer one
polycli ulxly bridge asset \
        --private-key $target_private_key \
        --value $(date +%s) \
        --bridge-address $bridge_address \
        --destination-network 0 \
        --destination-address $target_address \
        --force-update-root=true \
        --rpc-url $l2_pp1_url

# Now let's try a native bridge from PP1 back to PP2
polycli ulxly bridge asset \
        --private-key $target_private_key \
        --value $(date +%s) \
        --bridge-address $bridge_address \
        --destination-network 2 \
        --destination-address $target_address \
        --force-update-root=true \
        --rpc-url $l2_pp1_url

# Neither of these transactions will be claimed automatically. So
# let's claim them and make sure that works fine.
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

# The details of this particular claim are probably a little weird
# looking because it's an L2 to L2 claim. The deposit network is 1
# because that's where the bridge originated. We're using the deposit
# network's bridge service. And then we're making the claim against
# the network 2 RPC. The tricky thing is, the claim tx hash will never
# show up in the bridge service for this particular tx now.
deposit_cnt=1
polycli ulxly claim asset \
        --bridge-address $bridge_address \
        --bridge-service-url $l2_pp1b_url \
        --rpc-url $l2_pp2_url \
        --deposit-count $deposit_cnt \
        --deposit-network 1 \
        --destination-address $target_address \
        --private-key $private_key


# Let's try the same test now, but for PP2. Remember, PP2 is a gas
# token network, so when we bridge to other networks it should be
# turned into an ERC20 of some kind.
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

# Now we should try to claim these transactions again on Layer one and PP1
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

cast call --rpc-url $l1_rpc_url $bridge_address 'depositCount() external view returns (uint256)'


# ## Pict Based Test Scenarios
#
# The goal here is to have some methods for creating more robust
# testing combinations. In theory, we can probably brute force test
# every combination of parameters, but as the number of parameters
# grows, this might become too difficult. I'm using a command like
# this to generate the test cases.
pict lxly.pict /f:json | jq -c '.[] | from_entries' | jq -s > test-scenarios.json

# For the sake of simplicity, I'm going to use the deterministic
# deployer so that I have the same ERC20 address on each chain. Here
# I'm adding some funds to the deterministict deployer address.
cast send --legacy --value 0.1ether --rpc-url $l1_rpc_url --private-key $private_key 0x3fab184622dc19b6109349b94811493bf2a45362
cast send --legacy --value 0.1ether --rpc-url $l2_pp1_url --private-key $private_key 0x3fab184622dc19b6109349b94811493bf2a45362
cast send --legacy --value 0.1ether --rpc-url $l2_pp2_url --private-key $private_key 0x3fab184622dc19b6109349b94811493bf2a45362

# The tx data and address are standard for the deterministict deployer
deterministic_deployer_tx=0xf8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222
deterministic_deployer_addr=0x4e59b44847b379578588920ca78fbf26c0b4956c

cast publish --rpc-url $l1_rpc_url $deterministic_deployer_tx
cast publish --rpc-url $l2_pp1_url $deterministic_deployer_tx
cast publish --rpc-url $l2_pp2_url $deterministic_deployer_tx


salt=0x6a6f686e2068696c6c696172642077617320686572650a000000000000000000
erc_20_bytecode=60806040526040516200143a3803806200143a833981016040819052620000269162000201565b8383600362000036838262000322565b50600462000045828262000322565b5050506200005a82826200007160201b60201c565b505081516020909201919091206006555062000416565b6001600160a01b038216620000cc5760405162461bcd60e51b815260206004820152601f60248201527f45524332303a206d696e7420746f20746865207a65726f206164647265737300604482015260640160405180910390fd5b8060026000828254620000e09190620003ee565b90915550506001600160a01b038216600081815260208181526040808320805486019055518481527fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef910160405180910390a35050565b505050565b634e487b7160e01b600052604160045260246000fd5b600082601f8301126200016457600080fd5b81516001600160401b03808211156200018157620001816200013c565b604051601f8301601f19908116603f01168101908282118183101715620001ac57620001ac6200013c565b81604052838152602092508683858801011115620001c957600080fd5b600091505b83821015620001ed5785820183015181830184015290820190620001ce565b600093810190920192909252949350505050565b600080600080608085870312156200021857600080fd5b84516001600160401b03808211156200023057600080fd5b6200023e8883890162000152565b955060208701519150808211156200025557600080fd5b50620002648782880162000152565b604087015190945090506001600160a01b03811681146200028457600080fd5b6060959095015193969295505050565b600181811c90821680620002a957607f821691505b602082108103620002ca57634e487b7160e01b600052602260045260246000fd5b50919050565b601f8211156200013757600081815260208120601f850160051c81016020861015620002f95750805b601f850160051c820191505b818110156200031a5782815560010162000305565b505050505050565b81516001600160401b038111156200033e576200033e6200013c565b62000356816200034f845462000294565b84620002d0565b602080601f8311600181146200038e5760008415620003755750858301515b600019600386901b1c1916600185901b1785556200031a565b600085815260208120601f198616915b82811015620003bf578886015182559484019460019091019084016200039e565b5085821015620003de5787850151600019600388901b60f8161c191681555b5050505050600190811b01905550565b808201808211156200041057634e487b7160e01b600052601160045260246000fd5b92915050565b61101480620004266000396000f3fe608060405234801561001057600080fd5b506004361061014d5760003560e01c806340c10f19116100c35780639e4e73181161007c5780639e4e73181461033c578063a457c2d714610363578063a9059cbb14610376578063c473af3314610389578063d505accf146103b0578063dd62ed3e146103c357600080fd5b806340c10f19146102b257806342966c68146102c557806356189cb4146102d857806370a08231146102eb5780637ecebe001461031457806395d89b411461033457600080fd5b806323b872dd1161011557806323b872dd146101c357806330adf81f146101d6578063313ce567146101fd5780633408e4701461020c5780633644e51514610212578063395093511461029f57600080fd5b806304622c2e1461015257806306fdde031461016e578063095ea7b31461018357806318160ddd146101a6578063222f5be0146101ae575b600080fd5b61015b60065481565b6040519081526020015b60405180910390f35b6101766103d6565b6040516101659190610db1565b610196610191366004610e1b565b610468565b6040519015158152602001610165565b60025461015b565b6101c16101bc366004610e45565b610482565b005b6101966101d1366004610e45565b610492565b61015b7f6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c981565b60405160128152602001610165565b4661015b565b61015b6006546000907f8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f907fc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc646604080516020810195909552840192909252606083015260808201523060a082015260c00160405160208183030381529060405280519060200120905090565b6101966102ad366004610e1b565b6104b6565b6101c16102c0366004610e1b565b6104d8565b6101c16102d3366004610e81565b6104e6565b6101c16102e6366004610e45565b6104f3565b61015b6102f9366004610e9a565b6001600160a01b031660009081526020819052604090205490565b61015b610322366004610e9a565b60056020526000908152604090205481565b6101766104fe565b61015b7fc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc681565b610196610371366004610e1b565b61050d565b610196610384366004610e1b565b61058d565b61015b7f8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f81565b6101c16103be366004610ebc565b61059b565b61015b6103d1366004610f2f565b6106ae565b6060600380546103e590610f62565b80601f016020809104026020016040519081016040528092919081815260200182805461041190610f62565b801561045e5780601f106104335761010080835404028352916020019161045e565b820191906000526020600020905b81548152906001019060200180831161044157829003601f168201915b5050505050905090565b6000336104768185856106d9565b60019150505b92915050565b61048d8383836107fd565b505050565b6000336104a08582856109a3565b6104ab8585856107fd565b506001949350505050565b6000336104768185856104c983836106ae565b6104d39190610fb2565b6106d9565b6104e28282610a17565b5050565b6104f03382610ad6565b50565b61048d8383836106d9565b6060600480546103e590610f62565b6000338161051b82866106ae565b9050838110156105805760405162461bcd60e51b815260206004820152602560248201527f45524332303a2064656372656173656420616c6c6f77616e63652062656c6f77604482015264207a65726f60d81b60648201526084015b60405180910390fd5b6104ab82868684036106d9565b6000336104768185856107fd565b428410156105eb5760405162461bcd60e51b815260206004820152601960248201527f48455a3a3a7065726d69743a20415554485f45585049524544000000000000006044820152606401610577565b6001600160a01b038716600090815260056020526040812080547f6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9918a918a918a91908661063883610fc5565b909155506040805160208101969096526001600160a01b0394851690860152929091166060840152608083015260a082015260c0810186905260e0016040516020818303038152906040528051906020012090506106998882868686610c08565b6106a48888886106d9565b5050505050505050565b6001600160a01b03918216600090815260016020908152604080832093909416825291909152205490565b6001600160a01b03831661073b5760405162461bcd60e51b8152602060048201526024808201527f45524332303a20617070726f76652066726f6d20746865207a65726f206164646044820152637265737360e01b6064820152608401610577565b6001600160a01b03821661079c5760405162461bcd60e51b815260206004820152602260248201527f45524332303a20617070726f766520746f20746865207a65726f206164647265604482015261737360f01b6064820152608401610577565b6001600160a01b0383811660008181526001602090815260408083209487168084529482529182902085905590518481527f8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925910160405180910390a3505050565b6001600160a01b0383166108615760405162461bcd60e51b815260206004820152602560248201527f45524332303a207472616e736665722066726f6d20746865207a65726f206164604482015264647265737360d81b6064820152608401610577565b6001600160a01b0382166108c35760405162461bcd60e51b815260206004820152602360248201527f45524332303a207472616e7366657220746f20746865207a65726f206164647260448201526265737360e81b6064820152608401610577565b6001600160a01b0383166000908152602081905260409020548181101561093b5760405162461bcd60e51b815260206004820152602660248201527f45524332303a207472616e7366657220616d6f756e7420657863656564732062604482015265616c616e636560d01b6064820152608401610577565b6001600160a01b03848116600081815260208181526040808320878703905593871680835291849020805487019055925185815290927fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef910160405180910390a35b50505050565b60006109af84846106ae565b9050600019811461099d5781811015610a0a5760405162461bcd60e51b815260206004820152601d60248201527f45524332303a20696e73756666696369656e7420616c6c6f77616e63650000006044820152606401610577565b61099d84848484036106d9565b6001600160a01b038216610a6d5760405162461bcd60e51b815260206004820152601f60248201527f45524332303a206d696e7420746f20746865207a65726f2061646472657373006044820152606401610577565b8060026000828254610a7f9190610fb2565b90915550506001600160a01b038216600081815260208181526040808320805486019055518481527fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef910160405180910390a35050565b6001600160a01b038216610b365760405162461bcd60e51b815260206004820152602160248201527f45524332303a206275726e2066726f6d20746865207a65726f206164647265736044820152607360f81b6064820152608401610577565b6001600160a01b03821660009081526020819052604090205481811015610baa5760405162461bcd60e51b815260206004820152602260248201527f45524332303a206275726e20616d6f756e7420657863656564732062616c616e604482015261636560f01b6064820152608401610577565b6001600160a01b0383166000818152602081815260408083208686039055600280548790039055518581529192917fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef910160405180910390a3505050565b600654604080517f8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f602080830191909152818301939093527fc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc660608201524660808201523060a0808301919091528251808303909101815260c082019092528151919092012061190160f01b60e083015260e282018190526101028201869052906000906101220160408051601f198184030181528282528051602091820120600080855291840180845281905260ff89169284019290925260608301879052608083018690529092509060019060a0016020604051602081039080840390855afa158015610d1b573d6000803e3d6000fd5b5050604051601f1901519150506001600160a01b03811615801590610d515750876001600160a01b0316816001600160a01b0316145b6106a45760405162461bcd60e51b815260206004820152602b60248201527f48455a3a3a5f76616c69646174655369676e6564446174613a20494e56414c4960448201526a445f5349474e415455524560a81b6064820152608401610577565b600060208083528351808285015260005b81811015610dde57858101830151858201604001528201610dc2565b506000604082860101526040601f19601f8301168501019250505092915050565b80356001600160a01b0381168114610e1657600080fd5b919050565b60008060408385031215610e2e57600080fd5b610e3783610dff565b946020939093013593505050565b600080600060608486031215610e5a57600080fd5b610e6384610dff565b9250610e7160208501610dff565b9150604084013590509250925092565b600060208284031215610e9357600080fd5b5035919050565b600060208284031215610eac57600080fd5b610eb582610dff565b9392505050565b600080600080600080600060e0888a031215610ed757600080fd5b610ee088610dff565b9650610eee60208901610dff565b95506040880135945060608801359350608088013560ff81168114610f1257600080fd5b9699959850939692959460a0840135945060c09093013592915050565b60008060408385031215610f4257600080fd5b610f4b83610dff565b9150610f5960208401610dff565b90509250929050565b600181811c90821680610f7657607f821691505b602082108103610f9657634e487b7160e01b600052602260045260246000fd5b50919050565b634e487b7160e01b600052601160045260246000fd5b8082018082111561047c5761047c610f9c565b600060018201610fd757610fd7610f9c565b506001019056fea26469706673582212207bede9966bc8e8634cc0c3dc076626579b27dff7bbcac0b645c87d4cf1812b9864736f6c63430008140033
constructor_args=$(cast abi-encode 'f(string,string,address,uint256)' 'Bridge Test' 'BT' "$target_address" 100000000000000000000 | sed 's/0x//')

cast send --legacy --rpc-url $l1_rpc_url --private-key $private_key $deterministic_deployer_addr $salt$erc_20_bytecode$constructor_args
cast send --legacy --rpc-url $l2_pp1_url --private-key $private_key $deterministic_deployer_addr $salt$erc_20_bytecode$constructor_args
cast send --legacy --rpc-url $l2_pp2_url --private-key $private_key $deterministic_deployer_addr $salt$erc_20_bytecode$constructor_args

test_erc20_addr=$(cast create2 --salt $salt --init-code $erc_20_bytecode$constructor_args)

cast send --legacy --rpc-url $l1_rpc_url --private-key $target_private_key $test_erc20_addr 'approve(address,uint256)' $bridge_address 100000000000000000000
cast send --legacy --rpc-url $l2_pp1_url --private-key $target_private_key $test_erc20_addr 'approve(address,uint256)' $bridge_address 100000000000000000000
cast send --legacy --rpc-url $l2_pp2_url --private-key $target_private_key $test_erc20_addr 'approve(address,uint256)' $bridge_address 100000000000000000000


# One of the test cases that I've left out for now is a permit
# call. It'll take some work to get the signed permit data in place,
# but it seems doable.
#
# - https://eips.ethereum.org/EIPS/eip-2612
# - https://eips.ethereum.org/EIPS/eip-712
#
# permit_sig=$(cast wallet sign --private-key $target_private_key 0x$(< /dev/urandom xxd -p | tr -d "\n" | head -c 40))
# permit_sig_r=${permit_sig:2:64}
# permit_sig_s=${permit_sig:66:64}
# permit_sig_v=${permit_sig:130:2}

# The test cases are committed for convenience, we'll use that to
# dynamically to some testing
cat test-scenarios.json | jq -c '.[]' | while read scenario ; do
    testBridgeType=$(echo $scenario | jq -r '.BridgeType')
    testDepositChain=$(echo $scenario | jq -r '.DepositChain')
    testDestinationChain=$(echo $scenario | jq -r '.DestinationChain')
    testDestinationAddress=$(echo $scenario | jq -r '.DestinationAddress')
    testToken=$(echo $scenario | jq -r '.Token')
    testMetaData=$(echo $scenario | jq -r '.MetaData')
    testForceUpdate=$(echo $scenario | jq -r '.ForceUpdate')
    testAmount=$(echo $scenario | jq -r '.Amount')

    testCommand="polycli ulxly bridge"

    if [[ $testBridgeType == "Asset" ]]; then
        testCommand="$testCommand asset"
    elif [[ $testBridgeType == "Message" ]]; then
        testCommand="$testCommand message"
    else
        testCommand="$testCommand weth"
    fi

    if [[ $testDepositChain == "L1" ]]; then
        testCommand="$testCommand --rpc-url $l1_rpc_url"
    elif [[ $testDepositChain == "PP1" ]]; then
        testCommand="$testCommand --rpc-url $l2_pp1_url"
    else
        testCommand="$testCommand --rpc-url $l2_pp2_url"
    fi

    if [[ $testDestinationChain == "L1" ]]; then
        testCommand="$testCommand --destination-network 0"
    elif [[ $testDestinationChain == "PP1" ]]; then
        testCommand="$testCommand --destination-network 1"
    else
        testCommand="$testCommand --destination-network 2"
    fi

    if [[ $testDestinationAddress == "Contract" ]]; then
        testCommand="$testCommand --destination-address $bridge_address"
    elif [[ $testDestinationAddress == "Precompile" ]]; then
        testCommand="$testCommand --destination-address 0x0000000000000000000000000000000000000004"
    else
        testCommand="$testCommand --destination-address $target_address"
    fi

    if [[ $testToken == "POL" ]]; then
        testCommand="$testCommand --token-address $pol_address"
    elif [[ $testToken == "LocalERC20" ]]; then
        testCommand="$testCommand --token-address $test_erc20_addr"
    elif [[ $testToken == "WETH" ]]; then
        testCommand="$testCommand --token-address $pp2_weth_address"
    elif [[ $testToken == "Invalid" ]]; then
        testCommand="$testCommand --token-address $(< /dev/urandom xxd -p | tr -d "\n" | head -c 40)"
    else
        testCommand="$testCommand --token-address 0x0000000000000000000000000000000000000000"
    fi

    if [[ $testMetaData == "Random" ]]; then
        testCommand="$testCommand --call-data $(date +%s | xxd -p)"
    else
        testCommand="$testCommand --call-data 0x"
    fi

    if [[ $testForceUpdate == "True" ]]; then
        testCommand="$testCommand --force-update-root=true"
    else
        testCommand="$testCommand --force-update-root=false"
    fi

    if [[ $testAmount == "0" ]]; then
        testCommand="$testCommand --value 0"
    elif [[ $testAmount == "1" ]]; then
        testCommand="$testCommand --value 1"
    else
        testCommand="$testCommand --value $(date +%s)"
    fi

    testCommand="$testCommand --bridge-address $bridge_address"
    testCommand="$testCommand --private-key $target_private_key"

    echo $scenario | jq -c '.'
    echo $testCommand
    $testCommand
done


curl -s $l2_pp2b_url/bridges/$target_address | jq -c '.deposits[] | select(.network_id == 2) | select(.dest_net == 1)' | while read deposit ; do
    echo $deposit | jq -c '.'
    leaf_type=$(echo $deposit | jq -r '.leaf_type')
    if [[ $leaf_type == "0" ]]; then
        polycli ulxly claim asset \
                --bridge-address $bridge_address \
                --bridge-service-url $l2_pp2b_url \
                --rpc-url $l2_pp1_url \
                --deposit-count $(echo $deposit | jq -r '.deposit_cnt') \
                --deposit-network 2 \
                --destination-address $(echo $deposit | jq -r '.dest_addr') \
                --private-key $private_key

    else
        polycli ulxly claim message \
                --bridge-address $bridge_address \
                --bridge-service-url $l2_pp2b_url \
                --rpc-url $l2_pp1_url \
                --deposit-count $(echo $deposit | jq -r '.deposit_cnt') \
                --deposit-network 2 \
                --destination-address $(echo $deposit | jq -r '.dest_addr') \
                --private-key $private_key
    fi
done
curl -s $l2_pp1b_url/bridges/$target_address | jq -c '.deposits[] | select(.network_id == 1) | select(.dest_net == 2)' | while read deposit ; do
    echo $deposit | jq -c '.'
    leaf_type=$(echo $deposit | jq -r '.leaf_type')
    if [[ $leaf_type == "0" ]]; then
        polycli ulxly claim asset \
                --bridge-address $bridge_address \
                --bridge-service-url $l2_pp1b_url \
                --rpc-url $l2_pp2_url \
                --deposit-count $(echo $deposit | jq -r '.deposit_cnt') \
                --deposit-network 1 \
                --destination-address $(echo $deposit | jq -r '.dest_addr') \
                --private-key $private_key

    else
        polycli ulxly claim message \
                --bridge-address $bridge_address \
                --bridge-service-url $l2_pp1b_url \
                --rpc-url $l2_pp2_url \
                --deposit-count $(echo $deposit | jq -r '.deposit_cnt') \
                --deposit-network 1 \
                --destination-address $(echo $deposit | jq -r '.dest_addr') \
                --private-key $private_key
    fi
done





constructor_args=$(cast abi-encode 'f(string,string,address,uint256)' 'Big Test' 'BT' "$target_address" $(cast max-uint) | sed 's/0x//')
cast send --legacy --rpc-url $l2_pp1_url --private-key $target_private_key $deterministic_deployer_addr 0x6a6f686e2068696c6c696172642077617320686572650a000000000000000002$erc_20_bytecode$constructor_args
cast send --legacy --rpc-url $l2_pp1_url --private-key $target_private_key 0x8A5B34caF06Da682FDC4d08696417054fBaA5D6B 'approve(address,uint256)' $bridge_address $(cast max-uint)

polycli ulxly bridge asset \
        --private-key $target_private_key \
        --value $(cast max-uint) \
        --bridge-address $bridge_address \
        --destination-network 2 \
        --destination-address $target_address \
        --call-data 0x \
        --rpc-url $l2_pp1_url \
        --token-address 0x8A5B34caF06Da682FDC4d08696417054fBaA5D6B \
        --force-update-root=true

# 9:45AM INF bridgeTxn: 0x2b23e48077674e683ddd0af6e753ec6e394bc5d880e819db3903899e2dffce71
# 9:45AM INF Deposit transaction successful txHash=0x2b23e48077674e683ddd0af6e753ec6e394bc5d880e819db3903899e2dffce71
token_hash=$(cast keccak $(cast abi-encode --packed 'f(uint32,address)' 1 0x8A5B34caF06Da682FDC4d08696417054fBaA5D6B))
pp2_big_test_addr=$(cast call --rpc-url $l2_pp2_url  $bridge_address 'tokenInfoToWrappedToken(bytes32)(address)' $token_hash)
cast call --rpc-url $l2_pp2_url $pp2_big_test_addr 'balanceOf(address)' $target_address


polycli ulxly bridge asset \
        --private-key $target_private_key \
        --value 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe \
        --bridge-address $bridge_address \
        --destination-network 1 \
        --destination-address $target_address \
        --rpc-url $l2_pp2_url \
        --token-address $pp2_big_test_addr \
        --force-update-root=true



curl -s $l2_pp1b_url/bridges/$target_address

# TODO add a test where there is more than uint256 funds
# TODO add some tests with reverting
# TODO add some tests where the bridge is called via a smart contract rather than directly

# ## State Capture Procedure
pushd $(mktemp -d)
mkdir agglayer-storage
docker cp agglayer--f3cc4c8d0bad44be9c0ea8eccedd0da1:/etc/zkevm/storage agglayer-storage/
mkdir cdk-001
docker cp cdk-node-001--bd52b030071a4c438cf82b6c281219e6:/tmp cdk-001/
mkdir cdk-002
docker cp cdk-node-002--3c9a92d0e1aa4259a795d7a60156188c:/tmp cdk-002/
kurtosis enclave dump pp

popd
tar caf agglayer-details.tar.xz /tmp/tmp.VKezDefjS6
