#!/bin/bash

# The goals of this script is to test and validate the operational status of the CDK environment.

# TODO: Sanity checks to add:
# - Log check
# - ✅ All containers running
# - ✅ Matching values from rpc and sequencer
# - ✅ Matching values from rpc and data stream
# - ✅ Is this a validium or a rollup
# - ✅ Dac Committee Members
# - ✅ Batch verification gap

check_variable() {
  local var_name="$1"
  local var_value="${!var_name}"
  if [ -z "$var_value" ]; then
    echo "Error: $var_name is not defined"
    exit 1
  fi
}

####################################################################################################
#    ____ ___  _   _ _____ ___ ____
#   / ___/ _ \| \ | |  ___|_ _/ ___|
#  | |  | | | |  \| | |_   | | |  _
#  | |__| |_| | |\  |  _|  | | |_| |
#   \____\___/|_| \_|_|   |___\____|
#
####################################################################################################

# ENCLAVE
enclave="cdk"

if [[ "$enclave" != "" ]] && ! kurtosis enclave inspect "$enclave"; then
  exit 1
fi

# LOCAL KURTOSIS-CDK
l1_rpc_url="$(kurtosis port print "$enclave" el-1-geth-lighthouse rpc)"
l2_sequencer_url="$(kurtosis port print "$enclave" cdk-erigon-sequencer-001 rpc)"
l2_datastreamer_url="$(kurtosis port print "$enclave" cdk-erigon-sequencer-001 data-streamer | sed 's|datastream://||')"
l2_rpc_url="$(kurtosis port print "$enclave" cdk-erigon-rpc-001 rpc)"
rollup_manager_addr="0x2F50ef6b8e8Ee4E579B17619A92dE3E2ffbD8AD2"
rollup_id=1

# LOCAL KURTOSIS-CDK-ERIGON (XAVI)
# l1_rpc_url="$(kurtosis port print "$enclave" el-1-geth-lighthouse rpc)"
# l2_sequencer_url="$(kurtosis port print "$enclave" sequencer001 sequencer8123)"
# l2_datastreamer_url="$(kurtosis port print "$enclave" sequencer001 sequencer6900)"
# l2_rpc_url="$(kurtosis port print "$enclave" rpc001 rpc8123)"
# rollup_manager_addr="0x2F50ef6b8e8Ee4E579B17619A92dE3E2ffbD8AD2"
# rollup_id=1

# BALI
# l1_rpc_url="https://rpc2.sepolia.org"
# l2_sequencer_url="https://rpc.internal.zkevm-rpc.com"
# TODO: l2_datastreamer_url
# TODO: l2_rpc_url
# rollup_manager_addr="0xe2ef6215adc132df6913c8dd16487abf118d1764"
# rollup_id=1

# CARDONA
# l1_rpc_url="https://rpc2.sepolia.org"
# l2_sequencer_url="https://rpc.cardona.zkevm-rpc.com"
# l2_datastreamer_url="datastream.cardona.zkevm-rpc.com:6900"
# l2_rpc_url="https://etherscan.cardona.zkevm-rpc.com"
# rollup_manager_addr="0x32d33D5137a7cFFb54c5Bf8371172bcEc5f310ff"
# rollup_id=1 # rollup
# rollup_id=2 # validium

# Check if all required variables are defined.
check_variable "l1_rpc_url"
check_variable "l2_sequencer_url"
check_variable "l2_datastreamer_url"
check_variable "l2_rpc_url"
check_variable "rollup_manager_addr"
check_variable "rollup_id"

# Log config.
echo "Running sanity check script with config:"
echo -e "- L1 RPC URL:\t\t\t$l1_rpc_url"
echo -e "- L2 Sequencer URL:\t\t$l2_sequencer_url"
echo -e "- L2 Datastreamer URL:\t\t$l2_datastreamer_url"
echo -e "- L2 RPC URL:\t\t\t$l2_rpc_url"
echo -e "- Rollup Manager Address:\t$rollup_manager_addr"
echo -e "- Rollup ID:\t\t\t$rollup_id"

# Update datastreamer config. This requires the sanity check script to be run
# from the root of the kurtosis-cdk repo.
# shellcheck disable=SC2016
tomlq -Y --toml-output --in-place --arg l2_datastreamer_url "$l2_datastreamer_url" '.Online.URI = $l2_datastreamer_url' scripts/datastreamer.toml

####################################################################################################
#   _____ _   _ _   _  ____ _____ ___ ___  _   _ ____
#  |  ___| | | | \ | |/ ___|_   _|_ _/ _ \| \ | / ___|
#  | |_  | | | |  \| | |     | |  | | | | |  \| \___ \
#  |  _| | |_| | |\  | |___  | |  | | |_| | |\  |___) |
#  |_|    \___/|_| \_|\____| |_| |___\___/|_| \_|____/
#
####################################################################################################

function fetch_l2_batch_info_from_rpc() {
  local rpc_url="$1"
  local batch_number="$2"
  cast rpc --rpc-url "$rpc_url" zkevm_getBatchByNumber "$batch_number" |
    jq '.transactions = (.transactions | length) | .blocks = (.blocks | length) | del(.batchL2Data)'
}

function fetch_l2_batch_info_from_datastream() {
  local batch_number="$1"
  local result

  # This is meant to read the stream and just add all of the objects together
  # which is a little odd but would allow us to see the last unique fields.
  #
  # The tool can be found and built from source here:
  # https://github.com/0xPolygonHermez/zkevm-node/tree/develop/tools/datastreamer
  result="$(zkevm-datastreamer decode-batch --cfg scripts/datastreamer.toml --batch "$batch_number" --json | jq -s 'add')"

  local ts
  ts="$(echo "$result" | jq -r '.Timestamp' | sed 's/ .*//')"
  ts="$(printf '0x%x' "$ts")"

  jq -n \
    --argjson result "$result" \
    --arg ts "$ts" \
    '{
      localExitRoot: $result["Local Exit Root"],
      stateRoot: $result["State Root"],
      timestamp: $ts
    }'
}

function fetch_l1_batch_info() {
  local batch_number="$1"

  local sig_get_sequenced_batches='getRollupSequencedBatches(uint32,uint64)(bytes32,uint64,uint64)'
  local batch_data
  batch_data=$(cast call --json --rpc-url "$l1_rpc_url" "$rollup_manager_addr" "$sig_get_sequenced_batches" "$rollup_id" "$batch_number")

  local sig_get_stateroot='getRollupBatchNumToStateRoot(uint32,uint64)(bytes32)'
  local batch_state_root
  batch_state_root=$(cast call --json --rpc-url "$l1_rpc_url" "$rollup_manager_addr" "$sig_get_stateroot" "$rollup_id" "$batch_number")

  local timestamp
  timestamp="$(printf '0x%x\n' "$(echo "$batch_data" | jq -r '.[1]')")"

  jq --null-input \
    --argjson batch_data "$batch_data" \
    --argjson batch_state_root "$batch_state_root" \
    --arg timestamp "$timestamp" \
    '{
      accInputHash: $batch_data[0],
      timestamp: $timestamp,
      previousLastBatchSequenced: $batch_data[2],
      stateRoot: $batch_state_root[0]
    }'
}

function compare_json_full_match() {
  _compare_json "$1" "$2" "$3" "$4" false
}

function compare_json_partial_match() {
  _compare_json "$1" "$2" "$3" "$4" true
}

function _compare_json() {
  local name1="$1"
  local json1="$2"
  local name2="$3"
  local json2="$4"
  local partial_check="${5:-false}"

  # Get all keys from both JSON objects.
  local keys
  keys=$(echo "$json1 $json2" | jq -r 'keys[]' | sort -u)

  # Function to compare fields.
  compare_field() {
    local field="$1"
    local value1
    value1=$(echo "$json1" | jq -r ".$field // \"<missing>\"")
    local value2
    value2=$(echo "$json2" | jq -r ".$field // \"<missing>\"")

    if [[ "$partial_check" == true ]] && { [[ "$value1" == "<missing>" ]] || [[ "$value2" == "<missing>" ]]; }; then
      return
    fi

    if [[ "$value1" != "$value2" ]]; then
      different=true
      echo -e "❌ $field mismatch:"
      echo -e "- $name1:\t$value1"
      echo -e "- $name2:\t$value2"
      echo
    fi
  }

  # Compare all fields.
  local different=false
  for key in $keys; do
    compare_field "$key"
  done

  if [[ "$different" == false ]]; then
    echo -e "✅ The JSON objects are the same."
    return 0
  else
    echo -e "❌ The JSON objects are not the same."
    return 1
  fi
}

# Check if there are any stopped services.
if [[ "$enclave" != "" ]]; then
  echo "
####################################################################################################
#   _  ___   _ ____ _____ ___  ____ ___ ____
#  | |/ / | | |  _ \_   _/ _ \/ ___|_ _/ ___|
#  | ' /| | | | |_) || || | | \___ \| |\___ \
#  | . \| |_| |  _ < | || |_| |___) | | ___) |
#  |_|\_\\___/|_| \_\|_| \___/|____/___|____/
#
####################################################################################################
"
  stopped_services="$(kurtosis enclave inspect "$enclave" | grep STOPPED)"
  if [[ -n "$stopped_services" ]]; then
    echo "🚨 It looks like there is at least one stopped service in the enclave... Something must have halted..."
    echo "$stopped_services"
    echo

    kurtosis enclave inspect "$enclave" --full-uuids | grep STOPPED | awk '{print $2 "--" $1}' |
      while read -r container; do
        echo "Printing logs for $container"
        docker logs --tail 50 "$container"
      done
    exit 1
  else
    echo "✅ All services are running."
  fi
fi

# Fetch rollup data.
# shellcheck disable=SC2028
echo '
####################################################################################################
#   ____   ___  _     _    _   _ ____    ____    _  _____  _
#  |  _ \ / _ \| |   | |  | | | |  _ \  |  _ \  / \|_   _|/ \
#  | |_) | | | | |   | |  | | | | |_) | | | | |/ _ \ | | / _ \
#  |  _ <| |_| | |___| |__| |_| |  __/  | |_| / ___ \| |/ ___ \
#  |_| \_\\___/|_____|_____\___/|_|     |____/_/   \_\_/_/   \_\
#
####################################################################################################
'

echo "Fetching rollup data..."
sig_rollup_id_to_data='rollupIDToRollupData(uint32)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint64,uint64,uint8)'
rollup_data_json=$(cast call --json --rpc-url "$l1_rpc_url" "$rollup_manager_addr" "$sig_rollup_id_to_data" "$rollup_id")

rollup_contract=$(echo "$rollup_data_json" | jq -r '.[0]')
last_virtualized_batch=$(echo "$rollup_data_json" | jq -r '.[5]')
last_verified_batch=$(echo "$rollup_data_json" | jq -r '.[6]')
rollup_type_id=$(echo "$rollup_data_json" | jq -r '.[10]')

jq -n --argjson rollup_data "$rollup_data_json" \
  '{
  rollupContract: $rollup_data[0],
  chainId: $rollup_data[1],
  verifierAddress: $rollup_data[2],
  forkId: $rollup_data[3],
  lastLocalExitRoot: $rollup_data[4],
  lastSequencedBatch: $rollup_data[5],
  lastVerifiedBatch: $rollup_data[6],
  lastPendingState: $rollup_data[7],
  lastPendingStateConsolidated: $rollup_data[8],
  lastVerifiedBatchBeforeUpgrade: $rollup_data[9],
  rollupTypeId: $rollup_data[10],
  rollupCompatibilityId: $rollup_data[11]
}'

echo -e "\nFetching rollup type data..."
sig_rollup_type_map='rollupTypeMap(uint32)(address,address,uint64,uint8,bool,bytes32)'
rollup_type_map=$(cast call --json --rpc-url "$l1_rpc_url" "$rollup_manager_addr" "$sig_rollup_type_map" "$rollup_type_id")

jq -n \
  --argjson rollup_type_map "$rollup_type_map" \
  '{
    consensusImplementation: $rollup_type_map[0],
    verifier: $rollup_type_map[1],
    forkID: $rollup_type_map[2],
    rollupCompatibilityID: $rollup_type_map[3],
    obsolete: $rollup_type_map[4],
    genesis: $rollup_type_map[5]
  }'

consensus_type=""
da_protocol_addr=""
result=$(cast call --json --rpc-url "$l1_rpc_url" "$rollup_contract" "dataAvailabilityProtocol()(address)" 2>&1)
# shellcheck disable=SC2181
if [[ $? -eq 0 ]]; then
  consensus_type="validium"
  da_protocol_addr="$(echo "$result" | jq -r '.[0]')"
else
  consensus_type="rollup"
fi
echo -e "\nConsensus type: $consensus_type"

if [[ "$consensus_type" == "validium" ]]; then
  echo '
####################################################################################################
#   ____    _    ____
#  |  _ \  / \  / ___|
#  | | | |/ _ \| |
#  | |_| / ___ \ |___
#  |____/_/   \_\____|
#
####################################################################################################
'

  echo "Fetching DAC data..."

  sequencerAllowedToBypassDAC="$(cast call --json --rpc-url "$l1_rpc_url" "$rollup_contract" "isSequenceWithDataAvailabilityAllowed()(bool)" | jq -r '.[0]')"
  requiredAmountOfSignatures="$(cast call --json --rpc-url "$l1_rpc_url" "$da_protocol_addr" "requiredAmountOfSignatures()(uint256)" | jq -r '.[0]')"
  committeeHash="$(cast call --json --rpc-url "$l1_rpc_url" "$da_protocol_addr" "committeeHash()(bytes32)" | jq -r '.[0]')"
  members="$(cast call --json --rpc-url "$l1_rpc_url" "$da_protocol_addr" "getAmountOfMembers()(uint256)" | jq -r '.[0]')"

  jq -n \
    --arg dataAvailabilityProtocol "$da_protocol_addr" \
    --arg sequencerAllowedToBypassDAC "$sequencerAllowedToBypassDAC" \
    --arg requiredAmountOfSignatures "$requiredAmountOfSignatures" \
    --arg committeeHash "$committeeHash" \
    --arg members "$members" \
    '{
      dataAvailabilityProtocol: $dataAvailabilityProtocol,
      isSequenceWithDataAvailabilityAllowed: $sequencerAllowedToBypassDAC,
      requiredAmountOfSignatures: $requiredAmountOfSignatures,
      committeeHash: $committeeHash,
      members: $members
    }'

  echo -e "\nMembers:"
  for ((i = 0; i < "$members"; i++)); do
    member_info="$(cast call --json --rpc-url "$l1_rpc_url" "$da_protocol_addr" "members(uint256)(string,address)" "$i")"
    jq -n \
      --arg i "$i" \
      --argjson member_info "$member_info" \
      '{
        id: $i,
        url: $member_info[0],
        address: $member_info[1],
      }'
  done
fi

# shellcheck disable=SC2028
echo '
####################################################################################################
#   _____ ____  _   _ ____ _____ _____ ____    ____    _  _____ ____ _   _
#  |_   _|  _ \| | | / ___|_   _| ____|  _ \  | __ )  / \|_   _/ ___| | | |
#    | | | |_) | | | \___ \ | | |  _| | | | | |  _ \ / _ \ | || |   | |_| |
#    | | |  _ <| |_| |___) || | | |___| |_| | | |_) / ___ \| || |___|  _  |
#    |_| |_| \_\\___/|____/ |_| |_____|____/  |____/_/   \_\_| \____|_| |_|
#
####################################################################################################
'

# Fetch batch numbers.
echo "Fetching last batch numbers L2 sequencer and L2 RPC..."
sequencer_latest_batch_number="$(cast rpc --rpc-url "$l2_sequencer_url" zkevm_batchNumber | jq -r '.')"
rpc_latest_batch_number="$(cast rpc --rpc-url "$l2_rpc_url" zkevm_batchNumber | jq -r '.')"
echo "- SEQUENCER: $((sequencer_latest_batch_number))"
echo "- RPC: $((rpc_latest_batch_number))"

if [[ "$((sequencer_latest_batch_number))" -eq "$((rpc_latest_batch_number))" ]]; then
  echo -e "\n✅ Batch numbers match."
else
  echo -e "\n❌ Batch number mismatch:"
  echo "- l2_sequencer: $sequencer_latest_batch_number"
  echo "- l2_rpc:       $rpc_latest_batch_number"
fi

# Fetch batch data.
echo -e "\nFetching data from L2 sequencer..."
sequencer_trusted_batch_info="$(fetch_l2_batch_info_from_rpc "$l2_sequencer_url" "$sequencer_latest_batch_number")"
echo "Batch: $((sequencer_latest_batch_number))"
echo "$sequencer_trusted_batch_info" | jq '.'

echo -e "\nFetching data from L2 RPC..."
rpc_trusted_batch_info="$(fetch_l2_batch_info_from_rpc "$l2_rpc_url" "$rpc_latest_batch_number")"
echo "Batch: $((rpc_latest_batch_number))"
echo "$rpc_trusted_batch_info" | jq '.'

# Compare batch data (only if they match) and if the batch is closed
if [[ ("$((sequencer_latest_batch_number))" -eq "$((rpc_latest_batch_number))") && ("true" == "$(echo "$sequencer_trusted_batch_info" | jq -r '.closed')") ]]; then
  echo -e "\nComparing L2 sequencer and L2 RPC..."
  compare_json_full_match \
    "l2_sequencer" "$sequencer_trusted_batch_info" \
    "l2_rpc" "$rpc_trusted_batch_info"
fi

# shellcheck disable=SC2028
echo '
####################################################################################################
#  __     _____ ____ _____ _   _   _    _     ___ __________ ____    ____    _  _____ ____ _   _
#  \ \   / /_ _|  _ \_   _| | | | / \  | |   |_ _|__  / ____|  _ \  | __ )  / \|_   _/ ___| | | |
#   \ \ / / | || |_) || | | | | |/ _ \ | |    | |  / /|  _| | | | | |  _ \ / _ \ | || |   | |_| |
#    \ V /  | ||  _ < | | | |_| / ___ \| |___ | | / /_| |___| |_| | | |_) / ___ \| || |___|  _  |
#     \_/  |___|_| \_\|_|  \___/_/   \_\_____|___/____|_____|____/  |____/_/   \_\_| \____|_| |_|
#
####################################################################################################
'

echo "Batch: $((last_virtualized_batch))"

# Fetch batch data.
echo -e "\nFetching data from L2 RPC..."
l2_rpc_virtualized_batch_info="$(fetch_l2_batch_info_from_rpc "$l2_rpc_url" "$(printf "0x%x" "$last_virtualized_batch")")"
echo "$l2_rpc_virtualized_batch_info" | jq '.'

echo -e "\nFetching data from L2 sequencer..."
l2_sequencer_virtualized_batch_info="$(fetch_l2_batch_info_from_rpc "$l2_sequencer_url" "$(printf "0x%x" "$last_virtualized_batch")")"
echo "$l2_sequencer_virtualized_batch_info" | jq '.'

echo -e "\nFetching data from L2 datastreamer..."
l2_datastreamer_virtualized_batch_info="$(fetch_l2_batch_info_from_datastream "$((last_virtualized_batch))")"
echo "$l2_datastreamer_virtualized_batch_info" | jq '.'

# Compare batch data.
echo -e "\nComparing L2 sequencer and L2 RPC..."
compare_json_full_match \
  "l2_sequencer" "$l2_sequencer_virtualized_batch_info" \
  "l2_rpc" "$l2_rpc_virtualized_batch_info"

echo -e "\nComparing L2 datastreamer and L2 rpc..."
compare_json_partial_match \
  "l2_datastreamer" "$l2_datastreamer_virtualized_batch_info" \
  "l2_rpc" "$l2_rpc_virtualized_batch_info"

# shellcheck disable=SC2028
echo '
####################################################################################################
#  __     _______ ____  ___ _____ ___ _____ ____    ____    _  _____ ____ _   _
#  \ \   / / ____|  _ \|_ _|  ___|_ _| ____|  _ \  | __ )  / \|_   _/ ___| | | |
#   \ \ / /|  _| | |_) || || |_   | ||  _| | | | | |  _ \ / _ \ | || |   | |_| |
#    \ V / | |___|  _ < | ||  _|  | || |___| |_| | | |_) / ___ \| || |___|  _  |
#     \_/  |_____|_| \_\___|_|   |___|_____|____/  |____/_/   \_\_| \____|_| |_|
#
####################################################################################################
'

echo "Batch: $((last_verified_batch))"

# Fetch batch data.
echo -e "\nFetching data from L2 RPC..."
l2_rpc_verified_batch_info="$(fetch_l2_batch_info_from_rpc "$l2_rpc_url" "$(printf "0x%x" "$last_verified_batch")")"
echo "$l2_rpc_verified_batch_info" | jq '.'

echo -e "\nFetching data from L2 sequencer..."
l2_sequencer_verified_batch_info="$(fetch_l2_batch_info_from_rpc "$l2_sequencer_url" "$(printf "0x%x" "$last_verified_batch")")"
echo "$l2_sequencer_verified_batch_info" | jq '.'

echo -e "\nFetching data from L2 datastreamer..."
l2_datastreamer_verified_batch_info="$(fetch_l2_batch_info_from_datastream "$((last_verified_batch))")"
echo "$l2_datastreamer_verified_batch_info" | jq '.'

echo -e "\nFetching data from L1 RollupManager contract..."
l1_verified_batch_info="$(fetch_l1_batch_info "$last_verified_batch")"
echo "$l1_verified_batch_info" | jq '.'

# Compare batch data.
echo -e "\nComparing L2 sequencer and L2 RPC..."
compare_json_full_match \
  "l2_sequencer" "$l2_sequencer_verified_batch_info" \
  "l2_rpc" "$l2_rpc_verified_batch_info"

echo -e "\nComparing L2 datastreamer and L2 rpc..."
compare_json_partial_match \
  "l2_datastreamer" "$l2_datastreamer_verified_batch_info" \
  "l2_rpc" "$l2_rpc_verified_batch_info"

echo -e "\nComparing L2 sequencer and L1 contracts..."
compare_json_partial_match \
  "l2_sequencer" "$l2_sequencer_verified_batch_info" \
  "l1_contract" "$l1_verified_batch_info"

echo -e "\nComparing L2 RPC and L1 contracts..."
compare_json_partial_match \
  "l2_rpc" "$l2_rpc_verified_batch_info" \
  "l1_contract" "$l1_verified_batch_info"

# shellcheck disable=SC2028
echo '
####################################################################################################
#   ____    _  _____ ____ _   _    ____    _    ____
#  | __ )  / \|_   _/ ___| | | |  / ___|  / \  |  _ \
#  |  _ \ / _ \ | || |   | |_| | | |  _  / _ \ | |_) |
#  | |_) / ___ \| || |___|  _  | | |_| |/ ___ \|  __/
#  |____/_/   \_\_| \____|_| |_|  \____/_/   \_\_|
#
####################################################################################################
'

sequencer_latest_trusted_batch_number="$(cast rpc --rpc-url "$l2_sequencer_url" zkevm_batchNumber | jq -r '.')"
sequencer_latest_virtualized_batch_number="$(cast rpc --rpc-url "$l2_sequencer_url" zkevm_virtualBatchNumber | jq -r '.')"
sequencer_latest_verified_batch_number="$(cast rpc --rpc-url "$l2_sequencer_url" zkevm_verifiedBatchNumber | jq -r '.')"
sequencer_virtualized_to_trusted_gap="$(($((sequencer_latest_trusted_batch_number)) - $((sequencer_latest_virtualized_batch_number))))"
sequencer_verified_to_trusted_gap="$(($((sequencer_latest_trusted_batch_number)) - $((sequencer_latest_verified_batch_number))))"
echo "L2 Sequencer"
echo -e "- Trusted:\t$((sequencer_latest_trusted_batch_number))"
echo -e "- Virtual:\t$((sequencer_latest_virtualized_batch_number)) ($sequencer_virtualized_to_trusted_gap)"
echo -e "- Verified:\t$((sequencer_latest_verified_batch_number)) ($sequencer_verified_to_trusted_gap)"

rpc_latest_trusted_batch_number="$(cast rpc --rpc-url "$l2_rpc_url" zkevm_batchNumber | jq -r '.')"
rpc_latest_virtualized_batch_number="$(cast rpc --rpc-url "$l2_rpc_url" zkevm_virtualBatchNumber | jq -r '.')"
rpc_latest_verified_batch_number="$(cast rpc --rpc-url "$l2_rpc_url" zkevm_verifiedBatchNumber | jq -r '.')"
rpc_virtualized_to_trusted_gap="$(($((rpc_latest_trusted_batch_number)) - $((rpc_latest_virtualized_batch_number))))"
rpc_verified_to_trusted_gap="$(($((rpc_latest_trusted_batch_number)) - $((rpc_latest_verified_batch_number))))"
echo -e "\nL2 RPC"
echo -e "- Trusted:\t$((rpc_latest_trusted_batch_number))"
echo -e "- Virtual:\t$((rpc_latest_virtualized_batch_number)) ($rpc_virtualized_to_trusted_gap)"
echo -e "- Verified:\t$((rpc_latest_verified_batch_number)) ($rpc_verified_to_trusted_gap)"

echo -e "\nL1 RollupManager Contract"
echo -e "- Virtual:\t$last_virtualized_batch"
echo -e "- Verified:\t$last_verified_batch"
