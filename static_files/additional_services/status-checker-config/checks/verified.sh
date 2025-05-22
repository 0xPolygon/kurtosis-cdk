#!/usr/bin/env bash

state_file="./verified.env"
error=0

# shellcheck source=/dev/null
[[ -f "$state_file" ]] && source "$state_file"

previous_verified_bn="${previous_verified_bn:-0}"
previous_verified_bn_idle_counter="${previous_verified_bn_idle_counter:-0}"

verified_bn="$(cast to-dec "$(cast rpc --rpc-url "$L2_RPC_URL" zkevm_verifiedBatchNumber | sed 's/\"//g')")"
echo "[Verified] Batch Number: ${verified_bn}"

if [[ "$verified_bn" -gt "$previous_verified_bn" ]]; then
  previous_verified_bn="$verified_bn"
  previous_verified_bn_idle_counter=0
else
  previous_verified_bn_idle_counter=$((previous_verified_bn_idle_counter + 1))
  if [[ "$previous_verified_bn_idle_counter" -ge 12 ]]; then
    echo "ERROR: Verified batch number is stuck."
    error=1
  fi
fi

cat > "$state_file" <<EOF
previous_verified_bn=${previous_verified_bn}
previous_verified_bn_idle_counter=${previous_verified_bn_idle_counter}
EOF

exit $error
