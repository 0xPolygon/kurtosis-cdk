#!/usr/bin/env bash

# shellcheck source=static_files/additional_services/status-checker/checks/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib.sh"

check_consensus pessimistic fep
check_certificate_height settled interop_getLatestSettledCertificateHeader
exit $?
