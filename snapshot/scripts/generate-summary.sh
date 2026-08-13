#!/usr/bin/env bash
#
# Generate Summary JSON Script
# Creates summary.json with contract addresses, service URLs, and accounts
#
# Usage: generate-summary.sh [--flavor default|anvil-aggkit] <DISCOVERY_JSON> <OUTPUT_DIR>
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Host-port numbering lives in exactly one place.
# shellcheck disable=SC1090,SC1091 # SCRIPT_DIR is resolved at runtime relative to this file (SC1090 on older shellcheck, SC1091 on newer)
source "$SCRIPT_DIR/lib/ports.sh"

FLAVOR="default"
while [ $# -gt 0 ]; do
    case "$1" in
        --flavor)
            FLAVOR="${2:-}"
            shift 2
            ;;
        -*)
            # Do not let an unknown option fall through to `break` and get
            # consumed as a positional -- that silently ran the default flavor.
            echo "ERROR: unknown option: $1" >&2
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

# An unrecognised flavor must fail rather than silently select the default
# (geth/lighthouse) code path against an anvil enclave's discovery.
case "$FLAVOR" in
    default | anvil-aggkit) ;;
    *)
        echo "ERROR: unknown flavor: '$FLAVOR' (expected 'default' or 'anvil-aggkit')" >&2
        exit 1
        ;;
esac

# Check arguments
if [ $# -ne 2 ]; then
    echo "Usage: $0 [--flavor default|anvil-aggkit] <DISCOVERY_JSON> <OUTPUT_DIR>" >&2
    exit 1
fi

DISCOVERY_JSON="$1"
OUTPUT_DIR="$2"

# Create temp directory for intermediate files to avoid "Argument list too long" errors
TEMP_DIR="${OUTPUT_DIR}/.tmp_summary_$$"
mkdir -p "$TEMP_DIR"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Check dependencies
for cmd in jq curl; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "ERROR: Required command '$cmd' not found" >&2
        exit 1
    fi
done

# Log function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log "Starting summary.json generation"

# Read discovery info
if [ ! -f "$DISCOVERY_JSON" ]; then
    log "ERROR: Discovery file not found: $DISCOVERY_JSON"
    exit 1
fi

ENCLAVE_NAME=$(jq -r '.enclave_name' "$DISCOVERY_JSON")
SNAPSHOT_ID=$(basename "$OUTPUT_DIR")

# ============================================================================
# Flavor: anvil-aggkit
#
# This summary is a CONTRACT with dev-ui CI (S13): the workflow reads the
# haproxy origin, the chain ids, the per-L2 network_id, the aggkit-proxy REST
# base and -- critically -- erc20_address, which is nonce-dependent and never
# matches dev-ui's hardcoded DEVNET_KNOWN_ERC20_CANDIDATE.
#
# The default flavor continues below this block, untouched.
# ============================================================================

if [ "$FLAVOR" = "anvil-aggkit" ]; then
    STATE_METADATA="$OUTPUT_DIR/state/state-metadata.json"
    if [ ! -f "$STATE_METADATA" ]; then
        log "ERROR: state metadata not found: $STATE_METADATA"
        exit 1
    fi
    FIXTURES_JSON="$OUTPUT_DIR/fixtures.json"
    IMAGE_INFO="$OUTPUT_DIR/images/IMAGE_INFO.json"

    L1_SVC=$(jq -r '.l1_anvil.service_name' "$DISCOVERY_JSON")
    AGGLAYER_SVC=$(jq -r '.agglayer.service_name' "$DISCOVERY_JSON")
    PROXY_SVC=$(jq -r '.aggkit_proxy.service_name' "$DISCOVERY_JSON")
    HAPROXY_SVC=$(jq -r '.haproxy.service_name' "$DISCOVERY_JSON")
    DEVUI_SVC=$(jq -r '.dev_ui.service_name' "$DISCOVERY_JSON")

    PROXY_PORT=$(snapshot_fixed_port devnet_proxy)
    PROXY_BASE="http://127.0.0.1:${PROXY_PORT}"
    AGGKIT_PROXY_PORT=$(snapshot_fixed_port aggkit_proxy)
    L1_PORT=$(snapshot_fixed_port l1_rpc)
    DEVUI_PORT=$(snapshot_fixed_port dev_ui)

    # ---- toml_value <file> <key> [section] ------------------------------
    # Reads an already-extracted config.toml rather than re-querying a live
    # container. With a section, the search is limited to that section.
    toml_value() {
        local file="$1" key="$2" section="${3:-}"
        [ -f "$file" ] || { echo ""; return; }
        if [ -n "$section" ]; then
            awk -v sect="[$section]" -v key="$key" '
                $0 == sect { in_s = 1; next }
                /^\[/ { in_s = 0 }
                in_s && $0 ~ "^" key "[[:space:]]*=" { print; exit }
            ' "$file" | sed 's/.*= *"\([^"]*\)".*/\1/'
        else
            awk -v key="$key" '
                /^\[/ { past = 1 }
                !past && $0 ~ "^" key "[[:space:]]*=" { print; exit }
            ' "$file" | sed 's/.*= *"\([^"]*\)".*/\1/'
        fi
    }

    FIRST_PREFIX=$(jq -r '.l2_chains | keys | first' "$DISCOVERY_JSON")
    FIRST_AGGKIT_SVC=$(jq -r --arg p "$FIRST_PREFIX" '.l2_chains[$p].aggkit.service_name' "$DISCOVERY_JSON")
    REF_AGGKIT_CONFIG="$OUTPUT_DIR/config/$FIRST_AGGKIT_SVC/config.toml"

    L1_CONTRACTS=$(jq -n \
        --arg bridge "$(toml_value "$REF_AGGKIT_CONFIG" BridgeAddr L1Config)" \
        --arg ger "$(toml_value "$REF_AGGKIT_CONFIG" polygonZkEVMGlobalExitRootAddress L1Config)" \
        --arg rm "$(toml_value "$REF_AGGKIT_CONFIG" polygonRollupManagerAddress L1Config)" \
        --arg pol "$(toml_value "$REF_AGGKIT_CONFIG" polTokenAddress L1Config)" \
        '{bridge: $bridge, global_exit_root_v2: $ger, rollup_manager: $rm, pol_token: $pol}
         | with_entries(select(.value != ""))')

    # ---- haproxy route table -------------------------------------------
    # Built from the discovered topology, not from parsing haproxy.cfg, so the
    # network_id/chain_id on each route comes from the authoritative source
    # (state-metadata.json, which greps each aggkit config).
    ROUTES=$(jq -n \
        --arg base "$PROXY_BASE" \
        --arg l1_svc "$L1_SVC" \
        --arg proxy_svc "$PROXY_SVC" \
        --arg devui_svc "$DEVUI_SVC" \
        --slurpfile meta "$STATE_METADATA" \
        '
        ($meta[0].chains | map(select(.role == "l1")) | first) as $l1 |
        ($meta[0].chains | map(select(.role == "l2"))) as $l2s |
        [
            {
                path: "/l1rpc",
                url: ($base + "/l1rpc"),
                kind: "json-rpc",
                upstream: ($l1_svc + ":8545"),
                chain_id: $l1.chain_id,
                network_id: $l1.network_id
            }
        ]
        + ($l2s | map({
                path: ("/l2rpc-" + .prefix),
                url: ($base + "/l2rpc-" + .prefix),
                kind: "json-rpc",
                upstream: (.service + ":8545"),
                chain_id: .chain_id,
                network_id: .network_id
          }))
        + [
            {
                path: "/l2rpc",
                url: ($base + "/l2rpc"),
                kind: "json-rpc",
                upstream: (($l2s | first).service + ":8545"),
                chain_id: ($l2s | first).chain_id,
                network_id: ($l2s | first).network_id,
                note: "back-compat alias for the first L2"
            },
            {
                path: "/aggkitapi",
                url: ($base + "/aggkitapi"),
                kind: "rest",
                upstream: ($proxy_svc + ":8080"),
                note: "aggkit-proxy bridge + tracker REST API (path prefix stripped upstream)"
            },
            {
                path: "/",
                url: ($base + "/"),
                kind: "http",
                upstream: ($devui_svc + ":80"),
                note: "default backend: the dev-ui"
            }
        ]')

    # ---- per-network detail ---------------------------------------------
    L1_META=$(jq -c '.chains[] | select(.role == "l1")' "$STATE_METADATA")
    L1_NET=$(jq -n \
        --argjson meta "$L1_META" \
        --slurpfile contracts <(echo "$L1_CONTRACTS") \
        --arg svc "$L1_SVC" \
        --arg base "$PROXY_BASE" \
        --arg port "$L1_PORT" \
        --arg env "$(snapshot_fixed_port_env l1_rpc)" \
        '{
            service: $svc,
            chain_id: $meta.chain_id,
            network_id: $meta.network_id,
            block_number_at_capture: $meta.block_number,
            rpc: {
                internal: ("http://" + $svc + ":8545"),
                external: ("http://127.0.0.1:" + $port),
                via_proxy: ($base + "/l1rpc"),
                host_port_env: $env
            },
            contracts: $contracts[0]
        }')

    L2_NETS="{}"
    for prefix in $(jq -r '.l2_chains | keys[]' "$DISCOVERY_JSON"); do
        L2_SVC=$(jq -r --arg p "$prefix" '.l2_chains[$p].anvil.service_name' "$DISCOVERY_JSON")
        AGGKIT_SVC=$(jq -r --arg p "$prefix" '.l2_chains[$p].aggkit.service_name' "$DISCOVERY_JSON")
        AGGKIT_CONFIG="$OUTPUT_DIR/config/$AGGKIT_SVC/config.toml"
        L2_META=$(jq -c --arg p "$prefix" '.chains[] | select(.prefix == $p)' "$STATE_METADATA")

        L2_CONTRACTS=$(jq -n \
            --arg bridge "$(toml_value "$AGGKIT_CONFIG" BridgeAddr L2Config)" \
            --arg ger "$(toml_value "$AGGKIT_CONFIG" GlobalExitRootAddr L2Config)" \
            --arg rollup "$(toml_value "$AGGKIT_CONFIG" polygonZkEVMAddress L1Config)" \
            '{sovereign_bridge: $bridge, global_exit_root: $ger, sovereign_rollup_l1: $rollup}
             | with_entries(select(.value != ""))')

        L2_NET=$(jq -n \
            --argjson meta "$L2_META" \
            --slurpfile contracts <(echo "$L2_CONTRACTS") \
            --arg prefix "$prefix" \
            --arg svc "$L2_SVC" \
            --arg aggkit "$AGGKIT_SVC" \
            --arg base "$PROXY_BASE" \
            --arg rpc_port "$(snapshot_l2_port "$prefix" http)" \
            --arg rpc_env "$(snapshot_l2_port_env "$prefix" http)" \
            --arg rest_port "$(snapshot_l2_port "$prefix" aggkit_rest)" \
            --arg rest_env "$(snapshot_l2_port_env "$prefix" aggkit_rest)" \
            --arg aggkit_rpc_port "$(snapshot_l2_port "$prefix" aggkit_rpc)" \
            '{
                prefix: $prefix,
                service: $svc,
                chain_id: $meta.chain_id,
                network_id: $meta.network_id,
                block_number_at_capture: $meta.block_number,
                rpc: {
                    internal: ("http://" + $svc + ":8545"),
                    external: ("http://127.0.0.1:" + $rpc_port),
                    via_proxy: ($base + "/l2rpc-" + $prefix),
                    host_port_env: $rpc_env
                },
                aggkit: {
                    service: $aggkit,
                    components: "aggsender,aggoracle,autoclaim,bridge",
                    rpc: {
                        internal: ("http://" + $aggkit + ":5576"),
                        external: ("http://127.0.0.1:" + $aggkit_rpc_port)
                    },
                    rest_api: {
                        internal: ("http://" + $aggkit + ":5577"),
                        external: ("http://127.0.0.1:" + $rest_port),
                        host_port_env: $rest_env
                    }
                },
                contracts: $contracts[0]
            }')

        L2_NETS=$(jq --arg p "$prefix" --argjson n "$L2_NET" '. + {($p): $n}' <<< "$L2_NETS")
    done

    # ---- accounts --------------------------------------------------------
    # Balances come out of the captured anvil state (authoritative) rather than
    # from a live RPC call, so the summary stays true for the bundle even if
    # the source enclave has moved on or been torn down.
    L1_MNEMONIC=$(jq -r '.chains[] | select(.role=="l1") | .cmd[0]' "$STATE_METADATA" \
        | sed -n 's/.*--mnemonic "\([^"]*\)".*/\1/p')
    L2_MNEMONIC=$(jq -r '.chains[] | select(.role=="l2") | .cmd[0]' "$STATE_METADATA" | head -1 \
        | sed -n 's/.*--mnemonic "\([^"]*\)".*/\1/p')

    FUNDED="[]"
    if command -v cast &> /dev/null; then
        # 10 accounts per mnemonic is what anvil's own startup banner prints and
        # is plenty for the dev-ui suite; the mnemonics are exported too so a
        # consumer can derive more.
        for spec in "l1:$L1_MNEMONIC" "l2:$L2_MNEMONIC"; do
            role="${spec%%:*}"
            mnem="${spec#*:}"
            [ -n "$mnem" ] || continue
            for i in $(seq 0 9); do
                addr=$(cast wallet address --mnemonic "$mnem" --mnemonic-index "$i" 2>/dev/null || echo "")
                pk=$(cast wallet private-key --mnemonic "$mnem" --mnemonic-index "$i" 2>/dev/null || echo "")
                [ -n "$addr" ] || continue
                bal=$(jq -r --arg a "${addr,,}" \
                    '.accounts // {} | to_entries | map(select(.key | ascii_downcase == $a)) | first | .value.balance // ""' \
                    "$OUTPUT_DIR/state/$([ "$role" = l1 ] && echo "$L1_SVC" || jq -r --arg p "$FIRST_PREFIX" '.l2_chains[$p].anvil.service_name' "$DISCOVERY_JSON").json" 2>/dev/null || echo "")
                FUNDED=$(jq --arg addr "$addr" --arg pk "$pk" --arg role "$role" --arg idx "$i" --arg bal "$bal" \
                    '. + [{address: $addr, private_key: $pk, mnemonic_index: ($idx|tonumber),
                           funded_on: (if $role == "l1" then ["l1"] else ["l2-001","l2-002"] end),
                           balance_at_capture: (if $bal == "" then null else $bal end)}]' <<< "$FUNDED")
            done
        done
    else
        log "  WARNING: cast not found -- funded-account list will be limited to the E2E wallet"
    fi

    # Operational signers. The kurtosis keystores carry no plaintext "address"
    # field, so instead of guessing, the addresses come from the one place they
    # are recorded in the clear: agglayer's [proof-signers] table (the per-network
    # aggsender/certificate signer). The keystore locations *inside the images*
    # are listed alongside so a consumer can decrypt them if it needs the keys.
    AGGLAYER_CONFIG="$OUTPUT_DIR/config/agglayer/config.toml"
    OPERATIONAL="[]"
    if [ -f "$AGGLAYER_CONFIG" ]; then
        while read -r nid addr; do
            [ -n "$addr" ] || continue
            OPERATIONAL=$(jq --argjson n "$nid" --arg a "$addr" \
                '. + [{network_id: $n, address: $a, role: "certificate/proof signer (aggsender)",
                       private_key: "(encrypted in keystore -- see keystores[])"}]' <<< "$OPERATIONAL")
        done < <(awk '/^\[proof-signers\]/{f=1;next} /^\[/{f=0} f && /=/{gsub(/"/,"");print $1, $3}' "$AGGLAYER_CONFIG")
    fi

    KEYSTORES="[]"
    add_keystore() {
        local file="$1" svc="$2" path="$3" role="$4"
        [ -f "$file" ] || return 0
        KEYSTORES=$(jq --arg s "$svc" --arg p "$path" --arg r "$role" \
            '. + [{service: $s, path_in_image: $p, role: $r}]' <<< "$KEYSTORES")
    }
    add_keystore "$OUTPUT_DIR/config/agglayer/aggregator.keystore" "$AGGLAYER_SVC" \
        "/etc/agglayer/aggregator.keystore" "agglayer settlement signer"
    for prefix in $(jq -r '.l2_chains | keys[]' "$DISCOVERY_JSON"); do
        SVC=$(jq -r --arg p "$prefix" '.l2_chains[$p].aggkit.service_name' "$DISCOVERY_JSON")
        add_keystore "$OUTPUT_DIR/config/$SVC/sequencer.keystore" "$SVC" \
            "/etc/aggkit/sequencer.keystore" "sequencer / aggsender signer"
        add_keystore "$OUTPUT_DIR/config/$SVC/aggoracle.keystore" "$SVC" \
            "/etc/aggkit/aggoracle.keystore" "aggoracle + autoclaim signer"
        add_keystore "$OUTPUT_DIR/config/$SVC/sovereignadmin.keystore" "$SVC" \
            "/etc/aggkit/sovereignadmin.keystore" "sovereign admin"
    done

    FIXTURES='null'
    ERC20_ADDRESS=""
    E2E_WALLET=""
    E2E_KEY=""
    if [ -f "$FIXTURES_JSON" ]; then
        FIXTURES=$(cat "$FIXTURES_JSON")
        ERC20_ADDRESS=$(jq -r '.erc20.address // ""' "$FIXTURES_JSON")
        E2E_WALLET=$(jq -r '.e2e_wallet // ""' "$FIXTURES_JSON")
        E2E_KEY=$(jq -r '.e2e_private_key // ""' "$FIXTURES_JSON")
    else
        log "  WARNING: fixtures.json not found -- erc20_address will be null"
    fi

    # Flatten IMAGE_INFO's nested {images: {...}} into {services: {...}} so
    # consumers read summary.images.services, not summary.images.images.
    IMAGES='null'
    if [ -f "$IMAGE_INFO" ]; then
        IMAGES=$(jq '{tag, image_prefix, busybox_image, self_contained, built_at: .timestamp, services: .images}' "$IMAGE_INFO")
    fi

    # ---- compose host-port table ----------------------------------------
    PORT_TABLE=$(jq -n '{}')
    add_port() {
        PORT_TABLE=$(jq --arg svc "$1" --arg env "$2" --argjson host "$3" --argjson cont "$4" --arg desc "$5" \
            '.[$svc] = ((.[$svc] // []) + [{env: $env, host_default: $host, container: $cont, description: $desc}])' \
            <<< "$PORT_TABLE")
    }
    add_port "$L1_SVC" "$(snapshot_fixed_port_env l1_rpc)" "$L1_PORT" 8545 "L1 JSON-RPC (debug)"
    for prefix in $(jq -r '.l2_chains | keys[]' "$DISCOVERY_JSON"); do
        L2_SVC=$(jq -r --arg p "$prefix" '.l2_chains[$p].anvil.service_name' "$DISCOVERY_JSON")
        AGGKIT_SVC=$(jq -r --arg p "$prefix" '.l2_chains[$p].aggkit.service_name' "$DISCOVERY_JSON")
        add_port "$L2_SVC" "$(snapshot_l2_port_env "$prefix" http)" "$(snapshot_l2_port "$prefix" http)" 8545 "L2 JSON-RPC (debug)"
        add_port "$AGGKIT_SVC" "$(snapshot_l2_port_env "$prefix" aggkit_rpc)" "$(snapshot_l2_port "$prefix" aggkit_rpc)" 5576 "aggkit JSON-RPC (debug)"
        add_port "$AGGKIT_SVC" "$(snapshot_l2_port_env "$prefix" aggkit_rest)" "$(snapshot_l2_port "$prefix" aggkit_rest)" 5577 "aggkit bridge REST API"
    done
    add_port "$AGGLAYER_SVC" "$(snapshot_fixed_port_env agglayer_grpc)" "$(snapshot_fixed_port agglayer_grpc)" 4443 "agglayer gRPC"
    add_port "$AGGLAYER_SVC" "$(snapshot_fixed_port_env agglayer_readrpc)" "$(snapshot_fixed_port agglayer_readrpc)" 4444 "agglayer read RPC"
    add_port "$AGGLAYER_SVC" "$(snapshot_fixed_port_env agglayer_admin)" "$(snapshot_fixed_port agglayer_admin)" 4446 "agglayer admin API"
    add_port "$AGGLAYER_SVC" "$(snapshot_fixed_port_env agglayer_metrics)" "$(snapshot_fixed_port agglayer_metrics)" 9092 "agglayer prometheus"
    add_port "$PROXY_SVC" "$(snapshot_fixed_port_env aggkit_proxy)" "$AGGKIT_PROXY_PORT" 8080 "aggkit-proxy bridge + tracker REST"
    add_port "$DEVUI_SVC" "$(snapshot_fixed_port_env dev_ui)" "$DEVUI_PORT" 80 "dev-ui (manual use)"
    add_port "$HAPROXY_SVC" "$(snapshot_fixed_port_env devnet_proxy)" "$PROXY_PORT" 80 "CORS origin used by dev-ui CI"

    CHAIN_IDS=$(jq '[.chains[] | {key: (if .role == "l1" then "l1" else "l2_" + .prefix end), value: .chain_id}] | from_entries' "$STATE_METADATA")
    NETWORK_IDS=$(jq '[.chains[] | {key: (if .role == "l1" then "l1" else "l2_" + .prefix end), value: .network_id}] | from_entries' "$STATE_METADATA")

    SUMMARY_FILE="$OUTPUT_DIR/summary.json"
    jq -n \
        --arg snapshot_name "$SNAPSHOT_ID" \
        --arg enclave "$ENCLAVE_NAME" \
        --arg flavor "$FLAVOR" \
        --arg created_at "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
        --arg erc20 "$ERC20_ADDRESS" \
        --arg e2e_wallet "$E2E_WALLET" \
        --arg e2e_key "$E2E_KEY" \
        --arg l1_mnemonic "$L1_MNEMONIC" \
        --arg l2_mnemonic "$L2_MNEMONIC" \
        --arg proxy_svc "$PROXY_SVC" \
        --arg haproxy_svc "$HAPROXY_SVC" \
        --arg devui_svc "$DEVUI_SVC" \
        --arg devui_image "$(jq -r '.dev_ui.image' "$DISCOVERY_JSON")" \
        --arg agglayer_svc "$AGGLAYER_SVC" \
        --arg proxy_base "$PROXY_BASE" \
        --argjson proxy_port "$PROXY_PORT" \
        --arg proxy_port_env "$(snapshot_fixed_port_env devnet_proxy)" \
        --argjson aggkit_proxy_port "$AGGKIT_PROXY_PORT" \
        --argjson devui_port "$DEVUI_PORT" \
        --slurpfile state_meta "$STATE_METADATA" \
        --argjson routes "$ROUTES" \
        --argjson l1 "$L1_NET" \
        --argjson l2 "$L2_NETS" \
        --argjson chain_ids "$CHAIN_IDS" \
        --argjson network_ids "$NETWORK_IDS" \
        --argjson funded "$FUNDED" \
        --argjson operational "$OPERATIONAL" \
        --argjson keystores "$KEYSTORES" \
        --argjson fixtures "$FIXTURES" \
        --argjson images "$IMAGES" \
        --argjson ports "$PORT_TABLE" \
        '{
            snapshot_name: $snapshot_name,
            enclave: $enclave,
            flavor: $flavor,
            created_at: $created_at,
            captured_at: $state_meta[0].captured_at,
            settlement_free: $state_meta[0].settlement_free,
            agglayer_certificates_at_capture: $state_meta[0].agglayer_certificates,

            erc20_address: (if $erc20 == "" then null else $erc20 end),
            chain_ids: $chain_ids,
            network_ids: $network_ids,

            proxy: {
                service: $haproxy_svc,
                host_port: $proxy_port,
                host_port_env: $proxy_port_env,
                base_url: $proxy_base,
                cors: "Access-Control-Allow-Origin: * , OPTIONS answered 204 by haproxy itself",
                routes: $routes
            },
            aggkit_proxy: {
                service: $proxy_svc,
                components: "proxy,tracker",
                rest_url: ("http://127.0.0.1:" + ($aggkit_proxy_port|tostring)),
                internal_rest_url: ($proxy_svc + ":8080" | "http://" + .),
                rest_url_via_proxy: ($proxy_base + "/aggkitapi"),
                bridge_api: ($proxy_base + "/aggkitapi/bridge/v1"),
                tracker_api: ($proxy_base + "/aggkitapi/tracker/v1"),
                sync_status_url: ($proxy_base + "/aggkitapi/bridge/v1/sync-status?network_id=")
            },
            agglayer: {
                service: $agglayer_svc,
                grpc: ("http://" + $agglayer_svc + ":4443"),
                read_rpc: ("http://" + $agglayer_svc + ":4444"),
                admin: ("http://" + $agglayer_svc + ":4446"),
                metrics: ("http://" + $agglayer_svc + ":9092/metrics")
            },
            dev_ui: {
                service: $devui_svc,
                image: $devui_image,
                url: ("http://127.0.0.1:" + ($devui_port|tostring)),
                url_via_proxy: ($proxy_base + "/"),
                config_path: "/etc/agglayer-dev-ui/config.json"
            },

            networks: { l1: $l1, l2: $l2 },

            accounts: {
                e2e_wallet: (if $e2e_wallet == "" then null else {
                    address: $e2e_wallet,
                    private_key: $e2e_key,
                    description: "dev-ui e2e signer; funded natively on all chains and holder of erc20_address"
                } end),
                funded: $funded,
                operational: $operational,
                keystores: $keystores,
                mnemonics: { l1: $l1_mnemonic, l2: $l2_mnemonic }
            },

            fixtures: $fixtures,
            images: $images,
            compose: {
                file: "docker-compose.yml",
                self_contained: true,
                bind_mounts: 0,
                volumes: 0,
                image_prefix_env: "SNAPSHOT_IMAGE_PREFIX",
                image_tag_env: "SNAPSHOT_IMAGE_TAG",
                host_ports: $ports
            },

            notes: {
                erc20: "erc20_address is nonce-dependent and does NOT match dev-ui DEVNET_KNOWN_ERC20_CANDIDATE. Pass it as E2E_ERC20_ADDRESS so globalSetup skips its own deploy.",
                self_contained: "State, config and keystores are baked into the images. The compose file is the only file needed.",
                settlement_free: "A bundle with settlement_free == false must not be published: agglayer/aggkit internal databases are not captured, so restoring chain state that already contains bridge activity is unsound.",
                restore_adaptation: "aggkit rollupCreationBlockNumber / RollupCreationBlockL1 are repointed at the L1 snapshot block when the images are built: a restored anvil serves state only at the snapshot block and later. See snapshot/scripts/build-images.sh.",
                keys: "All keys here are public kurtosis devnet keys. Nothing sensitive is published."
            }
        }' > "$SUMMARY_FILE"

    if ! jq -e . "$SUMMARY_FILE" > /dev/null; then
        log "ERROR: generated summary.json is not valid JSON"
        exit 1
    fi

    log "✓ Summary generated: $SUMMARY_FILE"
    log "  flavor:          $(jq -r '.flavor' "$SUMMARY_FILE")"
    log "  chain ids:       $(jq -rc '.chain_ids' "$SUMMARY_FILE")"
    log "  network ids:     $(jq -rc '.network_ids' "$SUMMARY_FILE")"
    log "  erc20_address:   $(jq -r '.erc20_address' "$SUMMARY_FILE")"
    log "  proxy routes:    $(jq -r '.proxy.routes | length' "$SUMMARY_FILE")"
    log "  funded accounts: $(jq -r '.accounts.funded | length' "$SUMMARY_FILE")"
    exit 0
fi

# Get checkpoint info
CHECKPOINT_FILE="$OUTPUT_DIR/metadata/checkpoint.json"
if [ -f "$CHECKPOINT_FILE" ]; then
    L1_BLOCK=$(jq -r '.l1_state.block_number' "$CHECKPOINT_FILE")
    L1_HASH=$(jq -r '.l1_state.block_hash' "$CHECKPOINT_FILE")
    GENESIS_HASH=$(jq -r '.l1_state.genesis_hash' "$CHECKPOINT_FILE")
else
    L1_BLOCK="unknown"
    L1_HASH="unknown"
    GENESIS_HASH="unknown"
fi

# Get L1 chain ID from genesis
L1_CHAIN_ID="271828"  # default
GENESIS_FILE="$OUTPUT_DIR/artifacts/genesis.json"
if [ -f "$GENESIS_FILE" ]; then
    L1_CHAIN_ID=$(jq -r '.config.chainId // "271828"' "$GENESIS_FILE")
fi

# Check if agglayer exists
AGGLAYER_FOUND=$(jq -r '.agglayer.found // false' "$DISCOVERY_JSON")

# Check if L2 chains exist
L2_CHAINS_COUNT=$(jq -r '.l2_chains | length // 0' "$DISCOVERY_JSON" 2>/dev/null || echo "0")

# ============================================================================
# Helper Functions
# ============================================================================

# Default mnemonics used for test accounts
DEFAULT_L1_MNEMONIC="giant issue aisle success illegal bike spike question tent bar rely arctic volcano long crawl hungry vocal artwork sniff fantasy very lucky have athlete"
DEFAULT_L2_MNEMONIC="test test test test test test test test test test test junk"

# Build a map of address -> private key from mnemonic
build_private_key_map() {
    local mnemonic="$1"
    local count="${2:-100}"  # Generate first 100 accounts

    echo "{}" > "$TEMP_DIR/pk_map.json"

    for i in $(seq 0 $((count - 1))); do
        # Derive address and private key
        local addr
        addr=$(cast wallet address --mnemonic "$mnemonic" --mnemonic-index "$i" 2>/dev/null || echo "")
        local pk
        pk=$(cast wallet private-key --mnemonic "$mnemonic" --mnemonic-index "$i" 2>/dev/null || echo "")

        if [ -n "$addr" ] && [ -n "$pk" ]; then
            # Add to map (convert address to lowercase for matching)
            jq --arg addr "${addr,,}" --arg pk "$pk" '. + {($addr): $pk}' "$TEMP_DIR/pk_map.json" > "$TEMP_DIR/pk_map_tmp.json"
            mv "$TEMP_DIR/pk_map_tmp.json" "$TEMP_DIR/pk_map.json"
        fi
    done
}

# Extract accounts from genesis file (only meaningful accounts with balance > 1)
extract_genesis_accounts() {
    local genesis_file="$1"
    local description_prefix="$2"
    local exclude_op_contracts="${3:-false}"
    local pk_map_file="$TEMP_DIR/pk_map.json"

    if [ ! -f "$genesis_file" ]; then
        echo "[]"
        return
    fi

    # Load private key map if available
    local pk_map="{}"
    if [ -f "$pk_map_file" ]; then
        pk_map=$(cat "$pk_map_file")
    fi

    # Extract accounts with meaningful balance, excluding precompiles and optionally OP contracts
    if [ "$exclude_op_contracts" = "true" ]; then
        jq --arg desc "$description_prefix" --argjson pk_map "$pk_map" '
            .alloc // {} | to_entries |
            map(select(
                # Exclude precompile addresses (0x0000...0000 through 0x0000...00ff)
                (.key | test("^0x000000000000000000000000000000000000") | not) and
                # Exclude OP predeploy contracts (0x4200...)
                (.key | test("^0x4200|^0420") | not) and
                # Only include accounts with balance > 1
                ((.value.balance | if type == "string" then
                    if startswith("0x") then
                        # Hex balance: exclude 0x0 and 0x1
                        . != "0x0" and . != "0x1"
                    else
                        # Decimal balance: exclude 0 and 1
                        (. | tonumber) > 1
                    end
                else false end))
            )) |
            map({
                address: (if .key | startswith("0x") then .key else ("0x" + .key) end),
                balance: .value.balance,
                private_key: (
                    .value.privateKey //
                    $pk_map[(if .key | startswith("0x") then .key else ("0x" + .key) end) | ascii_downcase] //
                    null
                ),
                description: ($desc + " pre-funded account")
            })
        ' "$genesis_file" 2>/dev/null || echo "[]"
    else
        jq --arg desc "$description_prefix" --argjson pk_map "$pk_map" '
            .alloc // {} | to_entries |
            map(select(
                # Exclude precompile addresses (0x0000...0000 through 0x0000...00ff)
                (.key | test("^0x000000000000000000000000000000000000") | not) and
                # Only include accounts with balance > 1
                ((.value.balance | if type == "string" then
                    if startswith("0x") then
                        # Hex balance: exclude 0x0 and 0x1
                        . != "0x0" and . != "0x1"
                    else
                        # Decimal balance: exclude 0 and 1
                        (. | tonumber) > 1
                    end
                else false end))
            )) |
            map({
                address: (if .key | startswith("0x") then .key else ("0x" + .key) end),
                balance: .value.balance,
                private_key: (
                    .value.privateKey //
                    $pk_map[(if .key | startswith("0x") then .key else ("0x" + .key) end) | ascii_downcase] //
                    null
                ),
                description: ($desc + " pre-funded account")
            })
        ' "$genesis_file" 2>/dev/null || echo "[]"
    fi
}

# Extract address from keystore file
extract_keystore_address() {
    local keystore_file="$1"

    if [ ! -f "$keystore_file" ]; then
        echo ""
        return
    fi

    # Keystore files contain the address in the "address" field
    jq -r '.address // empty' "$keystore_file" 2>/dev/null || echo ""
}

# Extract private key from keystore file (if possible - usually encrypted)
# shellcheck disable=SC2317
extract_keystore_privkey() {
    local keystore_file="$1"

    # Note: Keystores are encrypted, so we can't extract the private key directly
    # Return empty string to indicate it's encrypted
    echo ""
}

# Extract L1 contract addresses from agglayer and aggkit configs
extract_l1_contracts() {
    local output_dir="$1"
    local contracts="{}"

    # Extract from agglayer config if it exists
    local agglayer_config="$output_dir/config/agglayer/config.toml"
    if [ -f "$agglayer_config" ]; then
        local rollup_manager
        rollup_manager=$(grep -m1 "rollup-manager-contract" "$agglayer_config" | sed 's/.*= *"\([^"]*\)".*/\1/' 2>/dev/null || echo "")
        local ger_contract
        ger_contract=$(grep -m1 "polygon-zkevm-global-exit-root-v2-contract" "$agglayer_config" | sed 's/.*= *"\([^"]*\)".*/\1/' 2>/dev/null || echo "")

        contracts=$(jq -n \
            --arg rollup_manager "$rollup_manager" \
            --arg ger "$ger_contract" \
            '{
                rollup_manager: (if $rollup_manager != "" then $rollup_manager else null end),
                global_exit_root_v2: (if $ger != "" then $ger else null end)
            }')
    fi

    # Also extract from first L2 aggkit config if available
    local aggkit_config="$output_dir/config/001/aggkit-config.toml"
    if [ -f "$aggkit_config" ]; then
        local bridge_addr
        bridge_addr=$(grep "^BridgeAddr" "$aggkit_config" | head -1 | cut -d'"' -f2 2>/dev/null || echo "")
        local pol_token
        pol_token=$(grep "polTokenAddress" "$aggkit_config" | head -1 | cut -d'"' -f2 2>/dev/null || echo "")
        local deposit_contract
        deposit_contract=$(jq -r '.config.depositContractAddress // empty' "$output_dir/artifacts/genesis.json" 2>/dev/null || echo "")

        contracts=$(echo "$contracts" | jq \
            --arg bridge "$bridge_addr" \
            --arg pol_token "$pol_token" \
            --arg deposit "$deposit_contract" \
            '. + {
                bridge: (if $bridge != "" then $bridge else null end),
                pol_token: (if $pol_token != "" then $pol_token else null end),
                deposit_contract: (if $deposit != "" then $deposit else null end)
            }')
    fi

    echo "$contracts"
}

# ============================================================================
# Build L1 Network Info
# ============================================================================

log "Building L1 network info..."

# Build private key maps from mnemonics (if cast is available)
if command -v cast &> /dev/null; then
    log "  Deriving private keys from L1 mnemonic..."
    build_private_key_map "$DEFAULT_L1_MNEMONIC" 50

    log "  Deriving private keys from L2 mnemonic..."
    # Append L2 private keys to the same map
    for i in $(seq 0 49); do
        addr=$(cast wallet address --mnemonic "$DEFAULT_L2_MNEMONIC" --mnemonic-index "$i" 2>/dev/null || echo "")
        pk=$(cast wallet private-key --mnemonic "$DEFAULT_L2_MNEMONIC" --mnemonic-index "$i" 2>/dev/null || echo "")

        if [ -n "$addr" ] && [ -n "$pk" ]; then
            jq --arg addr "${addr,,}" --arg pk "$pk" '. + {($addr): $pk}' "$TEMP_DIR/pk_map.json" > "$TEMP_DIR/pk_map_tmp.json"
            mv "$TEMP_DIR/pk_map_tmp.json" "$TEMP_DIR/pk_map.json"
        fi
    done
fi

# L1 contract addresses
L1_CONTRACTS=$(extract_l1_contracts "$OUTPUT_DIR")

# L1 service URLs
L1_SERVICES=$(cat <<EOF
{
    "geth": {
        "http_rpc": {
            "internal": "http://geth:8545",
            "external": "http://localhost:8545"
        },
        "ws_rpc": {
            "internal": "ws://geth:8546",
            "external": "ws://localhost:8546"
        },
        "engine_api": {
            "internal": "http://geth:8551",
            "external": "http://localhost:8551"
        },
        "metrics": {
            "internal": "http://geth:9001/debug/metrics/prometheus",
            "external": "http://localhost:9001/debug/metrics/prometheus"
        }
    },
    "beacon": {
        "http_api": {
            "internal": "http://beacon:4000",
            "external": "http://localhost:4000"
        },
        "metrics": {
            "internal": "http://beacon:5054/metrics",
            "external": "http://localhost:5054/metrics"
        }
    },
    "validator": {
        "metrics": {
            "internal": "http://validator:5064/metrics",
            "external": "http://localhost:5064/metrics"
        }
    }
}
EOF
)

# L1 accounts
L1_ACCOUNTS=$(extract_genesis_accounts "$GENESIS_FILE" "L1")

# Build L1 network object
# Use temp files to avoid "Argument list too long" errors
echo "$L1_CONTRACTS" > "$TEMP_DIR/l1_contracts.json"
echo "$L1_SERVICES" > "$TEMP_DIR/l1_services.json"
echo "$L1_ACCOUNTS" > "$TEMP_DIR/l1_accounts.json"

L1_NETWORK=$(jq -n \
    --slurpfile contracts "$TEMP_DIR/l1_contracts.json" \
    --slurpfile services "$TEMP_DIR/l1_services.json" \
    --slurpfile accounts "$TEMP_DIR/l1_accounts.json" \
    --arg chain_id "$L1_CHAIN_ID" \
    --arg block "$L1_BLOCK" \
    --arg hash "$L1_HASH" \
    --arg genesis_hash "$GENESIS_HASH" \
    '{
        chain_id: $chain_id,
        snapshot_block: {
            number: $block,
            hash: $hash
        },
        genesis_hash: $genesis_hash,
        contracts: $contracts[0],
        services: $services[0],
        accounts: $accounts[0]
    }')

# ============================================================================
# Build Agglayer Info (if present)
# ============================================================================

AGGLAYER_INFO="null"

if [ "$AGGLAYER_FOUND" = "true" ]; then
    log "Building Agglayer info..."

    # Agglayer service URLs
    AGGLAYER_SERVICES=$(cat <<EOF
{
    "grpc_rpc": {
        "internal": "http://agglayer:4443",
        "external": "http://localhost:4443"
    },
    "read_rpc": {
        "internal": "http://agglayer:4444",
        "external": "http://localhost:4444"
    },
    "admin_api": {
        "internal": "http://agglayer:4446",
        "external": "http://localhost:4446"
    },
    "metrics": {
        "internal": "http://agglayer:9092/metrics",
        "external": "http://localhost:9092/metrics"
    }
}
EOF
)

    # Use temp files to avoid "Argument list too long" errors
    echo "$AGGLAYER_SERVICES" > "$TEMP_DIR/agglayer_services.json"

    AGGLAYER_INFO=$(jq -n \
        --slurpfile services "$TEMP_DIR/agglayer_services.json" \
        '{
            services: $services[0]
        }')
fi

# ============================================================================
# Build L2 Networks Info
# ============================================================================

L2_NETWORKS="{}"

if [ "$L2_CHAINS_COUNT" != "null" ] && [ "$L2_CHAINS_COUNT" -gt 0 ]; then
    log "Building L2 networks info..."

    for prefix in $(jq -r '.l2_chains | keys[]' "$DISCOVERY_JSON" 2>/dev/null); do
        log "  Processing L2 network: $prefix"

        # Port offsets -- see snapshot/scripts/lib/ports.sh
        L2_HTTP_PORT=$(snapshot_l2_port "$prefix" http)
        L2_WS_PORT=$(snapshot_l2_port "$prefix" ws)
        L2_ENGINE_PORT=$(snapshot_l2_port "$prefix" engine)
        L2_NODE_RPC_PORT=$(snapshot_l2_port "$prefix" node_rpc)
        L2_NODE_METRICS_PORT=$(snapshot_l2_port "$prefix" node_metrics)
        L2_AGGKIT_RPC_PORT=$(snapshot_l2_port "$prefix" aggkit_rpc)
        L2_AGGKIT_REST_PORT=$(snapshot_l2_port "$prefix" aggkit_rest)

        # Get L2 chain ID
        ROLLUP_FILE="$OUTPUT_DIR/config/$prefix/rollup.json"
        L2_CHAIN_ID="unknown"
        if [ -f "$ROLLUP_FILE" ]; then
            L2_CHAIN_ID=$(jq -r '.l2_chain_id // .genesis.l2.chain_id // "unknown"' "$ROLLUP_FILE")
        fi

        # Extract contract addresses from aggkit config
        L2_CONTRACTS="{}"
        AGGKIT_CONFIG="$OUTPUT_DIR/config/$prefix/aggkit-config.toml"
        if [ -f "$AGGKIT_CONFIG" ]; then
            # Extract bridge addresses and other contracts (use head -1 to ensure single value)
            L1_BRIDGE=$(grep "^BridgeAddr" "$AGGKIT_CONFIG" | head -1 | cut -d'"' -f2 2>/dev/null || echo "")
            L2_BRIDGE=$(grep -A10 "^\[L2Config\]" "$AGGKIT_CONFIG" | grep "^BridgeAddr" | head -1 | cut -d'"' -f2 2>/dev/null || echo "")
            ROLLUP_MANAGER=$(grep "RollupManagerAddr" "$AGGKIT_CONFIG" | head -1 | cut -d'"' -f2 2>/dev/null || echo "")
            GER_CONTRACT=$(grep -A10 "^\[L2Config\]" "$AGGKIT_CONFIG" | grep "^GlobalExitRootAddr" | head -1 | cut -d'"' -f2 2>/dev/null || echo "")

            L2_CONTRACTS=$(jq -n \
                --arg l1_bridge "$L1_BRIDGE" \
                --arg l2_bridge "$L2_BRIDGE" \
                --arg rollup_manager "$ROLLUP_MANAGER" \
                --arg ger "$GER_CONTRACT" \
                '{
                    l1_bridge: (if $l1_bridge != "" then $l1_bridge else null end),
                    l2_bridge: (if $l2_bridge != "" then $l2_bridge else null end),
                    rollup_manager: (if $rollup_manager != "" then $rollup_manager else null end),
                    global_exit_root: (if $ger != "" then $ger else null end)
                }')
        fi

        # L2 service URLs
        L2_SERVICES=$(jq -n \
            --arg prefix "$prefix" \
            --arg http_port "$L2_HTTP_PORT" \
            --arg ws_port "$L2_WS_PORT" \
            --arg engine_port "$L2_ENGINE_PORT" \
            --arg node_rpc_port "$L2_NODE_RPC_PORT" \
            --arg node_metrics_port "$L2_NODE_METRICS_PORT" \
            --arg aggkit_rpc_port "$L2_AGGKIT_RPC_PORT" \
            --arg aggkit_rest_port "$L2_AGGKIT_REST_PORT" \
            '{
                "op-reth": {
                    http_rpc: {
                        internal: ("http://op-reth-" + $prefix + ":8545"),
                        external: ("http://localhost:" + $http_port)
                    },
                    ws_rpc: {
                        internal: ("ws://op-reth-" + $prefix + ":8546"),
                        external: ("ws://localhost:" + $ws_port)
                    },
                    engine_api: {
                        internal: ("http://op-reth-" + $prefix + ":8551"),
                        external: ("http://localhost:" + $engine_port)
                    }
                },
                "op-node": {
                    rpc: {
                        internal: ("http://op-node-" + $prefix + ":8547"),
                        external: ("http://localhost:" + $node_rpc_port)
                    },
                    metrics: {
                        internal: ("http://op-node-" + $prefix + ":7300"),
                        external: ("http://localhost:" + $node_metrics_port)
                    }
                }
            }')

        # Add aggkit services if present
        if [ -f "$AGGKIT_CONFIG" ]; then
            L2_SERVICES=$(echo "$L2_SERVICES" | jq \
                --arg prefix "$prefix" \
                --arg rpc_port "$L2_AGGKIT_RPC_PORT" \
                --arg rest_port "$L2_AGGKIT_REST_PORT" \
                '. + {
                    aggkit: {
                        rpc: {
                            internal: ("http://aggkit-" + $prefix + ":5576"),
                            external: ("http://localhost:" + $rpc_port)
                        },
                        rest_api: {
                            internal: ("http://aggkit-" + $prefix + ":5577"),
                            external: ("http://localhost:" + $rest_port)
                        }
                    }
                }')
        fi

        # L2 accounts from genesis (exclude OP predeploy contracts)
        L2_GENESIS_FILE="$OUTPUT_DIR/config/$prefix/l2-genesis.json"
        L2_ACCOUNTS=$(extract_genesis_accounts "$L2_GENESIS_FILE" "L2 network $prefix" "true")

        # Add aggkit accounts from keystores
        if [ -f "$AGGKIT_CONFIG" ]; then
            SEQUENCER_KEYSTORE="$OUTPUT_DIR/config/$prefix/sequencer.keystore"
            AGGORACLE_KEYSTORE="$OUTPUT_DIR/config/$prefix/aggoracle.keystore"
            SOVEREIGNADMIN_KEYSTORE="$OUTPUT_DIR/config/$prefix/sovereignadmin.keystore"
            CLAIMSPONSOR_KEYSTORE="$OUTPUT_DIR/config/$prefix/claimsponsor.keystore"

            AGGKIT_ACCOUNTS="[]"

            # Sequencer
            if [ -f "$SEQUENCER_KEYSTORE" ]; then
                SEQUENCER_ADDR=$(extract_keystore_address "$SEQUENCER_KEYSTORE")
                if [ -n "$SEQUENCER_ADDR" ]; then
                    [[ "$SEQUENCER_ADDR" != 0x* ]] && SEQUENCER_ADDR="0x$SEQUENCER_ADDR"
                    AGGKIT_ACCOUNTS=$(echo "$AGGKIT_ACCOUNTS" | jq \
                        --arg addr "$SEQUENCER_ADDR" \
                        '. + [{
                            address: $addr,
                            private_key: "(encrypted in keystore)",
                            description: "L2 Sequencer account (signs L2 blocks)"
                        }]')
                fi
            fi

            # AggOracle
            if [ -f "$AGGORACLE_KEYSTORE" ]; then
                AGGORACLE_ADDR=$(extract_keystore_address "$AGGORACLE_KEYSTORE")
                if [ -n "$AGGORACLE_ADDR" ]; then
                    [[ "$AGGORACLE_ADDR" != 0x* ]] && AGGORACLE_ADDR="0x$AGGORACLE_ADDR"
                    AGGKIT_ACCOUNTS=$(echo "$AGGKIT_ACCOUNTS" | jq \
                        --arg addr "$AGGORACLE_ADDR" \
                        '. + [{
                            address: $addr,
                            private_key: "(encrypted in keystore)",
                            description: "AggOracle account (submits L1 data to L2)"
                        }]')
                fi
            fi

            # SovereignAdmin
            if [ -f "$SOVEREIGNADMIN_KEYSTORE" ]; then
                SOVEREIGNADMIN_ADDR=$(extract_keystore_address "$SOVEREIGNADMIN_KEYSTORE")
                if [ -n "$SOVEREIGNADMIN_ADDR" ]; then
                    [[ "$SOVEREIGNADMIN_ADDR" != 0x* ]] && SOVEREIGNADMIN_ADDR="0x$SOVEREIGNADMIN_ADDR"
                    AGGKIT_ACCOUNTS=$(echo "$AGGKIT_ACCOUNTS" | jq \
                        --arg addr "$SOVEREIGNADMIN_ADDR" \
                        '. + [{
                            address: $addr,
                            private_key: "(encrypted in keystore)",
                            description: "Sovereign Admin account (manages L2 bridge)"
                        }]')
                fi
            fi

            # ClaimSponsor
            if [ -f "$CLAIMSPONSOR_KEYSTORE" ]; then
                CLAIMSPONSOR_ADDR=$(extract_keystore_address "$CLAIMSPONSOR_KEYSTORE")
                if [ -n "$CLAIMSPONSOR_ADDR" ]; then
                    [[ "$CLAIMSPONSOR_ADDR" != 0x* ]] && CLAIMSPONSOR_ADDR="0x$CLAIMSPONSOR_ADDR"
                    AGGKIT_ACCOUNTS=$(echo "$AGGKIT_ACCOUNTS" | jq \
                        --arg addr "$CLAIMSPONSOR_ADDR" \
                        '. + [{
                            address: $addr,
                            private_key: "(encrypted in keystore)",
                            description: "Claim Sponsor account (sponsors bridge claims)"
                        }]')
                fi
            fi

            # Merge with L2 accounts
            L2_ACCOUNTS=$(jq -s '.[0] + .[1]' <(echo "$L2_ACCOUNTS") <(echo "$AGGKIT_ACCOUNTS"))
        fi

        # Build L2 network object
        # Use temp files to avoid "Argument list too long" errors with large account lists
        echo "$L2_CONTRACTS" > "$TEMP_DIR/l2_contracts_${prefix}.json"
        echo "$L2_SERVICES" > "$TEMP_DIR/l2_services_${prefix}.json"
        echo "$L2_ACCOUNTS" > "$TEMP_DIR/l2_accounts_${prefix}.json"

        L2_NETWORK=$(jq -n \
            --arg chain_id "$L2_CHAIN_ID" \
            --slurpfile contracts "$TEMP_DIR/l2_contracts_${prefix}.json" \
            --slurpfile services "$TEMP_DIR/l2_services_${prefix}.json" \
            --slurpfile accounts "$TEMP_DIR/l2_accounts_${prefix}.json" \
            '{
                chain_id: $chain_id,
                contracts: $contracts[0],
                services: $services[0],
                accounts: $accounts[0]
            }')

        # Add to L2_NETWORKS
        # Use temp files to avoid "Argument list too long" errors
        echo "$L2_NETWORK" > "$TEMP_DIR/l2_network_current.json"
        echo "$L2_NETWORKS" > "$TEMP_DIR/l2_networks_current.json"
        L2_NETWORKS=$(jq --arg prefix "$prefix" --slurpfile network "$TEMP_DIR/l2_network_current.json" \
            '. + {($prefix): $network[0]}' "$TEMP_DIR/l2_networks_current.json")

        log "  ✓ L2 network $prefix info collected"
    done
fi

# ============================================================================
# Build Final Summary JSON
# ============================================================================

log "Building final summary.json..."

# Use temp files to avoid "Argument list too long" errors with large network data
echo "$L1_NETWORK" > "$TEMP_DIR/l1_network.json"
echo "$AGGLAYER_INFO" > "$TEMP_DIR/agglayer_info.json"
echo "$L2_NETWORKS" > "$TEMP_DIR/l2_networks.json"

SUMMARY=$(jq -n \
    --arg snapshot_name "$SNAPSHOT_ID" \
    --arg enclave "$ENCLAVE_NAME" \
    --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg l1_mnemonic "$DEFAULT_L1_MNEMONIC" \
    --arg l2_mnemonic "$DEFAULT_L2_MNEMONIC" \
    --slurpfile l1 "$TEMP_DIR/l1_network.json" \
    --slurpfile agglayer "$TEMP_DIR/agglayer_info.json" \
    --slurpfile l2_networks "$TEMP_DIR/l2_networks.json" \
    '{
        snapshot_name: $snapshot_name,
        enclave: $enclave,
        created_at: $timestamp,
        networks: {
            l1: $l1[0],
            agglayer: $agglayer[0],
            l2_networks: $l2_networks[0]
        },
        test_accounts: {
            l1_mnemonic: $l1_mnemonic,
            l2_mnemonic: $l2_mnemonic,
            note: "Pre-funded test accounts are derived from these mnemonics. Use with cast: cast wallet address --mnemonic \"<mnemonic>\" --mnemonic-index <0-N>"
        },
        notes: {
            accounts: "Only accounts with meaningful balances are included. Precompile addresses (0x0000...00xx) and OP predeploy contracts (0x4200...) are excluded. Private keys for keystores are encrypted.",
            services: "Internal URLs are for use within the Docker network. External URLs are for access from the host machine.",
            contracts: "Contract addresses are extracted from configuration files. Some fields may be null if not found."
        }
    }')

# Write to file
SUMMARY_FILE="$OUTPUT_DIR/summary.json"
echo "$SUMMARY" | jq '.' > "$SUMMARY_FILE"

log "✓ Summary generated: $SUMMARY_FILE"

# Pretty print summary
log ""
log "Summary overview:"
log "  L1 Chain ID: $L1_CHAIN_ID"
log "  L1 Services: $(echo "$L1_SERVICES" | jq -r 'keys | length') service(s)"
log "  L1 Accounts: $(echo "$L1_ACCOUNTS" | jq 'length')"

if [ "$AGGLAYER_FOUND" = "true" ]; then
    log "  Agglayer: Present"
fi

if [ "$L2_CHAINS_COUNT" != "null" ] && [ "$L2_CHAINS_COUNT" -gt 0 ]; then
    log "  L2 Networks: $L2_CHAINS_COUNT network(s)"
fi

log ""
log "Summary generation complete!"

exit 0
