#!/usr/bin/env bash
set -euo pipefail

# This script monitors the progress of a blockchain rollup.
# Usage: ./monitor.sh <enclave_name> <sequencer_type> <consensus_contract_type>
# Example: ./monitor.sh cdk op-geth ecdsa-multisig

# Helper function to get the current timestamp
_timestamp() { date +"%Y-%m-%d %H:%M:%S"; }

# Helper function to format key=value pairs
_format_fields() {
  local msg="$1"
  shift
  local fields=""
  for arg in "$@"; do
    fields="$fields $arg"
  done
  echo "$msg$fields"
}

# Logging functions
log_info() { echo "$(_timestamp) INFO $(_format_fields "$@")" >&2; }
log_error() { echo "$(_timestamp) ERROR $(_format_fields "$@")" >&2; }

log_info "Monitoring rollup progress"

# Validate input parameters
enclave_name=${1:-"cdk"}
if [[ -z "${enclave_name}" ]]; then
  log_error "Enclave name must be provided"
  exit 1
fi
log_info "Using enclave name: ${enclave_name}"

sequencer_type=${2:-"op-geth"}
if [[ -z "${sequencer_type}" ]]; then
  log_error "Sequencer type must be provided"
  exit 1
fi
log_info "Using sequencer type: ${sequencer_type}"

consensus_contract_type=${3:-"ecdsa-multisig"}
if [[ -z "${consensus_contract_type}" ]]; then
  log_error "Consensus contract type must be provided"
  exit 1
fi
log_info "Using consensus contract type: ${consensus_contract_type}"

# Determine the rpc service and url based on the sequencer type
rpc_name=""
case "${sequencer_type}" in
  "cdk-erigon")
    rpc_name="cdk-erigon-rpc-001"
    ;;
  "op-geth")
    rpc_name="op-el-1-op-geth-op-node-001"
    ;;
  *)
    log_error "Unsupported sequencer type: ${sequencer_type}"
    exit 1
    ;;
esac
log_info "Using rpc name: ${rpc_name}"

rpc_url=$(kurtosis port print "${enclave_name}" "${rpc_name}" rpc)
log_info "Using rpc url: ${rpc_url}"

# Determine the target based on the consensus contract type
target=""
case "${sequencer_type}" in
  "cdk-erigon")
    target=20 # batches
    ;;
  "op-geth")
    target=50 # blocks
    ;;
  *)
    log_error "Unsupported sequencer type: ${sequencer_type}"
    exit 1
    ;;
esac
log_info "Using target: ${target}"

# Monitor the rollup progress
num_steps=100
gas_price_factor=1
for step in $(seq 1 "${num_steps}"); do
  log_info "Check ${step}/${num_steps}"

  case "${consensus_contract_type}" in
    "rollup"|"cdk-validium")
      LATEST_BATCH=$(cast to-dec "$(cast rpc zkevm_batchNumber --rpc-url "${rpc_url}" | sed 's/"//g')")
      VIRTUAL_BATCH=$(cast to-dec "$(cast rpc zkevm_virtualBatchNumber --rpc-url "${rpc_url}" | sed 's/"//g')")
      VERIFIED_BATCH=$(cast to-dec "$(cast rpc zkevm_verifiedBatchNumber --rpc-url "${rpc_url}" | sed 's/"//g')")
      log_info "Got batches: latest=${LATEST_BATCH}, virtual=${VIRTUAL_BATCH}, verified=${VERIFIED_BATCH}"
      if [[ "${LATEST_BATCH}" -ge "${target}" && "${VIRTUAL_BATCH}" -ge "${target}" && "${VERIFIED_BATCH}" -ge "${target}" ]]; then
        log_info "Target batches reached for all batch types (latest, virtual and verified)"
        exit 0
      fi
      ;;
    "pessimistic"|"ecdsa-multisig")
      case "${sequencer_type}" in
        "cdk-erigon")
          LATEST_BATCH=$(cast to-dec "$(cast rpc zkevm_batchNumber --rpc-url "${rpc_url}" | sed 's/"//g')")
          log_info "Got batches: latest=${LATEST_BATCH}"
          if [[ "${LATEST_BATCH}" -ge "${target}" ]]; then
            log_info "Target batches reached for latest batch type"
            exit 0
          fi
          ;;
        "op-geth")
          LATEST_BLOCK=$(cast bn --rpc-url "${rpc_url}")
          SAFE_BLOCK=$(cast bn safe --rpc-url "${rpc_url}")
          FINALIZED_BLOCK=$(cast bn finalized --rpc-url "${rpc_url}")
          log_info "Got blocks: latest=${LATEST_BLOCK}, safe=${SAFE_BLOCK}, finalized=${FINALIZED_BLOCK}"
          if [[ "${LATEST_BLOCK}" -ge "${target}" && "${SAFE_BLOCK}" -ge "${target}" && "${FINALIZED_BLOCK}" -ge "${target}" ]]; then
            log_info "Target blocks reached for all block types (latest, safe and finalized)"
            exit 0
          fi
          ;;
        *)
          log_error "Unsupported sequencer type: ${sequencer_type}"
          exit 1
          ;;
      esac
      ;;
    "fep")
      LATEST_BLOCK=$(cast bn --rpc-url "${rpc_url}")
      SAFE_BLOCK=$(cast bn safe --rpc-url "${rpc_url}")
      FINALIZED_BLOCK=$(cast bn finalized --rpc-url "${rpc_url}")
      log_info "Got blocks: latest=${LATEST_BLOCK}, safe=${SAFE_BLOCK}, finalized=${FINALIZED_BLOCK}"
      if [[ "${LATEST_BLOCK}" -ge "${target}" && "${SAFE_BLOCK}" -ge "${target}" && "${FINALIZED_BLOCK}" -ge "${target}" ]]; then
        log_info "Target blocks reached for all block types (latest, safe and finalized)"
        exit 0
      fi
      ;;
    *)
      log_error "Unsupported consensus contract type: ${consensus_contract_type}"
      exit 1
      ;;
  esac

  # Send a transaction to stimulate progress
  gas_price=$(cast gas-price --rpc-url "$rpc_url")
  gas_price=$(bc -l <<< "$gas_price * $gas_price_factor" | sed 's/\..*//')

  log_info "Sending a test transaction"
  cast send \
    --legacy \
    --timeout 30 \
    --gas-price "${gas_price}" \
    --rpc-url "${rpc_url}" \
    --private-key "0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625" \
    --gas-limit 100000 \
    --create 0x6001617000526160006110005ff05b6109c45a111560245761600061100080833c600e565b50
  result="$?"
  if [[ "${result}" -eq 0 ]]; then
    gas_price_factor=1
  else
    gas_price_factor=$(bc -l <<< "$gas_price_factor * 1.5")
  fi

  sleep 5
done

# If the code reaches here, the target was not met within the allowed steps
case "${consensus_contract_type}" in
  "rollup"|"cdk-validium")
    log_error "Target batches have not been reached for all batch types (latest, virtual and verified)"
    ;;
  "pessimistic"|"ecdsa-multisig")
    case "${sequencer_type}" in
      "cdk-erigon")
        log_error "Target batches have not been reached for latest batch type"
        ;;
      "op-geth")
        log_error "Target blocks have not been reached for all block types (latest, safe and finalized)"
        ;;
      *)
        log_error "Unsupported sequencer type: ${sequencer_type}"
        exit 1
        ;;
    esac
    ;;
  "fep")
    log_error "Target blocks have not been reached for all block types (latest, safe and finalized)"
    ;;
  *)
    log_error "Unsupported consensus contract type: ${consensus_contract_type}"
    exit 1
    ;;
esac
exit 1
