#!/usr/bin/env bash
#
# dev-ui Fixture Seeding (flavor: anvil-aggkit)
#
# Deploys the ERC20 that the agglayer-dev-ui Playwright suite needs
# (tests/bridge/erc20-approve-bridge.spec.ts, via tests/e2e/globalSetup.ts) on
# the L1 anvil, minted in full to the funded E2E wallet, and records its
# address so the snapshot summary can export it as E2E_ERC20_ADDRESS. Running
# this BEFORE state capture is the whole point: the token then lives in the
# captured anvil state and dev-ui CI never has to deploy anything.
#
# The contract source is a byte-for-byte copy of dev-ui's E2E_TOKEN_SOURCE
# (tests/e2e/globalSetup.ts) so the two deploy an identical token.
#
# forge runs in a container (--network host) on purpose: a host foundry
# install is not a requirement of this tool, and several dev machines here
# have a glibc-incompatible one. The image defaults to the tag the enclave's
# own L1 anvil is running, so the snapshot can never drift from the node it
# was taken against.
#
# Usage: seed-devui-fixtures.sh <DISCOVERY_JSON> <OUTPUT_DIR> [OPTIONS]
#
# Options:
#   --erc20-address <addr>   Reuse this token if it is live and funded
#                            (skips the deploy); fails if it is not usable.
#   --foundry-image <image>  Override the containerized foundry image.
#   --wallet <addr>          E2E wallet address (default below).
#   --private-key <key>      Deployer key; must own <addr> (default below).
#

set -euo pipefail

# ----------------------------------------------------------------------------
# Defaults
# ----------------------------------------------------------------------------

# The dev-ui E2E wallet and its (public, devnet-only) key. Same pair as
# params-aggkit-anvil-l2l2-run1.yml's l2_admin_address, so it is already
# funded natively on L1 and both L2s by the enclave itself.
E2E_WALLET="0xE34aaF64b29273B7D567FCFc40544c014EEe9970"
E2E_PRIVATE_KEY="0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"

# 1000 tokens at 18 decimals -- dev-ui's INITIAL_SUPPLY.
INITIAL_SUPPLY="1000000000000000000000"

ERC20_ADDRESS=""
FOUNDRY_IMAGE="${SNAPSHOT_FOUNDRY_IMAGE:-}"

# ----------------------------------------------------------------------------
# Arguments
# ----------------------------------------------------------------------------

POSITIONAL=()
while [ $# -gt 0 ]; do
    case "$1" in
        --erc20-address) ERC20_ADDRESS="$2"; shift 2 ;;
        --foundry-image) FOUNDRY_IMAGE="$2"; shift 2 ;;
        --wallet) E2E_WALLET="$2"; shift 2 ;;
        --private-key) E2E_PRIVATE_KEY="$2"; shift 2 ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *) POSITIONAL+=("$1"); shift ;;
    esac
done

# Validate every value that later lands inside a hand-built JSON-RPC body or
# inside the single `/bin/sh -c` string handed to the foundry container. Without
# this, a crafted --erc20-address re-parses as a different `method` (last
# duplicate key wins in most JSON parsers) and a crafted --private-key is shell
# metacharacters executing inside a --network host container whose output is
# then baked into a published image.
_require_hex() {
    local name="$1" value="$2" nibbles="$3"
    if ! [[ "$value" =~ ^0x[0-9a-fA-F]{$nibbles}$ ]]; then
        echo "ERROR: $name must be a 0x-prefixed ${nibbles}-nibble hex string (got: '$value')" >&2
        exit 1
    fi
}
[ -n "$ERC20_ADDRESS" ] && _require_hex "--erc20-address" "$ERC20_ADDRESS" 40
_require_hex "--wallet" "$E2E_WALLET" 40
_require_hex "--private-key" "$E2E_PRIVATE_KEY" 64

if [ ${#POSITIONAL[@]} -ne 2 ]; then
    echo "Usage: $0 <DISCOVERY_JSON> <OUTPUT_DIR> [--erc20-address <addr>] [--foundry-image <image>]" >&2
    exit 1
fi

DISCOVERY_JSON="${POSITIONAL[0]}"
OUTPUT_DIR="${POSITIONAL[1]}"

for cmd in docker jq curl; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "ERROR: Required command '$cmd' not found" >&2
        exit 1
    fi
done

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

if [ ! -f "$DISCOVERY_JSON" ]; then
    log "ERROR: Discovery file not found: $DISCOVERY_JSON"
    exit 1
fi

FLAVOR=$(jq -r '.flavor // "default"' "$DISCOVERY_JSON")
if [ "$FLAVOR" != "anvil-aggkit" ]; then
    log "ERROR: fixture seeding is only defined for flavor 'anvil-aggkit' (got '$FLAVOR')"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# ----------------------------------------------------------------------------
# L1 endpoint
# ----------------------------------------------------------------------------

L1_CONTAINER=$(jq -r '.l1_anvil.container_name' "$DISCOVERY_JSON")
L1_PORT=$(jq -r '.l1_anvil.ports["8545"] // empty' "$DISCOVERY_JSON")
L1_CHAIN_ID=$(jq -r '.l1_anvil.chain_id // "unknown"' "$DISCOVERY_JSON")

if [ -z "$L1_PORT" ]; then
    log "ERROR: no published 8545 port for L1 anvil ($L1_CONTAINER)"
    exit 1
fi

L1_RPC="http://127.0.0.1:$L1_PORT"
log "L1 anvil: $L1_CONTAINER -> $L1_RPC (chain id $L1_CHAIN_ID)"

if [ -z "$FOUNDRY_IMAGE" ]; then
    # Read the tag from the running node instead of hardcoding it: the anvil
    # image is pinned in src/package_io/constants.star and has already been
    # bumped once (v1.4.3 -> v1.5.1) for an agglayer-visible RPC gap.
    FOUNDRY_IMAGE=$(jq -r '.l1_anvil.image' "$DISCOVERY_JSON")
fi
log "Foundry image: $FOUNDRY_IMAGE"

rpc_call() {
    curl -s --max-time 30 "$L1_RPC" \
        -X POST -H 'Content-Type: application/json' \
        --data "$1"
}

# 0x-prefixed 32-byte left-padded address, for eth_call calldata.
pad_address() {
    local addr="${1#0x}"
    printf '%064s' "$(echo "$addr" | tr '[:upper:]' '[:lower:]')" | tr ' ' '0'
}

# balanceOf(address) -> decimal, or "" on failure.
erc20_balance_of() {
    local token="$1" holder="$2" result
    result=$(rpc_call "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"to\":\"$token\",\"data\":\"0x70a08231$(pad_address "$holder")\"},\"latest\"],\"id\":1}" \
        | jq -r '.result // empty')
    if [ -z "$result" ] || [ "$result" = "0x" ]; then
        echo ""
        return 0
    fi
    # Strip leading zeros so bash's base-16 arithmetic accepts it; 1000e18
    # exceeds 2^63 so print via python-free hex arithmetic is not possible --
    # keep the hex form and only decide zero/non-zero numerically.
    echo "$result"
}

hex_is_zero() {
    local hex="${1#0x}"
    [ -z "$(echo "$hex" | tr -d '0')" ]
}

erc20_is_usable() {
    local token="$1" code balance
    code=$(rpc_call "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getCode\",\"params\":[\"$token\",\"latest\"],\"id\":1}" \
        | jq -r '.result // "0x"')
    if [ "$code" = "0x" ] || [ -z "$code" ]; then
        return 1
    fi
    balance=$(erc20_balance_of "$token" "$E2E_WALLET")
    if [ -z "$balance" ] || hex_is_zero "$balance"; then
        return 1
    fi
    return 0
}

# ----------------------------------------------------------------------------
# Deploy (or reuse)
# ----------------------------------------------------------------------------

DEPLOY_TX="null"
REUSED=false

if [ -n "$ERC20_ADDRESS" ]; then
    log "Checking supplied ERC20 $ERC20_ADDRESS..."
    if erc20_is_usable "$ERC20_ADDRESS"; then
        log "  ✓ live and funded for $E2E_WALLET -- reusing (no deploy)"
        REUSED=true
    else
        log "ERROR: supplied ERC20 $ERC20_ADDRESS has no bytecode or a zero balance for $E2E_WALLET"
        exit 1
    fi
fi

if [ "$REUSED" = false ]; then
    WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/snapshot-e2e-erc20-XXXXXX")
    trap 'rm -rf "$WORK_DIR"' EXIT

    mkdir -p "$WORK_DIR/src"
    printf '[profile.default]\nsrc = "src"\nout = "out"\n' > "$WORK_DIR/foundry.toml"

    # Byte-for-byte dev-ui's E2E_TOKEN_SOURCE (tests/e2e/globalSetup.ts).
    cat > "$WORK_DIR/src/E2EToken.sol" << 'SOLIDITY'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract E2EToken {
    string public name = "Agglayer E2E Token";
    string public symbol = "E2E";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(uint256 initialSupply) {
        totalSupply = initialSupply;
        balanceOf[msg.sender] = initialSupply;
        emit Transfer(address(0), msg.sender, initialSupply);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}
SOLIDITY

    log "Deploying E2E ERC20 on L1 via containerized forge..."

    # The foundry image's entrypoint is `/bin/sh -c`, so the whole command must
    # be one string. Run as the host uid/gid: mktemp -d is mode 0700, so the
    # image's default uid could not even enter /workspace, and forge's output
    # would come back root-owned. HOME=/workspace gives forge a writable home
    # for its solc (svm) install.
    #
    # No --skip-simulation: foundry >= 1.7 dropped the flag and its variadic
    # --constructor-args then swallows the stray token.
    # $L1_PORT comes from discovery.json and is interpolated into a shell
    # string executed by the container's /bin/sh -c entrypoint; the key/supply
    # are validated at parse time above.
    if ! [[ "$L1_PORT" =~ ^[0-9]{1,5}$ ]]; then
        echo "ERROR: L1 host port from discovery.json is not numeric: '$L1_PORT'" >&2
        exit 1
    fi
    FORGE_CMD="cd /workspace && forge create src/E2EToken.sol:E2EToken \
--rpc-url http://127.0.0.1:$L1_PORT \
--private-key $E2E_PRIVATE_KEY \
--broadcast \
--constructor-args $INITIAL_SUPPLY"

    set +e
    FORGE_OUTPUT=$(docker run --rm --network host \
        --user "$(id -u):$(id -g)" \
        -e HOME=/workspace \
        -v "$WORK_DIR:/workspace" \
        "$FOUNDRY_IMAGE" "$FORGE_CMD" 2>&1)
    FORGE_STATUS=$?
    set -e

    # shellcheck disable=SC2001 # prefixing every line of multi-line output; ${var//pattern/repl} can't do this
    echo "$FORGE_OUTPUT" | sed 's/^/    /'

    if [ $FORGE_STATUS -ne 0 ]; then
        log "ERROR: forge create failed (exit $FORGE_STATUS)"
        exit 1
    fi

    ERC20_ADDRESS=$(echo "$FORGE_OUTPUT" | grep -oE 'Deployed to: 0x[a-fA-F0-9]{40}' | head -1 | awk '{print $3}')
    DEPLOY_TX_RAW=$(echo "$FORGE_OUTPUT" | grep -oE 'Transaction hash: 0x[a-fA-F0-9]{64}' | head -1 | awk '{print $3}')

    if [ -z "$ERC20_ADDRESS" ]; then
        log "ERROR: could not parse a deployed address out of forge's output"
        exit 1
    fi

    [ -n "$DEPLOY_TX_RAW" ] && DEPLOY_TX="\"$DEPLOY_TX_RAW\""

    log "  ✓ deployed at $ERC20_ADDRESS"
fi

# ----------------------------------------------------------------------------
# Verify
# ----------------------------------------------------------------------------

log "Verifying fixture..."

CODE=$(rpc_call "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getCode\",\"params\":[\"$ERC20_ADDRESS\",\"latest\"],\"id\":1}" | jq -r '.result // "0x"')
if [ "$CODE" = "0x" ]; then
    log "ERROR: no bytecode at $ERC20_ADDRESS after deployment"
    exit 1
fi
log "  ✓ bytecode present (${#CODE} hex chars)"

BALANCE_HEX=$(erc20_balance_of "$ERC20_ADDRESS" "$E2E_WALLET")
if [ -z "$BALANCE_HEX" ] || hex_is_zero "$BALANCE_HEX"; then
    log "ERROR: $E2E_WALLET holds zero $ERC20_ADDRESS"
    exit 1
fi
log "  ✓ balanceOf($E2E_WALLET) = $BALANCE_HEX (non-zero)"

NATIVE_HEX=$(rpc_call "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$E2E_WALLET\",\"latest\"],\"id\":1}" | jq -r '.result // "0x0"')
log "  L1 native balance of $E2E_WALLET: $NATIVE_HEX"

# ----------------------------------------------------------------------------
# Record
# ----------------------------------------------------------------------------

FIXTURES_FILE="$OUTPUT_DIR/fixtures.json"

jq -n \
    --arg erc20_address "$ERC20_ADDRESS" \
    --arg erc20_name "Agglayer E2E Token" \
    --arg erc20_symbol "E2E" \
    --argjson erc20_decimals 18 \
    --arg erc20_initial_supply "$INITIAL_SUPPLY" \
    --arg erc20_balance_hex "$BALANCE_HEX" \
    --arg e2e_wallet "$E2E_WALLET" \
    --arg e2e_private_key "$E2E_PRIVATE_KEY" \
    --arg e2e_wallet_native_balance_hex "$NATIVE_HEX" \
    --argjson l1_chain_id "$(jq '.l1_anvil.chain_id // null' "$DISCOVERY_JSON")" \
    --argjson deploy_tx "$DEPLOY_TX" \
    --argjson reused "$REUSED" \
    --arg foundry_image "$FOUNDRY_IMAGE" \
    --arg seeded_at "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    '{seeded_at: $seeded_at,
      l1_chain_id: $l1_chain_id,
      e2e_wallet: $e2e_wallet,
      e2e_private_key: $e2e_private_key,
      e2e_wallet_l1_native_balance_hex: $e2e_wallet_native_balance_hex,
      erc20: {
        address: $erc20_address,
        name: $erc20_name,
        symbol: $erc20_symbol,
        decimals: $erc20_decimals,
        initial_supply: $erc20_initial_supply,
        holder_balance_hex: $erc20_balance_hex,
        deploy_tx: $deploy_tx,
        reused: $reused,
        foundry_image: $foundry_image
      }}' > "$FIXTURES_FILE"

log "Fixtures recorded: $FIXTURES_FILE"
log "  E2E_ERC20_ADDRESS=$ERC20_ADDRESS"

exit 0
