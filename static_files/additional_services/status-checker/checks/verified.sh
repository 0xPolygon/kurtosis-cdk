#!/usr/bin/env bash

# shellcheck source=static_files/additional_services/status-checker/checks/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

check_consensus rollup cdk-validium
check_batch verified "zkevm_verifiedBatchNumber"
