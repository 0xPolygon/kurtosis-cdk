#!/usr/bin/env bash
#
# Test for verify-healthchecks.sh --flavor anvil-aggkit. It writes small
# compose files, runs the real script (with the real `docker compose config`,
# no daemon access needed) and checks that a sound bundle passes and that each
# kind of defect makes it fail: a missing component, a missing, disabled or
# commented-out healthcheck, an ungated depends_on, a bind mount or named
# volume, and a wrong profile gate. The defects are placed in the profile-gated
# dev-ui as well, the service a plain `config` does not show.
#
# Usage: ./verify-healthchecks_test.sh   (run from anywhere; needs docker compose)
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
verify="${script_dir}/verify-healthchecks.sh"
work_dir="$(mktemp -d)"
trap '[ -n "${KEEP:-}" ] || rm -rf "${work_dir}"' EXIT

if ! docker compose version > /dev/null 2>&1; then
    echo "verify-healthchecks_test.sh: 'docker compose' is required" >&2
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

# service <name> [extra yaml lines, already indented by 4] -- a healthy service
# gated on the L1 anvil.
service() {
    local name="$1" extra="${2:-}"
    echo "  ${name}:"
    echo "    image: example/${name}:t"
    if [ "${name}" != "anvil-001" ]; then
        printf '    depends_on:\n      anvil-001:\n        condition: service_healthy\n'
    fi
    printf '    healthcheck:\n      test: ["CMD", "true"]\n      interval: 1s\n'
    if [ -n "${extra}" ]; then printf '%s\n' "${extra}"; fi
}

# compose <file> [service=extra ...]: the nine-service bundle; each argument
# adds extra lines to one service. A service named "-name" is left out.
compose() {
    local file="$1"
    shift
    local -A extras=() skip=()
    local arg name extra
    for arg in "$@"; do
        case "${arg}" in
            -*) skip["${arg#-}"]=1 ;;
            *) extras["${arg%%=*}"]="${arg#*=}" ;;
        esac
    done
    {
        echo "services:"
        for name in anvil-001 l2-anvil-001 l2-anvil-002 aggkit-001 aggkit-002 agglayer aggkit-proxy-001 agglayer-dev-ui-proxy-001 agglayer-dev-ui-002; do
            [ -z "${skip[${name}]:-}" ] || continue
            extra="${extras[${name}]:-}"
            if [ "${name}" = "agglayer-dev-ui-002" ] && [ -z "${extras[${name}]+x}" ]; then
                extra='    profiles: ["devui"]'
            fi
            service "${name}" "${extra}"
        done
    } > "${file}"
}

# check <name> <pass|fail> [compose args...]
check() {
    local name="$1" want="$2"
    shift 2
    local dir="${work_dir}/${name}"
    mkdir -p "${dir}"
    compose "${dir}/docker-compose.yml" "$@"
    local rc=0
    "${verify}" --flavor anvil-aggkit "${dir}" > "${dir}.out" 2>&1 || rc=$?
    if [ "${want}" = "pass" ] && [ "${rc}" -eq 0 ]; then
        ok "${name}: accepted"
    elif [ "${want}" = "fail" ] && [ "${rc}" -ne 0 ]; then
        ok "${name}: rejected (rc ${rc})"
    else
        fail "${name}: expected ${want}, exit status ${rc} -- output:"
        cat "${dir}.out" >&2
    fi
}

check sound pass

check missing-aggkit fail "-aggkit-002"
check missing-agglayer fail "-agglayer"
check missing-dev-ui fail "-agglayer-dev-ui-002"
check missing-haproxy fail "-agglayer-dev-ui-proxy-001"
check missing-proxy fail "-aggkit-proxy-001"
check missing-l1 fail "-anvil-001"
check no-l2 fail "-l2-anvil-001" "-l2-anvil-002" "-aggkit-001" "-aggkit-002"

# A service without a healthcheck, and one whose block only mentions the word.
{
    dir="${work_dir}/healthcheck-removed"
    mkdir -p "${dir}"
    compose "${dir}/docker-compose.yml"
    python3 - "${dir}/docker-compose.yml" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('''  agglayer:
    image: example/agglayer:t
    depends_on:
      anvil-001:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "true"]
      interval: 1s
''', '''  agglayer:
    image: example/agglayer:t
    depends_on:
      anvil-001:
        condition: service_healthy
''')
open(p, 'w').write(s)
PY
    rc=0
    "${verify}" --flavor anvil-aggkit "${dir}" > "${dir}.out" 2>&1 || rc=$?
    if [ "${rc}" -ne 0 ]; then ok "healthcheck-removed: rejected (rc ${rc})"; else fail "healthcheck-removed: accepted"; fi
    # A comment that mentions the word must not stand in for the block.
    sed -i 's|^    image: example/agglayer:t|    image: example/agglayer:t\n    # healthcheck: removed on purpose|' "${dir}/docker-compose.yml"
    rc=0
    "${verify}" --flavor anvil-aggkit "${dir}" > "${dir}.out" 2>&1 || rc=$?
    if [ "${rc}" -ne 0 ]; then ok "healthcheck-in-comment-only: rejected (rc ${rc})"; else fail "healthcheck-in-comment-only: accepted"; cat "${dir}.out" >&2; fi
}

{
    dir="${work_dir}/disable-true"
    mkdir -p "${dir}"
    compose "${dir}/docker-compose.yml"
    sed -i '/^  aggkit-002:/,/^  agglayer:/ s|      interval: 1s|      interval: 1s\n      disable: true|' "${dir}/docker-compose.yml"
    rc=0
    "${verify}" --flavor anvil-aggkit "${dir}" > "${dir}.out" 2>&1 || rc=$?
    if [ "${rc}" -ne 0 ]; then ok "disable-true: rejected (rc ${rc})"; else fail "disable-true: accepted"; cat "${dir}.out" >&2; fi
}

{
    dir="${work_dir}/ungated"
    mkdir -p "${dir}"
    compose "${dir}/docker-compose.yml"
    sed -i '/^  aggkit-001:/,/^  aggkit-002:/ s|        condition: service_healthy|        condition: service_started|' "${dir}/docker-compose.yml"
    rc=0
    "${verify}" --flavor anvil-aggkit "${dir}" > "${dir}.out" 2>&1 || rc=$?
    if [ "${rc}" -ne 0 ]; then ok "ungated-depends-on: rejected (rc ${rc})"; else fail "ungated-depends-on: accepted"; fi

    # The same defect in the profile-gated dev-ui, written as a list.
    dir="${work_dir}/ungated-devui"
    mkdir -p "${dir}"
    compose "${dir}/docker-compose.yml"
    python3 - "${dir}/docker-compose.yml" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
marker = '  agglayer-dev-ui-002:\n    image: example/agglayer-dev-ui-002:t\n    depends_on:\n      anvil-001:\n        condition: service_healthy\n'
assert marker in s
s = s.replace(marker, '  agglayer-dev-ui-002:\n    image: example/agglayer-dev-ui-002:t\n    depends_on: [anvil-001]\n')
open(p, 'w').write(s)
PY
    rc=0
    "${verify}" --flavor anvil-aggkit "${dir}" > "${dir}.out" 2>&1 || rc=$?
    if [ "${rc}" -ne 0 ]; then ok "ungated-depends-on-devui: rejected (rc ${rc})"; else fail "ungated-depends-on-devui: accepted"; cat "${dir}.out" >&2; fi
}

check bind-mount fail $'aggkit-001=    volumes:\n      - ./cfg:/cfg'
check bind-mount-devui fail $'agglayer-dev-ui-002=    profiles: ["devui"]\n    volumes:\n      - ./cfg:/cfg'
check dev-ui-loses-profile fail 'agglayer-dev-ui-002='
check other-service-profiled fail 'aggkit-001=    profiles: ["extra"]'

echo
if [ "${fail_count}" -gt 0 ]; then
    echo "verify-healthchecks_test.sh: ${fail_count} assertion(s) FAILED" >&2
    exit 1
fi
echo "verify-healthchecks_test.sh: all assertions passed"
