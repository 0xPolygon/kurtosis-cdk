#!/bin/bash

if [[ ! -e docs/multi-pp-testing/test-scenarios.json ]]; then
    echo "expected to find test scenarios in docs/multi-pp-testing/test-scenarios.json. Maybe we're not in the root of the repo?"
    exit 1
fi

tester_contract_address=0xc54E34B55EF562FE82Ca858F70D1B73244e86388
test_erc20_buggy_addr=0x22939b3A4dFD9Fc6211F99Cdc6bd9f6708ae2956
test_lxly_proxy_addr=0x5d1847D52a39a05E6EDb45F2890d52D83155CF7F
tester_contract_address=0xc54E34B55EF562FE82Ca858F70D1B73244e86388

l1_rpc_url=http://$(kurtosis port print pp el-1-geth-lighthouse rpc)
l2_pp1_url=$(kurtosis port print pp cdk-erigon-rpc-001 rpc)
l2_pp2_url=$(kurtosis port print pp cdk-erigon-rpc-002 rpc)
l2_fep_url=$(kurtosis port print pp cdk-erigon-rpc-003 rpc)

l2_pp1b_url=$(kurtosis port print pp zkevm-bridge-service-001 rpc)
l2_pp2b_url=$(kurtosis port print pp zkevm-bridge-service-002 rpc)
l2_fepb_url=$(kurtosis port print pp zkevm-bridge-service-003 rpc)

private_key="0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"
eth_address="$(cast wallet address --private-key $private_key)"

rpc_list="$l1_rpc_url $l2_fep_url $l2_pp1_url $l2_pp2_url"

network_id_l1=0
network_id_pp1=1
network_id_pp2=2
network_id_fep=3

bridge_address=$(cat combined-001.json | jq -r .polygonZkEVMBridgeAddress)
pol_address=$(cat combined-001.json | jq -r .polTokenAddress)
gas_token_address=$(<gas-token-address.json)

token_hash=$(cast keccak $(cast abi-encode --packed 'f(uint32,address)' 0 $gas_token_address))
l2_gas_token_address=$(cast call --rpc-url $l2_pp1_url  $bridge_address 'tokenInfoToWrappedToken(bytes32)(address)' $token_hash)

while read scenario ; do
    echo $scenario | jq -c '.'

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
    elif [[ $testBridgeType == "Weth" ]]; then
        testCommand="$testCommand weth"
    else
        printf "Unrecognized Bridge Type: $testBridgeType\n"
        exit 1;
    fi

    temp_rpc_url=""
    if [[ $testDepositChain == "L1" ]]; then
        testCommand="$testCommand --rpc-url $l1_rpc_url"
        temp_rpc_url="$l1_rpc_url"
    elif [[ $testDepositChain == "PP1" ]]; then
        testCommand="$testCommand --rpc-url $l2_pp1_url"
        temp_rpc_url="$l2_pp1_url"
    elif [[ $testDepositChain == "FEP" ]]; then
        testCommand="$testCommand --rpc-url $l2_fep_url"
        temp_rpc_url="$l2_fep_url"
    elif [[ $testDepositChain == "PP2" ]]; then
        testCommand="$testCommand --rpc-url $l2_pp2_url"
        temp_rpc_url="$l2_pp2_url"
    else
        printf "Unrecognized Deposit Chain: $testDepositChain\n"
        exit 1;
    fi

    if [[ $testDestinationChain == "L1" ]]; then
        testCommand="$testCommand --destination-network $network_id_l1"
    elif [[ $testDestinationChain == "PP1" ]]; then
        testCommand="$testCommand --destination-network $network_id_pp1"
    elif [[ $testDestinationChain == "FEP" ]]; then
        testCommand="$testCommand --destination-network $network_id_fep"
    elif [[ $testDestinationChain == "PP2" ]]; then
        testCommand="$testCommand --destination-network $network_id_pp2"
    else
        printf "Unrecognized Destination Chain: $testDestinationChain\n"
        exit 1;
    fi

    if [[ $testDestinationAddress == "Contract" ]]; then
        testCommand="$testCommand --destination-address $bridge_address"
    elif [[ $testDestinationAddress == "Precompile" ]]; then
        testCommand="$testCommand --destination-address 0x0000000000000000000000000000000000000004"
    elif [[ $testDestinationAddress == "EOA" ]]; then
        testCommand="$testCommand --destination-address $eth_address"
    else
        printf "Unrecognized Destination Address: $testDestinationAddress\n"
        exit 1;
    fi

    if [[ $testToken == "POL" ]]; then
        testCommand="$testCommand --token-address $pol_address"
    elif [[ $testToken == "LocalERC20" ]]; then
        testCommand="$testCommand --token-address $test_erc20_addr"
    elif [[ $testToken == "WETH" ]]; then
        testCommand="$testCommand --token-address $pp2_weth_address"
    elif [[ $testToken == "Buggy" ]]; then
        testCommand="$testCommand --token-address $test_erc20_buggy_addr"
    elif [[ $testToken == "GasToken" ]]; then
        if [[ $testDepositChain == "L1" ]]; then
            testCommand="$testCommand --token-address $gas_token_address"
        elif [[  $testDepositChain == "PP2" ]]; then
            testCommand="$testCommand --token-address 0x0000000000000000000000000000000000000000"
        else
            testCommand="$testCommand --token-address $l2_gas_token_address"
        fi
    elif [[ $testToken == "NativeEther" ]]; then
        if [[  $testDepositChain == "PP2" ]]; then
            testCommand="$testCommand --token-address $pp2_weth_address"
        else
            testCommand="$testCommand --token-address 0x0000000000000000000000000000000000000000"
        fi
    else
        printf "Unrecognized Test Token: $testToken\n"
        exit 1;
    fi

    if [[ $testMetaData == "Random" ]]; then
        testCommand="$testCommand --call-data $(date +%s | xxd -p)"
    elif [[ $testMetaData == "0x" ]]; then
        testCommand="$testCommand --call-data 0x"
    elif [[ $testMetaData == "Huge" ]]; then
        temp_file=$(mktemp)
        xxd -p /dev/random | tr -d "\n" | head -c 97000 > $temp_file
        testCommand="$testCommand --call-data-file $temp_file"
    elif [[ $testMetaData == "Max" ]]; then
        temp_file=$(mktemp)
        xxd -p /dev/random | tr -d "\n" | head -c 261569 > $temp_file
        testCommand="$testCommand --call-data-file $temp_file"
    else
        printf "Unrecognized Metadata: $testMetaData\n"
        exit 1;
    fi

    if [[ $testForceUpdate == "True" ]]; then
        testCommand="$testCommand --force-update-root=true"
    elif [[ $testForceUpdate == "False" ]]; then
        testCommand="$testCommand --force-update-root=false"
    else
        printf "Unrecognized Force Update: $testForceUpdate\n"
        exit 1;
    fi

    if [[ $testAmount == "0" ]]; then
        testCommand="$testCommand --value 0"
    elif [[ $testAmount == "1" ]]; then
        testCommand="$testCommand --value 1"
    elif [[ $testAmount == "Max" ]]; then
        cast send --legacy --rpc-url $temp_rpc_url --private-key $private_key $test_erc20_buggy_addr 'mint(address,uint256)' $eth_address $(cast max-uint)
        cast send --legacy --rpc-url $temp_rpc_url --private-key $private_key $test_erc20_buggy_addr 'setBalanceOf(address,uint256)' $bridge_address 0
        testCommand="$testCommand --value $(cast max-uint)"
    elif [[ $testAmount == "Random" ]]; then
        testCommand="$testCommand --value $(date +%s)"
    else
        printf "Unrecognized Amount: $testAmount\n"
        exit 1;
    fi

    testCommand="$testCommand --bridge-address $bridge_address"
    testCommand="$testCommand --private-key $private_key"

    echo $testCommand
    $testCommand

    # In this particular case, we should zero the bridge out after the deposit is made
    if [[ $testAmount == "Max" ]]; then
        cast send --legacy --rpc-url $temp_rpc_url --private-key $private_key $test_erc20_buggy_addr 'setBalanceOf(address,uint256)' $bridge_address 0
    fi
done < <(jq -c '.[]' docs/multi-pp-testing/test-scenarios.json)

address_tester_actions="001 011 021 031 101 201 301 401 501 601 701 801 901"
for create_mode in 0 1 2; do
    for action in $address_tester_actions ; do
        printf "Running test: 0x$create_mode$action"
        cast send --gas-limit 2500000 --legacy --value $network_id_fep --rpc-url $l1_rpc_url --private-key $private_key $tester_contract_address $(cast abi-encode 'f(uint32, address, uint256)' 0x"$create_mode$action" $test_lxly_proxy_addr $network_id_fep)
        cast send --gas-limit 2500000 --legacy --value $network_id_pp1 --rpc-url $l1_rpc_url --private-key $private_key $tester_contract_address $(cast abi-encode 'f(uint32, address, uint256)' 0x"$create_mode$action" $test_lxly_proxy_addr $network_id_pp1)
        cast send --gas-limit 2500000 --legacy --value $network_id_pp2 --rpc-url $l1_rpc_url --private-key $private_key $tester_contract_address $(cast abi-encode 'f(uint32, address, uint256)' 0x"$create_mode$action" $test_lxly_proxy_addr $network_id_pp2)

        cast send --gas-limit 2500000 --legacy --value $network_id_l1  --rpc-url $l2_pp1_url --private-key $private_key $tester_contract_address $(cast abi-encode 'f(uint32, address, uint256)' 0x"$create_mode$action" $test_lxly_proxy_addr $network_id_l1)
        cast send --gas-limit 2500000 --legacy --value $network_id_fep --rpc-url $l2_pp1_url --private-key $private_key $tester_contract_address $(cast abi-encode 'f(uint32, address, uint256)' 0x"$create_mode$action" $test_lxly_proxy_addr $network_id_fep)
        cast send --gas-limit 2500000 --legacy --value $network_id_pp2 --rpc-url $l2_pp1_url --private-key $private_key $tester_contract_address $(cast abi-encode 'f(uint32, address, uint256)' 0x"$create_mode$action" $test_lxly_proxy_addr $network_id_pp2)

        cast send --gas-limit 2500000 --legacy --value $network_id_l1  --rpc-url $l2_pp2_url --private-key $private_key $tester_contract_address $(cast abi-encode 'f(uint32, address, uint256)' 0x"$create_mode$action" $test_lxly_proxy_addr $network_id_l1)
        cast send --gas-limit 2500000 --legacy --value $network_id_fep --rpc-url $l2_pp2_url --private-key $private_key $tester_contract_address $(cast abi-encode 'f(uint32, address, uint256)' 0x"$create_mode$action" $test_lxly_proxy_addr $network_id_fep)
        cast send --gas-limit 2500000 --legacy --value $network_id_pp1 --rpc-url $l2_pp2_url --private-key $private_key $tester_contract_address $(cast abi-encode 'f(uint32, address, uint256)' 0x"$create_mode$action" $test_lxly_proxy_addr $network_id_pp1)

        cast send --gas-limit 2500000 --legacy --value $network_id_l1  --rpc-url $l2_fep_url --private-key $private_key $tester_contract_address $(cast abi-encode 'f(uint32, address, uint256)' 0x"$create_mode$action" $test_lxly_proxy_addr $network_id_l1)
        cast send --gas-limit 2500000 --legacy --value $network_id_pp1 --rpc-url $l2_fep_url --private-key $private_key $tester_contract_address $(cast abi-encode 'f(uint32, address, uint256)' 0x"$create_mode$action" $test_lxly_proxy_addr $network_id_pp1)
        cast send --gas-limit 2500000 --legacy --value $network_id_pp2 --rpc-url $l2_fep_url --private-key $private_key $tester_contract_address $(cast abi-encode 'f(uint32, address, uint256)' 0x"$create_mode$action" $test_lxly_proxy_addr $network_id_pp2)
    done
done

polycli ulxly claim-everything \
        --bridge-address $bridge_address \
        --bridge-service-map $network_id_fep=$l2_fepb_url \
        --bridge-service-map $network_id_pp1=$l2_pp1b_url \
        --bridge-service-map $network_id_pp2=$l2_pp2b_url \
        --destination-address $eth_address \
        --private-key $private_key \
        --rpc-url $l2_fep_url \
        --bridge-limit 1000 --bridge-offset 0
polycli ulxly claim-everything \
        --bridge-address $bridge_address \
        --bridge-service-map $network_id_fep=$l2_fepb_url \
        --bridge-service-map $network_id_pp1=$l2_pp1b_url \
        --bridge-service-map $network_id_pp2=$l2_pp2b_url \
        --destination-address $eth_address \
        --private-key $private_key \
        --rpc-url $l2_pp1_url \
        --bridge-limit 1000 --bridge-offset 0
polycli ulxly claim-everything \
        --bridge-address $bridge_address \
        --bridge-service-map $network_id_fep=$l2_fepb_url \
        --bridge-service-map $network_id_pp1=$l2_pp1b_url \
        --bridge-service-map $network_id_pp2=$l2_pp2b_url \
        --destination-address $eth_address \
        --private-key $private_key \
        --rpc-url $l2_pp2_url \
        --bridge-limit 1000 --bridge-offset 0
polycli ulxly claim-everything \
        --bridge-address $bridge_address \
        --bridge-service-map $network_id_fep=$l2_fepb_url \
        --bridge-service-map $network_id_pp1=$l2_pp1b_url \
        --bridge-service-map $network_id_pp2=$l2_pp2b_url \
        --destination-address $eth_address \
        --private-key $private_key \
        --rpc-url $l1_rpc_url \
        --bridge-limit 1000 --bridge-offset 0
