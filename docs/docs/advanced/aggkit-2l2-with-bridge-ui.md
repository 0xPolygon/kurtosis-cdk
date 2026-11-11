---
sidebar_position: 5
---

# AggKit 2-L2 with Bridge UI

## Introduction

This guide sets up a **two-rollup L2 enclave** with AggKit bridge services and the [Agglayer Dev UI](https://github.com/agglayer/agglayer-dev-ui) for browser-based bridging between L1 and both L2s, as well as between the two L2s themselves.

The same topology on `sequencer_type: anvil` chains, captured as a docker-compose bundle that boots in seconds, is described in [Anvil Devnet Snapshot](./anvil-devnet-snapshot.md).

### What's Deployed?

- **L1 Ethereum blockchain** (lighthouse/geth)
- **Agglayer stack** ([contracts](https://github.com/agglayer/agglayer-contracts), [agglayer service](https://github.com/agglayer/agglayer), mock prover)
- **Two L2 Optimism blockchains** (op-reth/op-node), each enhanced with [AggKit](https://github.com/agglayer/aggkit) for Agglayer connectivity:
  - **L2-1**: network_id = 1, chain_id = 20201
  - **L2-2**: network_id = 2, chain_id = 20202
- **AggKit bridge REST APIs**, one per L2, both syncing the shared L1 bridge state. With `bridge` in `aggkit_components` each `aggkit-00X` process serves its main components and the bridge REST API in one container:
  - `aggkit-001:5577` (REST)
  - `aggkit-002:5577` (REST)
- **AggKit proxy** (`aggkit-proxy-001:8080`), started with `--components=proxy,tracker`:
  - **proxy**: multiplexes all three networks (L1 + both L2s) via the `network_id` query parameter
  - **tracker**: serves `/tracker/v1` (per-bridge-transaction status and progress, backed by the Agglayer gRPC endpoint)
- **HAProxy** (`agglayer-dev-ui-proxy-002`): handles CORS and routes the UI's API calls (see [HAProxy Route Map](#haproxy-route-map))
- **[Agglayer Dev UI](https://github.com/agglayer/agglayer-dev-ui)**, run from the dev-ui repository against the haproxy origin

### Use Cases

- Testing L2-to-L2 bridging scenarios (cross-rollup asset transfers)
- Validating bridge UI functionality against multiple chains
- Developing L2-to-L2 settlement features in AggKit and AggLayer
- Automated claim processing across multiple rollups

### Prerequisites

The package default AggKit image, `ghcr.io/agglayer/aggkit:0.11.1`, contains both the `aggkit` and `aggkit-proxy` binaries; no local build is needed (see [Image Version](#image-version)).

## Deployment

### Step 1: The Parameter Files

The 2-L2 setup uses **two consecutive `kurtosis run` calls** into the same enclave, with the two files shipped in the repository root:

| File | Deploys |
|------|---------|
| `params-aggkit-l2l2-run1.yml` | L1, the Agglayer and rollup 1 (`aggkit-001`). `agglayer_extra_rollups` registers rollup 2 in the Agglayer config, because the second run reuses the Agglayer instead of redeploying it. |
| `params-aggkit-l2l2-run2.yml` | Rollup 2 (`deployment_suffix: "-002"`, `l2_network_id: 2`, `aggkit-002`), `aggkit-proxy-001` and the haproxy (`bridge_ui` with `bridge_ui_backend: aggkit`). |

The keys that matter, all documented in the comments of the files:

- `aggkit_components: "aggsender,aggoracle,bridge"` makes each aggkit instance serve the bridge REST API itself. Without `bridge` in the list a dedicated `aggkit-00X-bridge` service is deployed instead.
- `consensus_contract_type: ecdsa-multisig` with `use_agg_sender_validator: true`: aggsender queries an on-chain multisig validator committee, which the pessimistic contracts do not expose, so L2→L1 exits would never settle otherwise.
- `aggkit_proxy_bridge_urls` and `aggkit_proxy_rpc_urls` map every network id (including `0` for L1) to its bridge REST and RPC URL. They are set in the second run because both aggkit instances must exist.
- `bridge_ui_l2_rpc_urls` defines the haproxy routes `/l2rpc-001` and `/l2rpc-002`; `aggkit_proxy_url` points the `/aggkitapi` route at the proxy.
- The second run must not override `l2_admin_address`, `l2_sequencer_address` or any other `l2_*` role key: the first run granted those roles on the L1 RollupManager and derived the CREATE2 genesis addresses from them.

### Step 2: Bring Up the Enclave

```bash
cd /path/to/kurtosis-cdk

# Always start fresh -- the second run's contract deployment is not idempotent
kurtosis enclave rm -f cdk

# Run 1: L1, Agglayer and L2-1
kurtosis run --enclave cdk --args-file params-aggkit-l2l2-run1.yml .

# Run 2: L2-2, the proxy and the haproxy (into the same enclave)
kurtosis run --enclave cdk --args-file params-aggkit-l2l2-run2.yml .
```

### Step 3: Verify the Enclave

```bash
kurtosis enclave inspect cdk
```

All services should be `RUNNING`:

- L1 services (`el-1-geth-lighthouse`, `cl-1-lighthouse-geth`, `vc-1-...`)
- Agglayer (`agglayer`)
- L2-1 services (`op-el-1-op-reth-op-node-001`, `op-cl-...-001`, `op-batcher-001`, `proxyd-001`)
- L2-2 services (`op-el-1-op-reth-op-node-002`, `op-cl-...-002`, `op-batcher-002`, `proxyd-002`)
- AggKit services (`aggkit-001`, `aggkit-002`), each also serving the bridge REST API
- AggKit proxy (`aggkit-proxy-001`)
- Bridge UI proxy (`agglayer-dev-ui-proxy-002`)
- Database services (`postgres-001`, `postgres-002`) and contract deployment services (`contracts-001`, `contracts-002`)

### Step 4: Configure the Bridge UI

Use the dev-ui devnet setup script to populate the UI's configuration:

```bash
cd /path/to/agglayer-dev-ui

# Discover ports and write config.json + .env.local
node scripts/kurtosisDevnetEnv.mjs --enclave cdk
```

The script discovers the L2 suffixes (001, 002) of the enclave, resolves the haproxy service and every RPC URL, writes `config.json` with the chains `DEVNET_L1`, `DEVNET_L2_001` and `DEVNET_L2_002`, and writes `.env.local` with `NEXT_PUBLIC_AGGKIT_PROXY` pointing at the haproxy `/aggkitapi` route.

### Step 5: Run the Bridge UI

```bash
cd /path/to/agglayer-dev-ui

# Uses config.json and .env.local from step 4
pnpm run dev

# Open http://localhost:3000 in your browser
```

The bridge form supports every route (L1→L2-1, L1→L2-2, L2-1→L1, L2-1→L2-2, L2-2→L1, L2-2→L2-1) and the activity list shows bridge and claim transactions across all chains.

## Configuration Details

### AggKit Proxy Configuration

The proxy multiplexes all three networks via the `network_id` query parameter:

- `/bridge/v1/bridges?network_id=0` → L1 origin/destination routes (any aggkit instance, they all sync the same L1 state)
- `/bridge/v1/bridges?network_id=1` → L2-1 routes (`aggkit-001`)
- `/bridge/v1/bridges?network_id=2` → L2-2 routes (`aggkit-002`)

Its inputs are `aggkit_proxy_bridge_urls` (network id → `aggkit-00X:5577`) and `aggkit_proxy_rpc_urls` (network id → RPC URL, used for proof validation).

### Bridge Tracker Configuration

`aggkit-proxy-001` also serves `/tracker/v1`: per-bridge-transaction status and step-by-step progress, read from the Agglayer gRPC endpoint. The template is `static_files/additional_services/aggkit-proxy/config.toml`; the `[Tracker]` section keeps the binary defaults except for these settings:

```toml
[Tracker]
RetentionPeriod = "30m"
L1GlobalExitRootAddress = "{{.l1_global_exit_root_address}}"

[Tracker.AgglayerClient.GRPC]
URL = "{{.agglayer_grpc_url}}"
```

- `L1GlobalExitRootAddress` has no on-chain discovery fallback, unlike `BridgeAddrs`. Left at the zero address, the proxy fails at startup with a validation error. The package passes the real address from `contract_setup_addresses["l1_ger_address"]`; keep the field when you fork this config.
- `RetentionPeriod = "30m"` is longer than the 10m default so that a slow L2→L1 certificate stays queryable. Once a tracked bridge is evicted, the next poll re-registers it (status `registered`, `all_steps: null`); see the [AggLayer SDK](https://github.com/agglayer/sdk) `getBridgeTracking` documentation for how a client handles this.
- `[REST] MaxRequestsPerIPAndSecond = 0`: the field is not enforced in-process. Apply rate limiting in haproxy or at the infrastructure level.

Through haproxy the tracker is reachable at `/aggkitapi/tracker/v1/...` (haproxy strips the `/aggkitapi` prefix). To smoke-test it once the enclave is up:

```bash
# `kurtosis port print` prints the full URL (e.g. http://127.0.0.1:33015)
HAPROXY_URL=$(kurtosis port print cdk agglayer-dev-ui-proxy-002 http)

curl -s "${HAPROXY_URL}/aggkitapi/tracker/v1/health"

# Registers the transaction on the first call, then reports its progress
curl -s "${HAPROXY_URL}/aggkitapi/tracker/v1/network/1/tx/0x<bridgeTxHash>"
```

The tx-tracking response carries `tracking_status` (`registered`, `running`, `finished` or `error`), `bridge_type` and, once populated, `all_steps` with a `step_name`/`status` per step.

### HAProxy Route Map

The browser only talks to haproxy (`agglayer-dev-ui-proxy-002`), which adds the CORS headers, answers preflight requests, and routes by path:

| Path | Backend | Network(s) |
|------|---------|-----------|
| `/l1rpc` | L1 EL RPC (`el-1-geth-lighthouse:8545`) | L1 |
| `/l2rpc-001` | L2-1 RPC (`op-el-1-op-reth-op-node-001:8545`) | L2-1 |
| `/l2rpc-002` | L2-2 RPC (`op-el-1-op-reth-op-node-002:8545`) | L2-2 |
| `/l2rpc` | alias of the `-001` L2 route | L2-1 |
| `/aggkitapi` | AggKit proxy (`aggkit-proxy-001:8080`) | all, selected with `?network_id=` |
| `/aggkitapi/tracker/v1/...` | AggKit proxy tracker component | all, selected by the network id in the path |

The dev-ui config written by `kurtosisDevnetEnv.mjs` uses a single `aggkitProxy` URL for every network:

```json
{
  "appModes": {
    "configs": {
      "devnet": {
        "aggkitProxy": "http://127.0.0.1:<haproxyPort>/aggkitapi",
        "chainKeys": ["DEVNET_L1", "DEVNET_L2_001", "DEVNET_L2_002"],
        "defaultFromChainKey": "DEVNET_L1",
        "defaultToChainKey": "DEVNET_L2_001"
      }
    }
  }
}
```

## Important Notes

### Image Version

Both params files use the package default image, `ghcr.io/agglayer/aggkit:0.11.1`. It bundles the `aggkit` and `aggkit-proxy` binaries; the proxy service overrides the image entrypoint to run `aggkit-proxy` (see `src/additional_services/aggkit_proxy.star`). To check both:

```bash
docker run --rm ghcr.io/agglayer/aggkit:0.11.1 version
docker run --rm --entrypoint /usr/local/bin/aggkit-proxy \
  ghcr.io/agglayer/aggkit:0.11.1 version
```

### Non-Idempotency Warning

The second run's contract deployment (`deploy_agglayer_core_contracts`) fails with "This script has already been executed" if it is run again into the same enclave. Always remove the enclave first and run both params files from scratch:

```bash
kurtosis enclave rm -f cdk
```

### Certificate Cadence

AggKit's aggsender logs `MinimumNewCertificateInterval: 5m0s` (aggkit's default). Despite the name this is neither a minimum spacing between certificates nor a rate limit: it is a maximum-idle heartbeat. It schedules an extra trigger 5 minutes after the last event and skips it if any other trigger was programmed in the meantime. With `trigger_cert_mode: "ASAP"`, the default, a new certificate is attempted as soon as the previous one reaches a final state (settled or in error), subject to `DelayBetweenCertificates`. A deposit therefore does not wait for a certificate window, and the timeouts of the dev-ui end-to-end suite (`E2E_L2_TO_L2_CLAIM_TIMEOUT_MS`) do not need to be sized off the 5-minute heartbeat.

### Shared Wallet State

The E2E wallet's balance and the enclave's transaction and certificate history accumulate across test runs on the same enclave. A spec that needs absolute balance assertions or a bounded activity list has to account for this.

## E2E Testing

The dev-ui end-to-end suite supports this 2-L2 setup:

```bash
cd /path/to/agglayer-dev-ui

# Set by kurtosisDevnetEnv.mjs, or manually:
export E2E_BACKEND_MODE=devnet
export E2E_TO_CHAIN_ID=20202        # L2-2 destination chain id
export E2E_L2_CHAIN_IDS=20201,20202 # Both L2 chain ids
export E2E_PRIVATE_KEY=<funded-devnet-key>

pnpm run test:e2e
```

The suite includes `manual-claim.spec.ts` (L2-1→L1, manual claim only, funds its own top-up) and the smoke, token selector, ERC20, native bridge and partial-failure specs. All specs are skipped unless `E2E_BACKEND_MODE=devnet`.

## Troubleshooting

### "Failed to connect to aggkit" or "bridge service unreachable"

1. Verify `kurtosis enclave inspect cdk` shows all services `RUNNING`.
2. Check the proxy port: `kurtosis port print cdk agglayer-dev-ui-proxy-002 http`.
3. Verify that the `config.json` URL points at that port.
4. Check the haproxy logs: `kurtosis service logs cdk agglayer-dev-ui-proxy-002`.

### "Network with id N is not configured"

`scripts/kurtosisDevnetEnv.mjs` discovers the L2 suffixes automatically. If it finds only `001`, check that both runs completed and that `kurtosis enclave inspect cdk` shows `aggkit-002` as `RUNNING`.

### Enclave State Issues

If the enclave gets into an inconsistent state, remove it and run both params files again:

```bash
kurtosis enclave rm -f cdk
```

### After an enclave reset: recovering your wallet and UI

A fresh bring-up resets every chain to genesis, but browser wallets (MetaMask and similar) cache per-account, per-network nonces and balances. The first transaction sent after a reset uses the stale, too-high cached nonce and hangs or fails.

| Symptom | Cause |
|---------|-------|
| Transaction stuck "pending" forever | The wallet sent it with a nonce higher than the reset chain expects |
| Wallet shows "nonce too high" | The wallet's cached nonce no longer matches the chain |
| Wrong balances after the reset | The wallet shows the cached balance from before |

- **MetaMask**: Settings → Advanced → **Clear activity tab data** resets the per-account, per-network nonce cache without removing the account.
- **Other injected wallets**: look for an equivalent "reset activity" action or re-import the account.

Then re-sync the UI:

1. Run `node scripts/kurtosisDevnetEnv.mjs --enclave cdk` again from the dev-ui repository. Service ports are chosen per enclave instance and change on every bring-up.
2. Restart `pnpm dev` so it picks up the rewritten `.env.local` and `config.json`.
3. Hard-reload the browser tab. Chain ids are deterministic across enclave recreations, so the wallet's network entries stay valid; only the RPC URL ports move.

### Tracker troubleshooting

See [Bridge Tracker Configuration](#bridge-tracker-configuration) for the config reference.

1. **A row shows no progress bar.** One of three causes:
   - the tracker has not resolved the bridge's route yet (`all_steps: null`, `tracking_status: registered`), which resolves shortly;
   - the bridge was evicted from the retention window and re-registered, with the same signature as a fresh registration;
   - the tracker gave up resolving the transaction (`tracking_status: error` with `bridge_status: null`); the UI shows a "Tracking unavailable" alert.

   Diagnose with:
   ```bash
   HAPROXY_URL=$(kurtosis port print cdk agglayer-dev-ui-proxy-002 http)
   curl -s "${HAPROXY_URL}/aggkitapi/tracker/v1/network/<id>/tx/<hash>"
   ```
   and read `tracking_status`, `bridge_status` and `error`.
2. **A step is stalled.** Check the component that step depends on:
   - `WaitingGERUpdate` / `WaitingLERUpdate`: the L1 GlobalExitRoot contract and the proxy's `L1GlobalExitRootAddress`;
   - `PendingInclusion` / `CertificatePending`: the aggsender and Agglayer certificate pipeline (see [Certificate Cadence](#certificate-cadence));
   - `WaitingGERInjection`: the destination chain's aggoracle.

   Also check `tracker/v1/health` and the proxy logs (`kurtosis service logs cdk aggkit-proxy-001`).

## References

- [AggKit GitHub](https://github.com/agglayer/aggkit)
- [Agglayer Dev UI GitHub](https://github.com/agglayer/agglayer-dev-ui)
- [AggLayer SDK](https://github.com/agglayer/sdk): TypeScript client for bridge operations
- [Bridge Configuration Guide](../configuration/examples/bridge-ui.md)
- [Anvil Devnet Snapshot](./anvil-devnet-snapshot.md): the same topology on anvil chains, as a docker-compose bundle
