#!/usr/bin/env bash

# shellcheck source=static_files/additional_services/status-checker-config/checks/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib.sh"

check_consensus pessimistic fep
check_certificate_height pending interop_getLatestPendingCertificateHeader
exit $?
