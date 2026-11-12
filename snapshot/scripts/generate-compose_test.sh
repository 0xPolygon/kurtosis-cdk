#!/usr/bin/env bash
#
# Test for generate-compose.sh --flavor anvil-aggkit: the real generator runs
# against a small crafted topology (two L2s) and the resulting compose files
# are inspected through `docker compose config` (no daemon access needed).
#
# Asserts that
#  - both compose variants resolve and define the nine expected services;
#  - every published port binds to 127.0.0.1 by default, and to the address
#    in BIND_ADDRESS when it is set;
#  - the host ports stay individually overridable;
#  - the generated docker-compose.yml passes verify-healthchecks.sh.
#
# Usage: ./generate-compose_test.sh   (run from anywhere; needs docker compose)
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

if ! docker compose version > /dev/null 2>&1; then
    echo "generate-compose_test.sh: 'docker compose' is required" >&2
    exit 1
fi

fail_count=0
fail() {
    echo "FAIL: $*" >&2
    fail_count=$((fail_count + 1))
}
ok() {
    echo "OK: $*"
}

bundle="${work_dir}/bundle"
mkdir -p "${bundle}/state" "${bundle}/images"
cat > "${bundle}/state/state-metadata.json" <<'JSON'
{"flavor": "anvil-aggkit", "settlement_free": true, "chains": [
  {"service": "anvil-001", "role": "l1", "chain_id": 271828, "network_id": 0},
  {"service": "l2-anvil-001", "role": "l2", "prefix": "001", "chain_id": 20201, "network_id": 1},
  {"service": "l2-anvil-002", "role": "l2", "prefix": "002", "chain_id": 20202, "network_id": 2}]}
JSON
cat > "${bundle}/images/IMAGE_INFO.json" <<'JSON'
{"flavor": "anvil-aggkit", "tag": "t", "image_prefix": "snapshot-", "images": {
  "anvil-001": {"name": "snapshot-anvil-001:t", "base_image": "ghcr.io/foundry-rs/foundry:v1.9.0"},
  "agglayer": {"name": "snapshot-agglayer:t", "base_image": "ghcr.io/agglayer/agglayer:0.6.2"},
  "aggkit-001": {"name": "snapshot-aggkit-001:t", "base_image": "ghcr.io/agglayer/aggkit:0.11.1"},
  "aggkit-002": {"name": "snapshot-aggkit-002:t", "base_image": "ghcr.io/agglayer/aggkit:0.11.1"},
  "aggkit-proxy-001": {"name": "snapshot-aggkit-proxy-001:t", "base_image": "ghcr.io/agglayer/aggkit:0.11.1"}}}
JSON
jq '.haproxy = {found: true, service_name: "agglayer-dev-ui-proxy-001", container_name: "h"}
    | .dev_ui = {found: true, service_name: "agglayer-dev-ui-002", container_name: "d"}' \
    "${script_dir}/testdata/extract-state-config-tree/discovery.json" > "${work_dir}/discovery.json"

if "${script_dir}/generate-compose.sh" --flavor anvil-aggkit "${work_dir}/discovery.json" "${bundle}" > "${work_dir}/generate.log" 2>&1; then
    ok "generate-compose.sh ran cleanly"
else
    fail "generate-compose.sh failed:"; cat "${work_dir}/generate.log" >&2
fi

# resolved <file> [ENV=value ...] -> compose model as JSON
resolved() {
    local file="$1"
    shift
    env "$@" docker compose -f "${bundle}/${file}" --profile '*' config --format json
}

for file in docker-compose.yml docker-compose.mounts.yml; do
    if ! model=$(resolved "${file}"); then
        fail "${file}: docker compose config failed"
        continue
    fi
    if [ "$(jq '.services | length' <<< "${model}")" -eq 9 ]; then
        ok "${file}: nine services"
    else
        fail "${file}: expected nine services, got $(jq '.services | keys' <<< "${model}")"
    fi
    hosts=$(jq -c '[.services[].ports[]?.host_ip] | unique' <<< "${model}")
    if [ "${hosts}" = '["127.0.0.1"]' ]; then
        ok "${file}: every published port binds to 127.0.0.1 by default"
    else
        fail "${file}: published ports bind to ${hosts}, expected [\"127.0.0.1\"]"
    fi
    if [ "$(jq '[.services[].ports[]?] | length' <<< "${model}")" -ge 14 ]; then
        ok "${file}: the ports are present (not an empty list)"
    else
        fail "${file}: fewer than 14 published ports"
    fi
    model_open=$(resolved "${file}" BIND_ADDRESS=0.0.0.0)
    hosts=$(jq -c '[.services[].ports[]?.host_ip] | unique' <<< "${model_open}")
    if [ "${hosts}" = '["0.0.0.0"]' ]; then
        ok "${file}: BIND_ADDRESS=0.0.0.0 opens every published port"
    else
        fail "${file}: with BIND_ADDRESS=0.0.0.0 the ports bind to ${hosts}"
    fi
    model_port=$(resolved "${file}" DEVNET_PROXY_PORT=9555)
    if jq -e '[.services[].ports[]? | select(.target == 80 and .published == "9555")] | length == 1' <<< "${model_port}" > /dev/null; then
        ok "${file}: DEVNET_PROXY_PORT still overrides the haproxy host port"
    else
        fail "${file}: DEVNET_PROXY_PORT=9555 did not change the haproxy host port"
    fi
done

if "${script_dir}/verify-healthchecks.sh" --flavor anvil-aggkit "${bundle}" > "${work_dir}/healthchecks.log" 2>&1; then
    ok "the generated docker-compose.yml passes verify-healthchecks.sh"
else
    fail "verify-healthchecks.sh rejected the generated compose file:"; cat "${work_dir}/healthchecks.log" >&2
fi

echo
if [ "${fail_count}" -gt 0 ]; then
    echo "generate-compose_test.sh: ${fail_count} assertion(s) FAILED" >&2
    exit 1
fi
echo "generate-compose_test.sh: all assertions passed"
