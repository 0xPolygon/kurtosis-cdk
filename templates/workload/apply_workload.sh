#!/bin/bash
set -e

echo "Applying workload..."
while true; do
  # shellcheck disable=SC1054,SC1083
  {{range .commands}}
  # shellcheck disable=SC1054,SC1083
  {{.}} &
  # shellcheck disable=SC1056,SC1072,SC1073,SC1009
  {{end}}
  sleep 120
done