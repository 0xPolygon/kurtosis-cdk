#!/usr/bin/env bash
#
# Unit test for the helpers of lib/verify-anvil-aggkit.sh that can be tested
# without a running bundle: the Go-duration parser behind the RetentionPeriod
# check and the teardown that runs when a verification ends.
#
# Usage: ./verify-anvil-aggkit_test.sh   (run from anywhere; python3 required)
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

# The library reuses the logging helpers of verify.sh.
log_info() { :; }
# shellcheck disable=SC1090,SC1091 # script_dir is resolved at runtime relative to this file (SC1090 on older shellcheck, SC1091 on newer)
source "${script_dir}/verify-anvil-aggkit.sh"

fail_count=0
fail() {
    echo "FAIL: $*" >&2
    fail_count=$((fail_count + 1))
}
ok() {
    echo "OK: $*"
}

# ---- duration_to_seconds ---------------------------------------------------
check_duration() {
    local input="$1" want="$2" got rc=0
    got=$(duration_to_seconds "${input}" 2> /dev/null) || rc=$?
    if [ "${want}" = "invalid" ]; then
        if [ "${rc}" -ne 0 ] && [ -z "${got}" ]; then ok "duration '${input}' is rejected"; else fail "duration '${input}': expected rejection, got '${got}' (rc ${rc})"; fi
    elif [ "${rc}" -eq 0 ] && [ "${got}" = "${want}" ]; then
        ok "duration '${input}' = ${got}s"
    else
        fail "duration '${input}': expected ${want}, got '${got}' (rc ${rc})"
    fi
}
check_duration 30m 1800
check_duration 1h30m 5400
check_duration 90s 90
check_duration 1.5h 5400
check_duration 30m0s 1800
check_duration 29m59s 1799
check_duration 24h 86400
check_duration 0h 0
check_duration 0 invalid
check_duration 30 invalid
check_duration "" invalid
check_duration abc invalid
check_duration "1h 30m" invalid
check_duration "-5m" invalid

# The check itself: >= 1800 seconds. `0h` and `29m59s` must not pass, `1h30m` must.
retention_ok() {
    local seconds
    seconds=$(duration_to_seconds "$1" 2> /dev/null) || return 1
    [ "${seconds}" -ge 1800 ]
}
for pass in 30m 1h 1h30m 90m; do
    if retention_ok "${pass}"; then ok "RetentionPeriod ${pass} is accepted"; else fail "RetentionPeriod ${pass} should be accepted"; fi
done
for refuse in 0h 29m59s 10m 5s bogus; do
    if retention_ok "${refuse}"; then fail "RetentionPeriod ${refuse} should be refused"; else ok "RetentionPeriod ${refuse} is refused"; fi
done

# ---- teardown ---------------------------------------------------------------
fake_bin="${work_dir}/fake-bin"
mkdir -p "${fake_bin}" "${work_dir}/bundle"
cat > "${fake_bin}/docker" <<'FAKE'
#!/usr/bin/env bash
echo "docker $*" >> "${FAKE_DOCKER_LOG}"
FAKE
chmod +x "${fake_bin}/docker"
export FAKE_DOCKER_LOG="${work_dir}/docker.log"

run_cleanup() {
    : > "${FAKE_DOCKER_LOG}"
    ANVIL_VERIFY_COMPOSE_DIR="${work_dir}/bundle"
    ANVIL_VERIFY_COMPOSE_FILE="docker-compose.yml"
    ANVIL_VERIFY_UP_LOG="${work_dir}/up.log"
    : > "${ANVIL_VERIFY_UP_LOG}"
    PATH="${fake_bin}:${PATH}" _anvil_aggkit_cleanup
}

run_cleanup
if grep -q 'compose -f docker-compose.yml --profile \* down -v' "${FAKE_DOCKER_LOG}"; then ok "cleanup: the stack is taken down with 'down -v'"; else fail "cleanup: no 'down -v': $(cat "${FAKE_DOCKER_LOG}")"; fi
if [ -e "${work_dir}/up.log" ]; then fail "cleanup: the compose log was not removed"; else ok "cleanup: the compose log is removed"; fi

SNAPSHOT_VERIFY_KEEP=true run_cleanup
if [ -s "${FAKE_DOCKER_LOG}" ]; then fail "cleanup: --keep still ran docker: $(cat "${FAKE_DOCKER_LOG}")"; else ok "cleanup: --keep leaves the stack running"; fi
if [ -e "${work_dir}/up.log" ]; then fail "cleanup: --keep did not remove the compose log"; else ok "cleanup: --keep still removes the compose log"; fi

# The exit status of the run survives the cleanup.
rc=0
(
    : > "${FAKE_DOCKER_LOG}"
    export ANVIL_VERIFY_COMPOSE_DIR="${work_dir}/bundle" ANVIL_VERIFY_COMPOSE_FILE=docker-compose.yml
    export PATH="${fake_bin}:${PATH}"
    trap '_anvil_aggkit_cleanup' EXIT
    exit 7
) || rc=$?
if [ "${rc}" -eq 7 ]; then ok "cleanup: the exit status (7) is preserved"; else fail "cleanup: exit status became ${rc}"; fi

echo
if [ "${fail_count}" -gt 0 ]; then
    echo "verify-anvil-aggkit_test.sh: ${fail_count} assertion(s) FAILED" >&2
    exit 1
fi
echo "verify-anvil-aggkit_test.sh: all assertions passed"
