#!/usr/bin/env bash
set -euo pipefail

# This script monitors the progress of a blockchain rollup.
# Usage: ./monitor.sh <enclave_name> <sequencer_type> <consensus_contract_type>
# Example: ./monitor.sh cdk op-geth ecdsa-multisig

timestamp() { date +"%Y-%m-%d %H:%M:%S"; }
log_info() { echo "$(timestamp) INFO $(_format_fields "$@")" >&2; }
log_error() { echo "$(timestamp) ERROR $(_format_fields "$@")" >&2; }

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

# Determine the RPC service to use based on the sequencer type
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
log_info "Using RPC name: ${rpc_name}"

rpc_url=$(kurtosis port print "${enclave_name}" "${rpc_name}" rpc)
log_info "Using RPC URL: ${rpc_url}"

# Monitor the rollup progress
target=50
num_steps=100
for step in $(seq 1 "${num_steps}"); do
  log_info "Check ${step}/${num_steps}..."

  case "${consensus_contract_type}" in
    "rollup"|"cdk-validium")
      LATEST_BATCH=$(cast to-dec "$(cast rpc zkevm_batchNumber --rpc-url "${rpc_url}" | sed 's/"//g')")
      VIRTUAL_BATCH=$(cast to-dec "$(cast rpc zkevm_virtualBatchNumber --rpc-url "${rpc_url}" | sed 's/"//g')")
      VERIFIED_BATCH=$(cast to-dec "$(cast rpc zkevm_verifiedBatchNumber --rpc-url "${rpc_url}" | sed 's/"//g')")
      log_info "Got batches: latest=${LATEST_BATCH}, virtual=${VIRTUAL_BATCH}, verified=${VERIFIED_BATCH}"
      if [[ "${LATEST_BATCH}" -gt "${target}" && "${VIRTUAL_BATCH}" -gt "${target}" && "${VERIFIED_BATCH}" -gt "${target}" ]]; then
        log_info "Target batches reached for all batch types ${target} (latest, virtual and verified)"
        exit 0
      fi
      ;;
    "pessimistic"|"ecdsa-multisig"|"fep")
      LATEST_BLOCK=$(cast bn --rpc-url "${rpc_url}")
      SAFE_BLOCK=$(cast bn safe --rpc-url "${rpc_url}")
      FINALIZED_BLOCK=$(cast bn finalized --rpc-url "${rpc_url}")
      log_info "Got blocks: latest=${LATEST_BLOCK}, safe=${SAFE_BLOCK}, finalized=${FINALIZED_BLOCK}"
      if [[ "${LATEST_BLOCK}" -gt "${target}" && "${SAFE_BLOCK}" -gt "${target}" && "${FINALIZED_BLOCK}" -gt "${target}" ]]; then
        log_info "Target blocks reached for all block types ${target} (latest, safe and finalized)"
        exit 0
      fi
      ;;
    *)
      log_error "Unsupported consensus contract type: ${consensus_contract_type}"
      exit 1
      ;;
  esac

  sleep 5
done

case "${consensus_contract_type}" in
  "rollup"|"cdk-validium")
    log_error "Target batches have not been reached for all batch types (latest, virtual and verified)"
    ;;
  "pessimistic"|"ecdsa-multisig"|"fep")
    log_error "Target blocks have not been reached for all block types (latest, safe and finalized)"
    ;;
  *)
    log_error "Unsupported consensus contract type: ${consensus_contract_type}"
    exit 1
    ;;
esac
exit 1
