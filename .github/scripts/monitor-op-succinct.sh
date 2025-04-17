#!/bin/bash
set -euo pipefail

ENCLAVE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --enclave)
            ENCLAVE="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

if [[ -z "$ENCLAVE" ]]; then
    echo "Error: --enclave argument is required"
    exit 1
fi

check_logs() {
    local service=$1
    echo "Checking logs for $service..."
    
    logs=$(kurtosis service logs "$ENCLAVE" "$service")
    if echo "$logs" | grep -iE "crit|error" > /dev/null; then
        echo "Found critical/error logs in $service:"
        echo "$logs" | grep -iE "crit|error"
        return 1
    else
        echo "No critical/error logs found in $service"
        return 0
    fi
}

errors=0

sleep 5
# Check proposer logs
if ! check_logs "op-succinct-proposer-001"; then
    errors=$((errors + 1))
fi

sleep 5
# Check server logs
if ! check_logs "op-succinct-server-001"; then
    errors=$((errors + 1))
fi

if [ $errors -gt 0 ]; then
    echo "Found errors in service logs"
    exit 1
fi

echo "All services logs clear of critical/error messages"
exit 0