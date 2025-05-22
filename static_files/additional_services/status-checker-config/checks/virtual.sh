#!/usr/bin/env bash

state_file="./virtual.env"
error=0

# shellcheck source=/dev/null
[[ -f "$state_file" ]] && source "$state_file"

previous_virtual_bn="${previous_virtual_bn:-0}"
previous_virtual_bn_idle_counter="${previous_virtual_bn_idle_counter:-0}"

virtual_bn="$(cast to-dec "$(cast rpc --rpc-url "$L2_RPC_URL" zkevm_virtualBatchNumber | sed 's/\"//g')")"
echo "[Virtual] Batch Number: ${virtual_bn}"

if [[ "$virtual_bn" -gt "$previous_virtual_bn" ]]; then
  previous_virtual_bn="$virtual_bn"
  previous_virtual_bn_idle_counter=0
else
  previous_virtual_bn_idle_counter=$((previous_virtual_bn_idle_counter + 1))
  if [[ "$previous_virtual_bn_idle_counter" -ge 12 ]]; then
    echo "ERROR: Virtual batch number is stuck."
    error=1
  fi
fi

cat > "$state_file" <<EOF
previous_virtual_bn=${previous_virtual_bn}
previous_virtual_bn_idle_counter=${previous_virtual_bn_idle_counter}
EOF

exit $error
