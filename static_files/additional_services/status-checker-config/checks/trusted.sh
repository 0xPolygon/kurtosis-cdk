#!/usr/bin/env bash

state_file="./trusted.env"
error=0

# shellcheck source=/dev/null
[[ -f "$state_file" ]] && source "$state_file"

previous_trusted_bn="${previous_trusted_bn:-0}"
previous_trusted_bn_idle_counter="${previous_trusted_bn_idle_counter:-0}"

trusted_bn="$(cast to-dec "$(cast rpc --rpc-url "$L2_RPC_URL" zkevm_batchNumber | sed 's/\"//g')")"
echo "[Trusted] Batch Number: ${trusted_bn}"

if [[ "$trusted_bn" -gt "$previous_trusted_bn" ]]; then
  previous_trusted_bn="$trusted_bn"
  previous_trusted_bn_idle_counter=0
else
  previous_trusted_bn_idle_counter=$((previous_trusted_bn_idle_counter + 1))
  if [[ "$previous_trusted_bn_idle_counter" -ge 12 ]]; then
    echo "ERROR: Trusted batch number is stuck."
    error=1
  fi
fi

cat > "$state_file" <<EOF
previous_trusted_bn=${previous_trusted_bn}
previous_trusted_bn_idle_counter=${previous_trusted_bn_idle_counter}
EOF

exit $error
