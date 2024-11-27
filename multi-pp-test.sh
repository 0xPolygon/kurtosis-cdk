#!/bin/bash
echo "dont run this!"
exit 1;

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
cast send --legacy --value 10ether --rpc-url $l2_pp_url --private-key $private_key 0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8
cast send --legacy --value 10ether --rpc-url $l2_fep_url --private-key $private_key 0x93F63c24735f45Cd0266E87353071B64dd86bc05

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


# Let's go to madison county

# R0, R1, Native, Force
cast send \
    --legacy \
    --rpc-url $l1_rpc_url \
    --value 100000000000000000000 \
    --private-key $private_key \
    $bridge_address \
    "bridgeAsset(uint32,address,uint256,address,bool,bytes)" \
    1 $target_address 100000000000000000000 $(cast az) true 0x

# R0, R2, Native, Force
cast send \
    --legacy \
    --rpc-url $l1_rpc_url \
    --value 100000000000000000000 \
    --private-key $private_key \
    $bridge_address \
    "bridgeAsset(uint32,address,uint256,address,bool,bytes)" \
    2 $target_address 100000000000000000000 $(cast az) true 0x

# R0, R1, Native, No Force
cast send \
    --legacy \
    --rpc-url $l1_rpc_url \
    --value 1000000000000000000 \
    --private-key $private_key \
    $bridge_address \
    "bridgeAsset(uint32,address,uint256,address,bool,bytes)" \
    1 $target_address 1000000000000000000 $(cast az) false 0x

# R0, R2, Native, No Force
cast send \
    --legacy \
    --rpc-url $l1_rpc_url \
    --value 1000000000000000000 \
    --private-key $private_key \
    $bridge_address \
    "bridgeAsset(uint32,address,uint256,address,bool,bytes)" \
    2 $target_address 1000000000000000000 $(cast az) false 0x


# R0, R1, POL, Force
cast send \
    --legacy \
    --rpc-url $l1_rpc_url \
    --private-key $private_key \
    $bridge_address \
    "bridgeAsset(uint32,address,uint256,address,bool,bytes)" \
    1 $target_address 1000000000000000000 $pol_address true 0x

# R0, R2, POL, Force
cast send \
    --legacy \
    --rpc-url $l1_rpc_url \
    --private-key $private_key \
    $bridge_address \
    "bridgeAsset(uint32,address,uint256,address,bool,bytes)" \
    2 $target_address 1000000000000000000 $pol_address true 0x

# We'll need to wait a little bit...

# Let's see if our balances have grown (both should be non-zero)
cast balance --ether --rpc-url $l2_pp_url $target_address
cast balance --ether --rpc-url $l2_fep_url $target_address

# Let's check our L2 token balance (both should be non-zero)
token_hash=$(cast keccak $(cast abi-encode --packed 'f(uint32,address)' 0 $pol_address))
l2_pol_address=$(cast call --rpc-url $l2_pp_url  $bridge_address 'tokenInfoToWrappedToken(bytes32)(address)' $token_hash)
cast call --rpc-url $l2_pp_url $l2_pol_address 'balanceOf(address)(uint256)' $target_address
cast call --rpc-url $l2_fep_url $l2_pol_address 'balanceOf(address)(uint256)' $target_address

# We should be in a good position now to try some bridge exits!!
# PP Exits
# R1, R0, Native, No Force
cast send \
    --legacy \
    --rpc-url $l2_pp_url \
    --value 100000000000000003 \
    --private-key $target_private_key \
    $bridge_address \
    "bridgeAsset(uint32,address,uint256,address,bool,bytes)" \
    0 $target_address 100000000000000003 $(cast az) false 0x

# R1, R2, Native, No Force
cast send \
    --legacy \
    --rpc-url $l2_pp_url \
    --value 100000000000000004 \
    --private-key $target_private_key \
    $bridge_address \
    "bridgeAsset(uint32,address,uint256,address,bool,bytes)" \
    2 $target_address 100000000000000004 $(cast az) false 0x

# R1, R0, POL, No Force
cast send \
    --legacy \
    --rpc-url $l2_pp_url \
    --private-key $target_private_key \
    $bridge_address \
    "bridgeAsset(uint32,address,uint256,address,bool,bytes)" \
    0 $target_address 100000000000000005 $l2_pol_address false 0x

# R1, R2, POL, No Force
cast send \
    --legacy \
    --rpc-url $l2_pp_url \
    --private-key $target_private_key \
    $bridge_address \
    "bridgeAsset(uint32,address,uint256,address,bool,bytes)" \
    2 $target_address 100000000000000006 $l2_pol_address false 0x

# R1, R0, Native, Force
cast send \
    --legacy \
    --rpc-url $l2_pp_url \
    --value 100000000000000001 \
    --private-key $target_private_key \
    $bridge_address \
    "bridgeAsset(uint32,address,uint256,address,bool,bytes)" \
    0 $target_address 100000000000000001 $(cast az) true 0x

# R1, R2, Native, Force
cast send \
    --legacy \
    --rpc-url $l2_pp_url \
    --value 100000000000000002 \
    --private-key $target_private_key \
    $bridge_address \
    "bridgeAsset(uint32,address,uint256,address,bool,bytes)" \
    2 $target_address 100000000000000002 $(cast az) true 0x

# FEP Exists
# R2, R0, Native, No Force
cast send \
    --legacy \
    --rpc-url $l2_fep_url \
    --value 100000000000000007 \
    --private-key $target_private_key \
    $bridge_address \
    "bridgeAsset(uint32,address,uint256,address,bool,bytes)" \
    0 $target_address 100000000000000007 $(cast az) false 0x

# R2, R1, Native, No Force
cast send \
    --legacy \
    --rpc-url $l2_fep_url \
    --value 100000000000000008 \
    --private-key $target_private_key \
    $bridge_address \
    "bridgeAsset(uint32,address,uint256,address,bool,bytes)" \
    1 $target_address 100000000000000008 $(cast az) false 0x

# R2, R0, POL, No Force
cast send \
    --legacy \
    --rpc-url $l2_fep_url \
    --private-key $target_private_key \
    $bridge_address \
    "bridgeAsset(uint32,address,uint256,address,bool,bytes)" \
    0 $target_address 100000000000000009 $l2_pol_address false 0x

# R2, R1, POL, No Force
cast send \
    --legacy \
    --rpc-url $l2_fep_url \
    --private-key $target_private_key \
    $bridge_address \
    "bridgeAsset(uint32,address,uint256,address,bool,bytes)" \
    1 $target_address 100000000000000010 $l2_pol_address false 0x

# R2, R0, Native, Force
cast send \
    --legacy \
    --rpc-url $l2_fep_url \
    --value 100000000000000011 \
    --private-key $target_private_key \
    $bridge_address \
    "bridgeAsset(uint32,address,uint256,address,bool,bytes)" \
    0 $target_address 100000000000000011 $(cast az) true 0x

# R2, R1, Native, Force
cast send \
    --legacy \
    --rpc-url $l2_fep_url \
    --value 100000000000000012 \
    --private-key $target_private_key \
    $bridge_address \
    "bridgeAsset(uint32,address,uint256,address,bool,bytes)" \
    1 $target_address 100000000000000012 $(cast az) true 0x


# Do some criss-crossing
for i in {1..20}; do
    # R1, R0, Native, Force
    cast send \
         --legacy \
         --rpc-url $l2_pp_url \
         --value 100000000000000001 \
         --private-key $target_private_key \
         $bridge_address \
         "bridgeAsset(uint32,address,uint256,address,bool,bytes)" \
         0 $target_address 100000000000000001 $(cast az) true 0x

    # R2, R0, Native, Force
    cast send \
         --legacy \
         --rpc-url $l2_fep_url \
         --value 100000000000000011 \
         --private-key $target_private_key \
         $bridge_address \
         "bridgeAsset(uint32,address,uint256,address,bool,bytes)" \
         0 $target_address 100000000000000011 $(cast az) true 0x
done


# Do a bridge message
# R0, R1, Message, Force
cast send \
    --legacy \
    --rpc-url $l1_rpc_url \
    --value 1 \
    --private-key $private_key \
    $bridge_address \
    "bridgeMessage(uint32,address,bool,bytes)" \
    1 "0xFFFF000000000000000000000000000000000001" "true" "0x1234"

# R0, R2, Message, Force
cast send \
    --legacy \
    --rpc-url $l1_rpc_url \
    --value 1 \
    --private-key $private_key \
    $bridge_address \
    "bridgeMessage(uint32,address,bool,bytes)" \
    2 "0xFFFF000000000000000000000000000000000001" "true" "0x1234"

# R0, R9999, Message, Force
cast send \
    --legacy \
    --rpc-url $l1_rpc_url \
    --value 1 \
    --private-key $private_key \
    $bridge_address \
    "bridgeMessage(uint32,address,bool,bytes)" \
    9999 "0xFFFF000000000000000000000000000000000001" "true" "0x1234"


for i in {2..16}; do
    call_size=$(bc <<< "2^$i")
    # R0, R1, Message, Force
    cast send \
         --legacy \
         --rpc-url $l1_rpc_url \
         --value 1 \
         --private-key $private_key \
         $bridge_address \
         "bridgeMessage(uint32,address,bool,bytes)" \
         1 "0xFFFF000000000000000000000000000000000001" "true" "0x$(cat /dev/random | xxd -p | tr -d "\n" | head -c $call_size)"

    # R0, R2, Message, Force
    cast send \
         --legacy \
         --rpc-url $l1_rpc_url \
         --value 1 \
         --private-key $private_key \
         $bridge_address \
         "bridgeMessage(uint32,address,bool,bytes)" \
         2 "0xFFFF000000000000000000000000000000000001" "true" "0x$(cat /dev/random | xxd -p | tr -d "\n" | head -c $call_size)"
done


for i in {2..16}; do
    call_size=$(bc <<< "2^$i")
    # R1, R0, Message, Force
    cast send \
         --legacy \
         --rpc-url $l2_pp_url \
         --value 1 \
         --private-key $target_private_key \
         $bridge_address \
         "bridgeMessage(uint32,address,bool,bytes)" \
         0 "0xFFFF000000000000000000000000000000000001" "true" "0x$(cat /dev/random | xxd -p | tr -d "\n" | head -c $call_size)"
    # R1, R2, Message, Force
    cast send \
         --legacy \
         --rpc-url $l2_pp_url \
         --value 1 \
         --private-key $target_private_key \
         $bridge_address \
         "bridgeMessage(uint32,address,bool,bytes)" \
         2 "0xFFFF000000000000000000000000000000000001" "true" "0x$(cat /dev/random | xxd -p | tr -d "\n" | head -c $call_size)"
done

# At this point, I've encountered the error
# [agglayer] {"timestamp":"2024-11-27T20:18:52.021621Z","level":"WARN","fields":{"message":"Error during certification process of 0x24319d4ef5dda589b80498917cea4a66fd91494993fb391bfe5a02ddda84e674: native execution failed: MissingTokenBalanceProof(TokenInfo { origin_network: NetworkId(0), origin_token_address: 0x0000000000000000000000000000000000000000 })","hash":"0x24319d4ef5dda589b80498917cea4a66fd91494993fb391bfe5a02ddda84e674"},"target":"agglayer_certificate_orchestrator::network_task"}
# [agglayer] {"timestamp":"2024-11-27T20:18:59.020532Z","level":"WARN","fields":{"message":"Certificate 0x24319d4ef5dda589b80498917cea4a66fd91494993fb391bfe5a02ddda84e674 is in error: (native) proof generation error: Missing token balance proof. TokenInfo: TokenInfo { origin_network: NetworkId(0), origin_token_address: 0x0000000000000000000000000000000000000000 }","hash":"0x24319d4ef5dda589b80498917cea4a66fd91494993fb391bfe5a02ddda84e674"},"target":"agglayer_certificate_orchestrator::network_task"}

