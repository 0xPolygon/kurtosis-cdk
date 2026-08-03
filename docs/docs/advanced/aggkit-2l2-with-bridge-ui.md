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
- **AggKit bridge services** (one per L2, syncing the shared L1 bridge state):
  - `aggkit-001-bridge:5577` (REST)
  - `aggkit-002-bridge:5577` (REST)
- **AggKit proxy** (`aggkit-proxy-001:8080`) — multiplexes all three networks (L1 + both L2s) via query parameter routing
- **HAProxy** (`agglayer-dev-ui-proxy-002`) — handles CORS and routes the UI's API calls:
  - `/l1rpc` → L1 EL RPC
  - `/l2rpc` → L2-1 RPC (chain-1-only back-compat alias)
  - `/l2rpc-001` → L2-1 RPC
  - `/l2rpc-002` → L2-2 RPC
  - `/aggkitapi` → AggKit proxy (all networks, selected via `?network_id=`)
- **Automated claim routing** (autoclaim) on both L2s, with configurable destinations
- **UI and supporting services**:
  - [Agglayer Dev UI](https://github.com/agglayer/agglayer-dev-ui) for browser-based bridging

### Use Cases

- Testing L2-to-L2 bridging scenarios (cross-rollup asset transfers)
- Validating bridge UI functionality against multiple chains
- Developing L2-to-L2 settlement features in AggKit and AggLayer
- Automated claim processing across multiple rollups

### Prerequisites

This setup requires the **develop branch** of the AggKit image or later, which includes both `aggkit` and `aggkit-proxy` binaries. See the "Image version" section below.

## Deployment

### Step 1: Create the Parameter Files

The 2-L2 setup uses **two consecutive runs** into the same enclave (idempotent L1/agglayer deploy in run1, then L2-2 creation in run2).

**Run 1 params file (`params-aggkit-l2l2-run1.yml`):**

```yaml
args:
  sequencer_type: op-reth
  consensus_contract_type: ecdsa-multisig

  # AggKit components: aggsender and aggoracle on the main service, plus autoclaim
  aggkit_components: "aggsender,aggoracle,autoclaim"
  # Enable autoclaim on L2-1 (network_id = 1)
  aggkit_autoclaim_destinations: [1]
  # Static bridge service URLs for autoclaim discovery
  aggkit_autoclaim_bridge_urls:
    - network_id: 1
      bridge_url: "http://aggkit-001-bridge:5577"
    - network_id: 2
      bridge_url: "http://aggkit-002-bridge:5577"

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

  # Create a second rollup (L2-2)
  deployment_suffix: "-002"
  l2_chain_id: 20202
  network_id: 2

  # Rollup-2's aggkit instance: same autoclaim config as rollup-1
  aggkit_components: "aggsender,aggoracle,autoclaim"
  aggkit_autoclaim_destinations: [2]    # Claim on L2-2 (its own destination)
  aggkit_autoclaim_bridge_urls:
    - network_id: 1
      bridge_url: "http://aggkit-001-bridge:5577"
    - network_id: 2
      bridge_url: "http://aggkit-002-bridge:5577"

  # AggKit proxy (fronts all networks for the bridge UI)
  additional_services:
    - aggkit_proxy

  # Static maps for the proxy: network_id → bridge REST URL and RPC URL
  aggkit_proxy_bridge_urls:
    - network_id: 0
      bridge_url: "http://aggkit-001-bridge:5577"  # L1 side is synced via any bridge instance
    - network_id: 1
      bridge_url: "http://aggkit-001-bridge:5577"
    - network_id: 2
      bridge_url: "http://aggkit-002-bridge:5577"

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

All 28 services should be `RUNNING`:
- L1 services (el-1-geth-lighthouse, cl-1-lighthouse-geth, vc-1-...)
- Agglayer (agglayer)
- L2-1 services (op-el-1-op-reth-op-node-001, op-cl-...-001, op-batcher-001, proxyd-001)
- L2-2 services (op-el-1-op-reth-op-node-002, op-cl-...-002, op-batcher-002, proxyd-002)
- AggKit services (aggkit-001, aggkit-001-bridge, aggkit-002, aggkit-002-bridge)
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
- `/bridge/v1/bridges?network_id=0` → L1 origin/destination routes (routed to any bridge instance; all sync the same L1 state)
- `/bridge/v1/bridges?network_id=1` → L2-1 origin/destination routes (routed to aggkit-001-bridge)
- `/bridge/v1/bridges?network_id=2` → L2-2 origin/destination routes (routed to aggkit-002-bridge)

**Proxy configuration args:**
- `aggkit_proxy_bridge_urls` — Static map of network_id → `aggkit-00X-bridge:5577` URL
- `aggkit_proxy_rpc_urls` — Static map of network_id → L2 RPC URL (used for proof validation)

Both maps are supplied at run2 time (they require both bridge services to already exist).

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

The params files currently pin a **locally-built patched image** `aggkit:fix-autoclaim-l2tolx-local` pending upstream PR [#1761](https://github.com/agglayer/aggkit/pull/1761).

Once PR #1761 is merged and released, update both params files to use the released develop image (e.g., `ghcr.io/agglayer/aggkit:develop_<date>_<sha>`).

### Non-Idempotency Warning

The run2 contract-deployment script (`deploy_agglayer_core_contracts`) is **not idempotent** — it fails with "This script has already been executed" if run again into the same enclave.

**Always start fresh before running the sequence:**
```bash
kurtosis enclave rm -f cdk
# Then run both params files fresh
```

### Certificate Cadence and E2E Timeouts

AggKit's aggsender enforces `MinimumNewCertificateInterval: 5m0s` between certificate send attempts. A deposit submitted just after a certificate window closes can wait up to 5 minutes for the next window.

The dev-ui E2E suite's `l2-to-l2.spec.ts` has a `E2E_L2_TO_L2_CLAIM_TIMEOUT_MS: 300000` (5 minutes, **identical to the certificate interval**), leaving **zero margin** against unlucky timing. If this timeout triggers in CI, budget 7-8 minutes instead, or keep L1 block production fast enough to stay ahead of L2 block height for the test duration.

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
- `kurtosis enclave inspect cdk` shows `aggkit-002` and `aggkit-002-bridge` as `RUNNING`

### Enclave State Issues

If the enclave gets into an inconsistent state:
```bash
kurtosis enclave rm -f cdk    # Clean teardown
# Then re-run both params files from scratch
```

## References

- [AggKit GitHub](https://github.com/agglayer/aggkit)
- [Agglayer Dev UI GitHub](https://github.com/agglayer/agglayer-dev-ui)
- [AggLayer SDK](https://github.com/agglayer/sdk) — TypeScript client for bridge operations
- [Bridge Configuration Guide](../configuration/examples/bridge-ui.md)
