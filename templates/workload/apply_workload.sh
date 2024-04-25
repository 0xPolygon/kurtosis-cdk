#!/bin/bash
set -e

echo "Applying workload..."
while true; do
  {{range .commands}}
  {{.}} &
  {{end}}
  sleep 120
done