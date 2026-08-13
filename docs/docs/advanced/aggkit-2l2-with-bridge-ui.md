---
sidebar_position: 5
---

# AggKit 2-L2 with Bridge UI

## Introduction

This guide sets up a **two-rollup L2 enclave** with AggKit bridge services, automated claim routing (autoclaim), and the [Agglayer Dev UI](https://github.com/agglayer/agglayer-dev-ui) for browser-based bridging between L1 and both L2s, as well as between the two L2s themselves.

### What's Deployed?

- **L1 Ethereum blockchain** (lighthouse/geth)
- **Agglayer stack** ([contracts](https://github.com/agglayer/agglayer-contracts), [agglayer service](https://github.com/agglayer/agglayer), mock prover)
- **Two L2 Optimism blockchains** (op-reth/op-node), each enhanced with [AggKit](https://github.com/agglayer/aggkit) for Agglayer connectivity:
  - **L2-1**: network_id = 1, chain_id = 20201
  - **L2-2**: network_id = 2, chain_id = 20202
- **AggKit bridge REST APIs** (one per L2, syncing the shared L1 bridge state; each
  `aggkit-00X` process serves both its main components AND the bridge REST API in one
  container — `--components=...,bridge`):
  - `aggkit-001:5577` (REST)
  - `aggkit-002:5577` (REST)
- **AggKit proxy** (`aggkit-proxy-001:8080`) — runs with `--components=proxy,tracker`:
  - **proxy**: multiplexes all three networks (L1 + both L2s) via `network_id` query parameter routing
  - **tracker**: serves `/tracker/v1` (per-bridge-transaction status/progress tracking, backed by the Agglayer gRPC endpoint)
- **HAProxy** (`agglayer-dev-ui-proxy-002`) — handles CORS and routes the UI's API calls:
  - `/l1rpc` → L1 EL RPC
  - `/l2rpc` → L2-1 RPC (chain-1-only back-compat alias)
  - `/l2rpc-001` → L2-1 RPC
  - `/l2rpc-002` → L2-2 RPC
  - `/aggkitapi` → AggKit proxy (all networks, selected via `?network_id=`; also fronts `/aggkitapi/tracker/v1/...`)
- **Automated claim routing** (autoclaim) on both L2s, with configurable destinations
- **UI and supporting services**:
  - [Agglayer Dev UI](https://github.com/agglayer/agglayer-dev-ui) for browser-based bridging

### Use Cases

- Testing L2-to-L2 bridging scenarios (cross-rollup asset transfers)
- Validating bridge UI functionality against multiple chains
- Developing L2-to-L2 settlement features in AggKit and AggLayer
- Automated claim processing across multiple rollups

### Prerequisites

This setup requires an AggKit image that includes both the `aggkit` and `aggkit-proxy` binaries.
The params files below pin the registry image `ghcr.io/agglayer/aggkit:0.11.0-rc5` — no local
build is needed. See [Image Version](#image-version) for details.

## Deployment

### Step 1: Create the Parameter Files

The 2-L2 setup uses **two consecutive runs** into the same enclave (idempotent L1/agglayer deploy in run1, then L2-2 creation in run2).

**Run 1 params file (`params-aggkit-l2l2-run1.yml`):**

```yaml
args:
  sequencer_type: op-reth
  consensus_contract_type: ecdsa-multisig

  # AggKit image: registry release, includes the aggkit-proxy binary and the
  # bridge-tracker (see Image Version below)
  aggkit_image: ghcr.io/agglayer/aggkit:0.11.0-rc5

  # AggKit components: aggsender and aggoracle on the main service, plus autoclaim
  # and bridge (the bridge REST API is served by this SAME process/container --
  # there is no separate aggkit-001-bridge service)
  aggkit_components: "aggsender,aggoracle,autoclaim,bridge"
  # Enable autoclaim on L2-1 (network_id = 1)
  aggkit_autoclaim_destinations: [1]
  # Static bridge service URLs for autoclaim discovery
  aggkit_autoclaim_bridge_urls:
    - network_id: 1
      bridge_url: "http://aggkit-001:5577"
    - network_id: 2
      bridge_url: "http://aggkit-002:5577"

  # Declare rollup-2 to agglayer so it accepts rollup-2 certificates
  # (both RPC URL and sequencer address are deterministic)
  agglayer_extra_rollups:
    - network_id: 2
      op_el_rpc_url: "http://op-el-1-op-reth-op-node-002:8545"
      sequencer_address: "0x5b06837A43bdC3dD9F114558DAf4B26ed49842Ed"

  # Bridge UI additional service (haproxy + dev UI)
  additional_services:
    - bridge_ui

deployment_stages:
  deploy_l1: true
  deploy_agglayer: true
```

**Run 2 params file (`params-aggkit-l2l2-run2.yml`):**

```yaml
deployment_stages:
  deploy_l1: false          # L1 already deployed in run1
  deploy_agglayer: false    # Agglayer already deployed in run1, reused

args:
  sequencer_type: op-reth
  consensus_contract_type: ecdsa-multisig

  # Same registry image as run1
  aggkit_image: ghcr.io/agglayer/aggkit:0.11.0-rc5

  # Create a second rollup (L2-2)
  deployment_suffix: "-002"
  l2_chain_id: 20202
  network_id: 2

  # Rollup-2's aggkit instance: same autoclaim config as rollup-1, plus bridge
  # (see run1's comment above -- no separate aggkit-002-bridge service)
  aggkit_components: "aggsender,aggoracle,autoclaim,bridge"
  aggkit_autoclaim_destinations: [2]    # Claim on L2-2 (its own destination)
  aggkit_autoclaim_bridge_urls:
    - network_id: 1
      bridge_url: "http://aggkit-001:5577"
    - network_id: 2
      bridge_url: "http://aggkit-002:5577"

  # AggKit proxy (fronts all networks for the bridge UI)
  additional_services:
    - aggkit_proxy

  # Static maps for the proxy: network_id → bridge REST URL and RPC URL
  aggkit_proxy_bridge_urls:
    - network_id: 0
      bridge_url: "http://aggkit-001:5577"  # L1 side is synced via any aggkit instance
    - network_id: 1
      bridge_url: "http://aggkit-001:5577"
    - network_id: 2
      bridge_url: "http://aggkit-002:5577"

  aggkit_proxy_rpc_urls:
    - network_id: 0
      rpc_url: "http://el-1-geth-lighthouse:8545"
    - network_id: 1
      rpc_url: "http://op-el-1-op-reth-op-node-001:8545"
    - network_id: 2
      rpc_url: "http://op-el-1-op-reth-op-node-002:8545"
```

### Step 2: Bring Up the Enclave

```bash
cd /path/to/kurtosis-cdk

# Always start fresh — the run2 contract-deployment script is not idempotent
kurtosis enclave rm -f cdk

# Run 1: Deploy L1, Agglayer, and L2-1
kurtosis run --enclave cdk --args-file params-aggkit-l2l2-run1.yml .

# Run 2: Add L2-2 and the proxy (into the same enclave)
kurtosis run --enclave cdk --args-file params-aggkit-l2l2-run2.yml .
```

Expected output: `Starlark code successfully run` (exit 0) for both runs. Total wall time: ~8 minutes.

### Step 3: Verify the Enclave

```bash
kurtosis enclave inspect cdk
```

All 26 services should be `RUNNING`:
- L1 services (el-1-geth-lighthouse, cl-1-lighthouse-geth, vc-1-...)
- Agglayer (agglayer)
- L2-1 services (op-el-1-op-reth-op-node-001, op-cl-...-001, op-batcher-001, proxyd-001)
- L2-2 services (op-el-1-op-reth-op-node-002, op-cl-...-002, op-batcher-002, proxyd-002)
- AggKit services (aggkit-001, aggkit-002 -- each also serving the bridge REST API in the
  same container, `--components=...,bridge`; there is no separate `-bridge` sibling)
- AggKit proxy (aggkit-proxy-001)
- Bridge UI proxy (agglayer-dev-ui-proxy-002)
- Database services (postgres-001, postgres-002)
- Contract deployment services (contracts-001, contracts-002)

### Step 4: Configure the Bridge UI

Use the devnet setup script to populate the UI's configuration:

```bash
cd /path/to/agglayer-dev-ui

# Discover ports and write config.json + .env.local
node scripts/kurtosisDevnetEnv.mjs --enclave cdk
```

This script:
- Discovers L2 suffixes (001, 002) from the enclave
- Resolves the haproxy service and all RPC URLs
- Writes `config.json` with three chains: DEVNET_L1, DEVNET_L2_001, DEVNET_L2_002
- Writes `.env.local` with `NEXT_PUBLIC_AGGKIT_BRIDGE_APIS` pointed at the proxy

### Step 5: Run the Bridge UI

```bash
cd /path/to/agglayer-dev-ui

# Start the dev server (uses config.json + .env.local from step 4)
pnpm run dev

# Open http://localhost:3000 in your browser
```

The UI will display:
- **From chain selector** with L1, L2-1, L2-2
- **To chain selector** with L1, L2-1, L2-2
- Bridge form supporting all routes (L1→L2-1, L1→L2-2, L2-1→L1, L2-1→L2-2, L2-2→L1, L2-2→L2-1)
- Activity list showing bridge and claim transactions across all chains

## Configuration Details

### Autoclaim Configuration

Autoclaim is enabled per-chain via two parameters:

1. **`aggkit_autoclaim_destinations`** — List of destination network IDs this instance should claim on.
   - `[1]` on L2-1 (run1)
   - `[2]` on L2-2 (run2)
   - Never include `0` (L1), as this setup intentionally makes L2→L1 claims manual-only

2. **`aggkit_autoclaim_bridge_urls`** — Static map of network_id → bridge REST URL.
   - Required because on-chain `BRIDGE_SERVICE_URL` metadata is not registered in this devnet
   - Identical on both L2 instances (they see the same L1 bridge state and both L2 bridges)

**Current autoclaim latencies** (from S12 enclave results):
- L1→L2 auto-claim: ~67 seconds
- L2→L2 auto-claim: Request detected within ~7 minutes (certificate settlement + L1 info tree sync); submission may be blocked by an upstream aggkit bug in networks where L2 block height exceeds L1 (see notes below)
- L2→L1: Always manual-only; proof ready within ~9-10 minutes

**Grace timeout in the UI** (`app/constants/e2e.ts`):
- `E2E_L1_TO_L2_CLAIM_TIMEOUT_MS: 180000` (3 minutes) — covers the ~67s latency with margin
- `E2E_L2_TO_L2_CLAIM_TIMEOUT_MS: 300000` (5 minutes) — **has no margin against certificate cadence** (see notes)

### AggKit Proxy Configuration

The proxy multiplexes all three networks (L1 + both L2s) via the `network_id` query parameter:

**Query parameter semantics:**
- `/bridge/v1/bridges?network_id=0` → L1 origin/destination routes (routed to any aggkit instance; all sync the same L1 state)
- `/bridge/v1/bridges?network_id=1` → L2-1 origin/destination routes (routed to aggkit-001)
- `/bridge/v1/bridges?network_id=2` → L2-2 origin/destination routes (routed to aggkit-002)

**Proxy configuration args:**
- `aggkit_proxy_bridge_urls` — Static map of network_id → `aggkit-00X:5577` URL
- `aggkit_proxy_rpc_urls` — Static map of network_id → L2 RPC URL (used for proof validation)

Both maps are supplied at run2 time (they require both aggkit instances to already exist).

### Bridge Tracker Configuration

`aggkit-proxy-001` runs with `--components=proxy,tracker`, so the same process also serves
`/tracker/v1` — per-bridge-transaction status and step-by-step progress, read from the
Agglayer gRPC endpoint. The template lives at
`static_files/additional_services/aggkit-proxy/config.toml` under `[Tracker]`:

```toml
[Tracker]
RetentionPeriod = "30m"
IdleTimeout = "30m"
RegisterResolveTimeout = "3s"
L1BlockFinality = "LatestBlock"
L2BlockFinality = "LatestBlock"
MaxTrackedBridges = 100000
L1GlobalExitRootAddress = "{{.l1_global_exit_root_address}}"

[Tracker.AgglayerClient.GRPC]
URL = "{{.agglayer_grpc_url}}"
```

**Why `L1GlobalExitRootAddress` matters:** unlike `BridgeAddrs` (which the tracker can discover
on-chain if left unset), `L1GlobalExitRootAddress` has **no on-chain discovery fallback**
(confirmed in aggkit's `bridgetracker/sources/ger.go`, unchanged through rc5). Left unset, it
defaults to the zero address, because the tracker's `GERSource` filters L1 logs by that exact
address. As of aggkit v0.11.0-rc5 (`bridgetracker/config.go`'s `Config.Validate`,
[agglayer/aggkit#1784](https://github.com/agglayer/aggkit/pull/1784)), the proxy now **fails fast
at startup** with a clear error if this resolves to the zero address, instead of starting and
silently stalling `StepWaitingGERUpdate` for every L1→L2 bridge as it did under rc4. This package
threads a real address through `contract_setup_addresses["l1_ger_address"]` — the same mechanism
already used for `rollup_manager_address` — into `aggkit_proxy.star`'s template data, so the
rc5 startup check passes without any config change. If you fork this config for a new
environment, do not drop this field.

**Other notable settings:**
- `RetentionPeriod = "30m"` — raised from the binary's 10m default so a slow L2→L1 demo
  certificate (agglayer settlement can take a while) stays queryable through `/tracker/v1`
  instead of falling out of the registry mid-demo. Once a tracked bridge is evicted, the next
  poll simply re-registers it (status `registered`, `all_steps: null`) — see the SDK's
  `getBridgeTracking` docs for how a client should handle this.
- `[REST] MaxRequestsPerIPAndSecond = 0` — matches the binary's own default as of aggkit
  v0.11.0-rc5. This field is unenforced in `RESTConfig`-backed sections (no middleware reads it);
  aggkit's `docs/common_config.md` documents it as unused and recommends applying rate limiting
  at the infra layer (e.g. haproxy) instead.

Reachable through haproxy at `/aggkitapi/tracker/v1/...` (haproxy strips the `/aggkitapi` prefix
before forwarding to the proxy's `/tracker/v1/...`).

**Smoke-test the tracker once the enclave is up:**

```bash
# `kurtosis port print` outputs the full URL (e.g. http://127.0.0.1:33015)
HAPROXY_URL=$(kurtosis port print cdk agglayer-dev-ui-proxy-002 http)

# Health check
curl -s "${HAPROXY_URL}/aggkitapi/tracker/v1/health"

# Register/query a bridge transaction's tracking status (first call registers it if unseen)
curl -s "${HAPROXY_URL}/aggkitapi/tracker/v1/network/1/tx/0x<bridgeTxHash>"
```

The tx-tracking response includes `tracking_status` (`registered`, `running`, `finished`, or
`error`), `bridge_type`, and (once populated) `all_steps` with a `step_name`/`status` per step. See
the [AggLayer SDK](https://github.com/agglayer/sdk)'s `getBridgeTracking` client method for the
full wire-format reference and polling guidance.

### HAProxy Route Map

The UI's browser requests are routed through HAProxy (`agglayer-dev-ui-proxy-002`), which:
- Handles CORS (UI requests never touch aggkit directly; all go through the proxy)
- Routes requests based on path:

| Path | Backend | Network(s) |
|------|---------|-----------|
| `/l1rpc` | L1 EL RPC (`el-1-geth-lighthouse:8545`) | L1 only |
| `/l2rpc` | L2-1 RPC (op-el-1-op-reth-op-node-001:8545) | L2-1 (back-compat alias, never "current") |
| `/l2rpc-001` | L2-1 RPC | L2-1 |
| `/l2rpc-002` | L2-2 RPC | L2-2 |
| `/aggkitapi` | AggKit proxy (aggkit-proxy-001:8080) | All networks (selected by `?network_id=`) |
| `/aggkitapi/tracker/v1/...` | AggKit proxy's tracker component (aggkit-proxy-001:8080) | All networks (selected by network id in the path) |

**Dev UI configuration:**
The script `scripts/kurtosisDevnetEnv.mjs` writes:
```json
{
  "appModes": {
    "configs": {
      "devnet": {
        "aggkitBridgeApis": {
          "1": "http://127.0.0.1:<haproxyPort>/aggkitapi",
          "2": "http://127.0.0.1:<haproxyPort>/aggkitapi"
        },
        "chainKeys": ["DEVNET_L1", "DEVNET_L2_001", "DEVNET_L2_002"],
        "defaultFromChainKey": "DEVNET_L1",
        "defaultToChainKey": "DEVNET_L2_001"
      }
    }
  }
}
```

Both networks use the **same proxy URL** — routing to different backends happens via `network_id` query parameter.

## Important Notes

### Image Version

Both params files pin the registry image `ghcr.io/agglayer/aggkit:0.11.0-rc5`. No local build is
required — `kurtosis run` pulls it like any other image.

`aggkit:0.11.0-rc5` bundles both the `aggkit` and `aggkit-proxy` binaries; the proxy service
overrides the image's `aggkit` entrypoint to run `aggkit-proxy` (see
`src/additional_services/aggkit_proxy.star`). You can confirm both binaries are present with:

```bash
docker run --rm ghcr.io/agglayer/aggkit:0.11.0-rc5 version
docker run --rm --entrypoint /usr/local/bin/aggkit-proxy \
  ghcr.io/agglayer/aggkit:0.11.0-rc5 version
```

**Why not `develop`:** an earlier iteration of this guide pinned a locally-built patched image
because L2→L2 autoclaim never fired on the `develop` image at the time — the claimer compared an
L1 info-tree leaf's L1 block number against the source rollup's own L2 block number, so on a
devnet whose L2 height exceeds L1's the readiness gate never opened and requests stayed queued
indefinitely (`proof not ready for request constraints`, retrying forever). That fix
(agglayer/aggkit [#1761](https://github.com/agglayer/aggkit/pull/1761)) has been upstream since
rc4, so the local build is no longer needed. The image also carries the `aggkit-proxy`
bridge-tracker component used by this guide (see
[Bridge Tracker Configuration](#bridge-tracker-configuration)).

**Why rc5 specifically (over rc4):** rc5 adds fail-fast startup validation on
`[Tracker].L1GlobalExitRootAddress` (see [Why `L1GlobalExitRootAddress`
matters](#bridge-tracker-configuration) above, [agglayer/aggkit#1782](https://github.com/agglayer/aggkit/issues/1782))
and changes `MaxRequestsPerIPAndSecond`'s default
in `RESTConfig`-backed sections from `10` to `0` (see [Other notable
settings](#bridge-tracker-configuration) above, [agglayer/aggkit#1783](https://github.com/agglayer/aggkit/issues/1783)),
plus the `bridgetracker/API.md` doc correction ([agglayer/aggkit#1781](https://github.com/agglayer/aggkit/issues/1781),
fixed by [PR #1784](https://github.com/agglayer/aggkit/pull/1784)) and an unrelated bridgesync
DB-index performance fix. None of these required a config change in this package.

:::note Version-gate correctness
This package's Starlark version-comparison helpers (`_parse_aggkit_major_minor` in
`src/chain/shared/aggkit.star`) parse `<major>.<minor>` as an integer tuple rather than collapsing
it to a float or comparing it lexicographically as a string. Both of those alternatives put
`0.11` *below* `0.3`/`0.8` (`"0.11" < "0.8"` lexicographically, and `0.11 < 0.8` as a float), which
would wrongly render the hard-failing deprecated `polygonBridgeAddr` config key and route rc4 to
the `readrpc` agglayer endpoint instead of `grpc`. If you bump to a future aggkit minor version
past single digits again, this is already handled — no template changes needed.
:::

### Non-Idempotency Warning

The run2 contract-deployment script (`deploy_agglayer_core_contracts`) is **not idempotent** — it fails with "This script has already been executed" if run again into the same enclave.

**Always start fresh before running the sequence:**
```bash
kurtosis enclave rm -f cdk
# Then run both params files fresh
```

### Certificate Cadence and E2E Timeouts

AggKit's aggsender logs `MinimumNewCertificateInterval: 5m0s` (aggkit's own default, `config/default.go`).
Despite the name this is **not** a minimum spacing between certificates and **not** a rate limit —
it is a maximum-idle heartbeat. `fulfillMinimumInterval`
(`aggsender/trigger/trigger_asap.go`) schedules an extra trigger 5 minutes after the last event and
then **skips it if any other trigger was already programmed** in the meantime. The primary driver is
the ASAP trigger: a new certificate is attempted as soon as the previous one reaches a final state
(settled or in error), subject to `DelayBetweenCertificates: 1s`. In a live 2-L2 enclave the
aggsender logs a certificate attempt roughly every 2 seconds.

So a deposit does **not** wait up to 5 minutes for a "certificate window". Measured end-to-end
L2→L2 send→claimed latencies in this topology were ~87 s (busy enclave) to ~2 m 11 s (idle enclave).

The dev-ui E2E suite's `l2-to-l2.spec.ts` budget (`E2E_L2_TO_L2_CLAIM_TIMEOUT_MS`, default 8 minutes)
is therefore sized off those measured latencies, not off the 5-minute heartbeat. It is deliberately
generous: an earlier triage run did time out at a 5-minute budget, and every latency figure here is
a single sample from a shared, traffic-contaminated enclave. Override with
`E2E_L2_TO_L2_CLAIM_TIMEOUT_MS` if your enclave is faster or slower.

### Shared Wallet State

The E2E wallet's balance and the enclave's transaction/certificate history both accumulate across test runs on the same enclave (never fully reset between UI interactions or consecutive test suites). This is benign for the current spec set, but any future spec requiring absolute balance assertions or a bounded activity-list length should account for this.

## E2E Testing

The bridge UI E2E suite supports this 2-L2 setup:

```bash
cd /path/to/agglayer-dev-ui

# Environment variables (set by kurtosisDevnetEnv.mjs, or manually):
export E2E_BACKEND_MODE=devnet
export E2E_TO_CHAIN_ID=20202        # L2-2 destination chain id
export E2E_L2_CHAIN_IDS=20201,20202 # Both L2 chain ids
export E2E_PRIVATE_KEY=<funded-devnet-key>

# Run the suite
pnpm run test:e2e
```

The suite includes:
- **claim-autoclaim.spec.ts** — L1→L2-1 auto-claim (L1ToL2BridgeDetector)
- **l2-to-l2.spec.ts** — L2-1→L2-2 auto-claim (L2ToLxBridgeDetector), *may timeout per certificate cadence note above*
- **manual-claim.spec.ts** — L2-1→L1 (manual-only), funds its own top-up then tests withdrawal
- Other tests: smoke, token selector, ERC20, native bridge, partial-failure notice

All tests assume `E2E_BACKEND_MODE=devnet` and will skip if not set.

## Troubleshooting

### "Failed to connect to aggkit" or "bridge service unreachable"

1. Verify `kurtosis enclave inspect cdk` shows all services `RUNNING`
2. Check the proxy port is correct: `kurtosis port print cdk agglayer-dev-ui-proxy-002 http`
3. Verify the config.json URL is pointing to the correct proxy port
4. Check haproxy logs: `kurtosis service logs cdk agglayer-dev-ui-proxy-002`

### "Network with id N is not configured"

The `scripts/kurtosisDevnetEnv.mjs` script discovers L2 suffixes automatically. If it finds only one (001), recheck:
- Both run1 and run2 completed successfully
- `kurtosis enclave inspect cdk` shows `aggkit-002` as `RUNNING`

### Enclave State Issues

If the enclave gets into an inconsistent state:
```bash
kurtosis enclave rm -f cdk    # Clean teardown
# Then re-run both params files from scratch
```

### After an enclave reset: recovering your wallet and UI

`kurtosis enclave rm` + a fresh bring-up resets every chain to genesis, but browser wallets
(MetaMask and similar injected wallets) cache per-account, per-network nonces and balances
locally — they have no way to know the chain moved. The first transaction sent after a reset
uses the wallet's stale, now-too-high cached nonce and hangs or fails silently.

**Symptoms:**

| Symptom | Cause |
|---------|-------|
| Transaction stuck "pending" forever | Wallet sent it with a nonce higher than the reset chain expects |
| Wallet shows "nonce too high" | Same — the wallet's cached nonce no longer matches on-chain state |
| Wrong/stale balances after reset | Wallet is still showing cached balance from before the reset |

**Fix the wallet:**

- **MetaMask**: Settings → Advanced → **Clear activity tab data**. This resets MetaMask's
  per-account, per-network nonce cache (and clears stale pending-tx history) without removing
  the account itself.
- **Other injected wallets**: look for an equivalent "reset activity"/"clear activity" action, or
  as a fallback, re-import the account.

**Re-sync the UI:**

1. Re-run `node scripts/kurtosisDevnetEnv.mjs --enclave cdk` from the dev-ui repo — the enclave's
   service ports are re-derived per instance on every bring-up (they are not stable across
   `enclave rm`/recreate cycles, only within one enclave's lifetime).
2. Restart `pnpm dev` so it picks up the rewritten `.env.local`/`config.json`.
3. Hard-reload the browser tab. The app's own `localStorage` caches (app mode, custom token
   imports) survive a reset and remain valid — chain ids are deterministic across enclave
   recreates, so the wallet's existing network entries stay correct. Only the RPC URLs' ports
   move, and step 1 already rewrote those into the config the app reads.

### Tracker troubleshooting

See [Bridge Tracker Configuration](#bridge-tracker-configuration) for the config reference. Common
failure modes when a row's tracking doesn't behave as expected:

1. **`WaitingClaim` step showing, but the UI's "Claim tokens" button hasn't appeared yet.** This
   is expected, not a bug — see upstream [agglayer/aggkit#1786](https://github.com/agglayer/aggkit/issues/1786)
   (OPEN). The tracker's `WaitingClaim` step reflects only a fast-path read of the settlement
   tx's own L1 receipt; it does not mean aggkit's bridge-service has finished the separate
   L1-info-tree sync that the claim button's `READY_TO_CLAIM` status (and the claim proof fetch)
   actually depends on. Measured on rc5: the tracker enters `WaitingClaim` roughly 16–22s before
   `/claim-proof` is actually servable. The dev-ui deliberately shows "Finalizing claim data…"
   during this window and gates the Claim button on its own `READY_TO_CLAIM` check, not on the
   tracker step — do not "fix" this by changing the UI copy while #1786 is open.
2. **A row shows no progress bar at all.** One of three causes:
   - The tracker hasn't resolved the bridge's route yet (`all_steps: null`, `tracking_status:
     registered` — normal, will populate shortly);
   - the bridge was evicted from the tracker's retention window and silently re-registered (see
     `RetentionPeriod` above) — same signature as a fresh registration, not an error;
   - the tracker gave up resolving the transaction entirely (`tracking_status: error` with
     `bridge_status: null`) — the UI shows a "Tracking unavailable" alert in this case.

   Diagnose with:
   ```bash
   HAPROXY_URL=$(kurtosis port print cdk agglayer-dev-ui-proxy-002 http)
   curl -s "${HAPROXY_URL}/aggkitapi/tracker/v1/network/<id>/tx/<hash>"
   ```
   and read `tracking_status`/`bridge_status`/`error` in the response.
3. **A step is stalled and not progressing.** Check which component that step depends on:
   - `WaitingGERUpdate` / `WaitingLERUpdate` — the L1 GlobalExitRoot contract and this package's
     `L1GlobalExitRootAddress` config (see above — a zero/misconfigured address now fails fast at
     rc5 startup instead of stalling silently, so if the proxy is running at all this is likely
     already correct);
   - `PendingInclusion` / `CertificatePending` — the aggsender/agglayer certificate pipeline;
     remember agglayer's own `MinimumNewCertificateInterval` cadence (5m by default — see
     [Certificate Cadence and E2E Timeouts](#certificate-cadence-and-e2e-timeouts));
   - `WaitingGERInjection` — the destination chain's aggoracle.

   Also check `tracker/v1/health` and the proxy's own logs
   (`kurtosis service logs cdk aggkit-proxy-001`) for errors.
4. **Suspected flooding/abuse.** `MaxRequestsPerIPAndSecond` is declared but unenforced in-process
   (see [Other notable settings](#bridge-tracker-configuration) above,
   [agglayer/aggkit#1783](https://github.com/agglayer/aggkit/issues/1783)) — if a flood is
   suspected, look at haproxy/infra-level rate limiting, not this field.

## References

- [AggKit GitHub](https://github.com/agglayer/aggkit)
- [Agglayer Dev UI GitHub](https://github.com/agglayer/agglayer-dev-ui)
- [AggLayer SDK](https://github.com/agglayer/sdk) — TypeScript client for bridge operations
- [Bridge Configuration Guide](../configuration/examples/bridge-ui.md)
- [Anvil Devnet Snapshot](./anvil-devnet-snapshot.md) — a fast-boot,
  `sequencer_type: anvil` equivalent of this same topology, captured as a
  self-contained docker-compose bundle consumable by dev-ui, aggkit, or agglayer (no
  Kurtosis toolchain needed to consume it)
