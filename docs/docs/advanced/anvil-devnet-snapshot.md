---
sidebar_position: 8
title: "Anvil Devnet Snapshot"
description: "Fast-boot, self-contained anvil + aggkit + agglayer devnet bundle, consumable by dev-ui, aggkit, and agglayer CI without a Kurtosis toolchain"
---

# Anvil Devnet Snapshot

A second [snapshot](./snapshot.md) flavor (`--flavor anvil-aggkit`) that captures a 2-rollup **anvil** enclave (L1, two L2s, agglayer, aggkit ×2 each also serving the bridge REST API in-process, an aggkit-proxy and the [Agglayer Dev UI](https://github.com/agglayer/agglayer-dev-ui)) into a self-contained, **9-service** `docker-compose.yml` + `summary.json` bundle. A second `docker-compose.mounts.yml` variant trades the zero-mount contract for an image-override seam on the aggkit-side services.

It gives any consumer that needs a real bridging backend a hermetic devnet without a Kurtosis toolchain: `docker compose up -d --wait` reaches an all-healthy 3-chain devnet in well under a minute, instead of the several minutes a full op-reth/geth `kurtosis run` bring-up takes (see [AggKit 2-L2 with Bridge UI](./aggkit-2l2-with-bridge-ui.md) for that setup).

This page covers the topology, how a bundle is captured, verified and published, the bundle contract each consumer depends on, the capture-time arguments, anvil's reorg support and the restore hazards. The default (geth/lighthouse) flavor is described in [Kurtosis CDK Snapshot Tool](./snapshot.md).

## Why anvil

Anvil self-produces blocks with no beacon chain and no genesis-timestamp handling, and boots in seconds. `sequencer_type: anvil` is a chain type alongside `cdk-erigon` and `op-reth`: the sovereign bridge and GER contracts are predeployed through L2 genesis allocs, and the optimism-package is not used. `l1_engine: anvil` is a separate option that this flavor pairs with it, so every chain in the enclave supports state capture over the same `anvil_dumpState` JSON-RPC method.

The anvil image is `DEFAULT_IMAGES["anvil_image"]` in `src/package_io/constants.star` (a foundry image). It must be **v1.5.0 or newer**: agglayer's settlement task probes nonce inclusion on the L1 with `eth_getTransactionBySenderAndNonce`, which older anvil builds answer with `-32601 Method not found`. Agglayer treats that as non-recoverable and marks the certificate `InError`, so no L2→L1 exit would ever settle.

## Topology

Compose service names equal Kurtosis service names, so the snapshot scripts' config rewriting is near zero:

| Service | Role | Container port(s) |
|---|---|---|
| `anvil-001` | L1 | 8545 |
| `l2-anvil-001` | L2 rollup 1 (network_id 1, chain_id 20201) | 8545 |
| `l2-anvil-002` | L2 rollup 2 (network_id 2, chain_id 20202) | 8545 |
| `agglayer` | Settlement / certificate pipeline | 4443 (grpc), 4444 (readrpc), 4446 (admin), 9092 (prometheus) |
| `aggkit-001` / `aggkit-002` | aggsender + aggoracle + bridge per rollup (one container serves the main components and the bridge REST API) | 5576 (rpc), 5577 (rest) |
| `aggkit-proxy-001` | `--components=proxy,tracker`; multiplexes all 3 networks by `network_id` | 8080 |
| `agglayer-dev-ui-proxy-002` (haproxy) | Single CORS-enabled origin: `/l1rpc`, `/l2rpc-001`, `/l2rpc-002`, `/l2rpc` (alias), `/aggkitapi` (see the [route map](./aggkit-2l2-with-bridge-ui.md#haproxy-route-map)) | 80 |
| `agglayer-dev-ui-002` | `agglayer_dev_ui_aggkit_image`, opt-in | 80 |

The bundle keeps exactly these nine services because both anvil params files set `aggkit_components: "aggsender,aggoracle,bridge"`; without `bridge` in the list a separate `aggkit-00X-bridge` service would be deployed.

### Bring-up: the two-run params pair

Like the [2-L2 op-reth setup](./aggkit-2l2-with-bridge-ui.md), the anvil flavor uses **two consecutive `kurtosis run` calls into the same enclave**: `params-aggkit-anvil-l2l2-run1.yml` deploys the anvil L1, agglayer and rollup 1; `params-aggkit-anvil-l2l2-run2.yml` (`deploy_l1: false`, `deploy_agglayer: false`) adds rollup 2, `aggkit-proxy-001`, and, through `bridge_ui`, the haproxy proxy and the dev-ui container. `optimism_package:` must be absent from both files: `sequencer_type: anvil` rejects it at validation time.

```bash
kurtosis run --enclave=cdk --args-file=params-aggkit-anvil-l2l2-run1.yml .
kurtosis run --enclave=cdk --args-file=params-aggkit-anvil-l2l2-run2.yml .
```

The first run does not need to spell out `l1_rpc_url`, `l1_ws_url` and `l1_beacon_url`: they are derived from the deployment suffix for an anvil L1. The second run sets them explicitly because its own suffix is `-002` while the L1 it talks to is the first run's `anvil-001`.

### The two dev-ui image constants

`src/package_io/constants.star` carries two separate dev-ui images:

| Key | Consumer | Mount contract |
|---|---|---|
| `agglayer_dev_ui_image` | `bridge_ui_backend: bridge_hub` mode | mounts a rendered `config.ts`, Next dev server style container |
| `agglayer_dev_ui_aggkit_image` | `bridge_ui_backend: aggkit` mode, opt-in via `aggkit_deploy_dev_ui` | GHCR release image with an `nginx:alpine` runtime, mounts a runtime-rendered `config.json` at `/etc/agglayer-dev-ui/config.json` |

`aggkit_deploy_dev_ui: true` is set by `params-aggkit-anvil-l2l2-run2.yml`; every other `bridge_ui_backend: aggkit` deployment is unaffected.

## Capturing a snapshot

Once the enclave is up and **before any bridge or settlement activity**:

```bash
./snapshot/snapshot.sh cdk --flavor anvil-aggkit
```

`./snapshot/snapshot.sh --help` lists every option, including `--skip-seed` and `--erc20-address`, which only apply to this flavor. The pipeline:

1. **Seed** (`seed-devui-fixtures.sh`) deploys an E2E ERC20 on L1, funded to the well-known devnet wallet `0xE34aaF64b29273B7D567FCFc40544c014EEe9970`, with a containerized foundry. `--skip-seed` and `--erc20-address` bypass this; a bundle without the e2e wallet cannot pass the bridge round trip of `verify.sh`, so combine `--skip-seed` with `--skip-verify`.
2. **Discover** (`discover-containers.sh`) locates the anvil, aggkit, aggkit-proxy, haproxy and dev-ui services of the enclave. aggkit-proxy, haproxy and dev-ui are mandatory.
3. **Extract** (`extract-state.sh`) captures all three anvils **live** over `anvil_dumpState` (nothing is stopped, so there is no "resume the enclave" step) plus the configs and keystores of agglayer, aggkit ×2, aggkit-proxy, haproxy and dev-ui. It also asks agglayer whether any certificate exists and records the answer as `settlement_free`; a failed or unparsable probe fails the capture instead of counting as "none".
4. **Build** (`build-images.sh`) bakes state, config and keystores into thin derived images (`FROM` the original image, `COPY` the captured files). The dev-ui config's `rpcUrl` for each chain is rewritten to the haproxy route on the default proxy port, `http://127.0.0.1:8555` (`/l1rpc`, `/l2rpc-001`, `/l2rpc-002`), so the UI works from a browser on the host; the enclave-internal URLs of a plain `kurtosis run` are not reachable from there. If you change `DEVNET_PROXY_PORT`, the baked URLs must be changed with it.
5. **Compose + summary** (`generate-compose.sh`, `generate-summary.sh`) emit the two compose files and `summary.json`.

Unlike the default flavor, `snapshot.sh --flavor anvil-aggkit` does not run `verify.sh` itself; run the gate and the verification as separate steps, as the [publish workflow](#the-publish-workflow) does:

```bash
./snapshot/scripts/gate-snapshot-soundness.sh --expect-l2 2 snapshots/cdk-<timestamp>/state/state-metadata.json
./snapshot/verify.sh snapshots/cdk-<timestamp>/
```

`verify.sh` takes `--compose-file docker-compose.mounts.yml` to verify the mounts variant of the same bundle. It starts the stack, runs the checks and removes the stack again (`docker compose down -v`); a stack left over from an earlier run is removed first. Pass `--keep` to leave the stack running for inspection:

```bash
./snapshot/verify.sh --keep snapshots/cdk-<timestamp>/
```

The checks cover image presence, a static audit of the compose healthchecks, live container health, block progression and finality on all three chains, bridge/GER bytecode, sync-status on every network (`is_synced` and `is_active`), the tracker health endpoint, the tracker retention period, haproxy CORS preflights, the baked dev-ui config (valid, and every chain answers `eth_chainId` through its `rpcUrl`), the historical-state invariant, and a scripted L1→L2 and L2→L1 bridge round trip with both legs claimed manually.

### Host `cast` and `forge`

The snapshot scripts run `cast`/`forge` in a throwaway foundry container with `--network host` instead of using host binaries: host wrappers without host networking resolve `127.0.0.1` inside their own container, and a host `forge` can fail with a missing-GLIBC error on older base images. Do the same in your own scripts:

```bash
docker run --rm --network host --entrypoint=/usr/local/bin/cast \
  ghcr.io/foundry-rs/foundry:v1.9.0 block-number --rpc-url http://127.0.0.1:8545
```

`--network host` only reaches the host's ports on Linux.

## The bundle contract

Two compose files come out of every capture:

| File | Who it's for | Contract |
|---|---|---|
| `docker-compose.yml` | dev-ui, and anyone who wants the frozen devnet as is | Zero mounts: every image has state and config baked in |
| `docker-compose.mounts.yml` | aggkit / agglayer, to run their **own** build against the captured state | Same topology, but `agglayer`, `aggkit-00X` and `aggkit-proxy-001` run the bare upstream image plus a read-only bind mount of the emitted `config/` tree, override-able through env vars |

Both are generated by `generate-compose.sh` from the same discovery data, so they cannot drift apart in topology, ports or service names.

### `docker-compose.yml` (zero-mount variant)

`docker compose up -d --wait` blocks until every service's healthcheck passes.

**The dev-ui container is opt-in** through the compose profile `devui`, so a plain `docker compose up -d --wait` starts 8 of the 9 services. Start it explicitly with:

```bash
docker compose -f docker-compose.yml --profile devui up -d
```

haproxy does not route to the dev-ui container: capture removes the captured `default_backend` fallback (`patch_haproxy_default_backend` in `extract-state.sh`), because haproxy cannot resolve a container that does not exist on the network and would crash-loop at boot. A request to bare `/` through haproxy therefore returns 503; the dev-ui is reached directly on `${DEVUI_PORT:-8557}`.

**Published ports bind to `127.0.0.1` by default.** The anvils expose unlocked well-known accounts and agglayer an admin API, so set `BIND_ADDRESS` to expose them on another interface:

```bash
BIND_ADDRESS=0.0.0.0 docker compose -f docker-compose.yml up -d --wait
```

The port formulas live in `snapshot/scripts/lib/ports.sh`, sourced by every script that needs a port, so the compose files, `summary.json` and this table cannot drift:

| Service | Container port | Host port (env override, default) |
|---|---|---|
| `agglayer-dev-ui-proxy-002` (haproxy) | 80 | `${DEVNET_PROXY_PORT:-8555}` (the only port dev-ui CI uses) |
| `aggkit-proxy-001` | 8080 | `${AGGKIT_PROXY_PORT:-8556}` |
| `agglayer-dev-ui-002` | 80 | `${DEVUI_PORT:-8557}` |
| `anvil-001` (L1) | 8545 | `${L1_RPC_PORT:-8545}` |
| `l2-anvil-001` | 8545 | `${L2_001_HTTP_PORT:-11545}` |
| `l2-anvil-002` | 8545 | `${L2_002_HTTP_PORT:-12545}` |
| `aggkit-001` / `aggkit-002` | 5576 (rpc), 5577 (bridge rest) | `${L2_00X_AGGKIT_RPC_PORT:-11576/12576}` / `${L2_00X_AGGKIT_REST_PORT:-11577/12577}` |
| `agglayer` | 4443 / 4444 / 4446 / 9092 | same (debug only) |

### `docker-compose.mounts.yml` (mounts variant)

Same 9-service topology and port table, but three groups of services swap their derived image for the **bare upstream image** recorded in `IMAGE_INFO.json`'s `base_image`, plus a read-only bind mount of the emitted `./config/<svc>/` tree:

| Service(s) | Override env var | Default | Healthcheck |
|---|---|---|---|
| `agglayer` | `AGGLAYER_IMAGE` | the recorded `agglayer` `base_image` (e.g. `ghcr.io/agglayer/agglayer:0.6.2`) | compose-level `bash -c 'exec 3<>/dev/tcp/127.0.0.1/4443'` probe |
| `aggkit-001` / `aggkit-002` / `aggkit-proxy-001` | `AGGKIT_IMAGE` (one variable shared by all three; the proxy binary ships in the same image) | the recorded `aggkit-proxy-001` `base_image` (e.g. `ghcr.io/agglayer/aggkit:0.11.1`) | none |

- The override default is the bare upstream image, not the derived image with the mount shadowing its bake, so "override the image" swaps like for like.
- `aggkit-00X` and `aggkit-proxy-001` have no healthcheck because aggkit's images are distroless (there is no `sh`). Their dependents use `condition: service_started`.
- `agglayer` gets the TCP probe because the bare agglayer image has `bash`, and because `aggkit-00X` depends on it with `condition: service_healthy`: if aggsender's first claim-syncer call reaches agglayer before its gRPC listener is bound, the claim syncer's local state moves past block 0 in the meantime and aggsender stays stuck at `starting_claim_syncer_stage`.
- An `AGGLAYER_IMAGE` without `/bin/bash` therefore stays `unhealthy` and `aggkit-00X` never starts. This fails loudly; replace the healthcheck if you need a shell-less image.

The anvil family (L1 and every L2) is not override-able in either file: swapping it would lose the captured chain state. haproxy and the dev-ui keep their derived images and only bind-mount their own config file over the baked copy.

### `summary.json`

Machine-readable description of the bundle:

| Field | Contents |
|---|---|
| `flavor` | `"anvil-aggkit"` |
| `settlement_free` | Must be `true` to publish, see [Restore constraints](#restore-constraints-and-hazards) |
| `agglayer_certificates_at_capture` | Per-network certificate height/status at capture time |
| `erc20_address` | The seeded fixture ERC20, **nonce-dependent, changes on every capture** |
| `chain_ids` / `network_ids` | `{l1, l2_001, l2_002}` |
| `proxy` | haproxy service, host port, `routes[]` (path/url/kind/upstream/chain_id/network_id) |
| `aggkit_proxy` | REST/bridge/tracker/sync-status URLs, both internal and via the proxy |
| `agglayer` | grpc/read_rpc/admin/metrics URLs |
| `dev_ui` | service, image reference, URL, `config_path` |
| `networks.l1` / `networks.l2["001"\|"002"]` | per-chain RPC URLs, contract addresses, `block_number_at_capture` |
| `accounts` | `e2e_wallet`, `funded[]`, `operational[]` (proof/certificate signers), `keystores[]` (paths), `mnemonics` |
| `fixtures` | the seeded ERC20's deploy details |
| `images` | `tag`, `image_prefix`, `busybox_image`, per-service `{name, base_image, size}` under `images.services`; after publishing also `{tag, digest}` |
| `compose` | `bind_mounts: 0`, `volumes: 0`, `host_ports` keyed by service |

Every value in `summary.json`, private keys included, is a well-known public Kurtosis/Foundry devnet fixture.

## The publish workflow

`.github/workflows/snapshot-devui.yml` runs the pipeline (in `snapshot-devui-pipeline.yml`) in CI: `kurtosis-pre-run`, the two `kurtosis run` calls, `snapshot.sh --flavor anvil-aggkit`, the soundness gate with `--expect-l2 2`, `verify.sh`, and then, when publishing, the image push, the digest pinning and the artifact upload.

| Trigger | What runs |
|---|---|
| `pull_request` touching the bundle's inputs (`main.star`, `src/**`, `static_files/**`, `snapshot/**`, the anvil params files, the Kurtosis actions) | capture, gate and verify; the publish commands are only rehearsed with `publish-images.sh --dry-run`, nothing is pushed |
| `push` to `main` (same paths) | the same, then publish |
| `workflow_dispatch` | validation, and with `publish: true` also publishing; a dispatch with `publish: true` from any ref other than `main` fails |

Only the publishing job holds `packages: write`. Validation and publishing use separate concurrency groups; publishes are never cancelled once started.

```bash
gh workflow run snapshot-devui.yml --repo 0xPolygon/kurtosis-cdk --ref main -f publish=true
```

### Images and tags

Images publish under `ghcr.io/0xpolygon/kurtosis-cdk-snapshot-<service>` for the nine services listed in the [topology](#topology). Each carries:

- the moving alias `snapshot-latest-devui`, moved only after every service has been pushed;
- one immutable tag, `<component-version>-<UTC yyyymmddHHMMSS>-<sha7>-r<run>.<attempt>` (for example `0.11.1-20261110093015-1a2b3c4-r1234567.1`; local runs use `<sha7>-l<6 hex>` as the source id). The component version comes from the upstream image that produced the baked image; `publish-images.sh` refuses to push a tag that already exists in the registry.

The authoritative pin is the `@sha256:<digest>` reference that `apply-digests.sh` writes into `docker-compose.yml` and `docker-compose.mounts.yml` (the readable tag is kept as a trailing comment) and into `summary.json`'s `images.services.<svc>.{tag,digest}`. The workflow passes `--smoke-test`, which pulls the pinned images and runs `docker compose up -d --wait` on the result. `publish-images.sh` writes `PUBLISHED_TAGS.json` (`repo`, `tag`, `digest`, `aliases` per service) only when everything succeeded.

The uploaded workflow artifact `devui-snapshot-<tag>` contains `docker-compose.yml`, `docker-compose.mounts.yml`, `summary.json` and the `config/` tree the mounts variant bind-mounts.

### Package visibility

dev-ui CI pulls the images without credentials, so the packages must be public. New packages in the organization have come out public; if a policy change makes a new package private, change it once per package (`https://github.com/orgs/0xPolygon/packages` → `kurtosis-cdk-snapshot-<service>` → Package settings → Change visibility), or with a token that has the `write:packages` scope:

```bash
gh api -X PATCH /orgs/0xPolygon/packages/container/kurtosis-cdk-snapshot-<service> -f visibility=public
```

Verify anonymously afterwards:

```bash
docker logout ghcr.io
docker pull ghcr.io/0xpolygon/kurtosis-cdk-snapshot-anvil-001:snapshot-latest-devui
```

## Consuming this bundle

### As dev-ui: zero-mount, no build required

Pull `docker-compose.yml` and `summary.json` (the workflow artifact, or the published GHCR images) and run the file as is:

```bash
docker compose -f docker-compose.yml up -d --wait
```

Everything is baked into the images. Talk to the devnet through `agglayer-dev-ui-proxy-002` on `${DEVNET_PROXY_PORT:-8555}` and tear it down with `docker compose down -v`.

### As aggkit: mounts variant and `AGGKIT_IMAGE`

To run **your own** aggkit build against the captured two-rollup, agglayer-backed state, use the mounts variant and override `AGGKIT_IMAGE`:

```bash
AGGKIT_IMAGE=ghcr.io/agglayer/aggkit:0.11.1 \
  docker compose -f docker-compose.mounts.yml up -d --wait
```

`aggkit-001`, `aggkit-002` and `aggkit-proxy-001` start from the mounted `./config/<svc>/` tree. Point `AGGKIT_IMAGE` at a local build the same way.

### As agglayer: `AGGLAYER_IMAGE`

`AGGLAYER_IMAGE` on `docker-compose.mounts.yml` lets an agglayer build under test run against the same captured state. The image must carry `/bin/bash` (see the healthcheck above).

## Capture-time arguments

These are Kurtosis input arguments (`args:` in a params file passed to `kurtosis run --args-file=...`) that shape what is captured, not env vars of the compose files.

| Argument | Default | Effect |
|---|---|---|
| `aggkit_image` | `ghcr.io/agglayer/aggkit:0.11.1` | Upstream aggkit build the enclave runs and the mounts variant defaults to |
| `agglayer_image` | `ghcr.io/agglayer/agglayer:0.6.2` | Same for agglayer |
| `aggkit_components` | `aggsender,aggoracle` (the anvil params files set `aggsender,aggoracle,bridge`) | aggkit sub-processes per container; `bridge` makes the container serve the bridge REST API |
| `trigger_cert_mode` | `ASAP` | `EpochBased`, `NewBridge`, `ASAP` or `Auto`. `ASAP` sends a new certificate as soon as the previous one is final. `Auto` is not a fourth mode: for the pessimistic-proof aggsender it resolves to `EpochBased`, which is driven by agglayer's `[epoch.block-clock]` |
| `agglayer_settle_confirmations` | `1` | L1 confirmations agglayer waits for; must be `>= 1` |
| `agglayer_settlement_policy` | `safe` | `latest`, `safe` or `finalized`; rendered into `[settlement.pessimistic-proof-tx-config]` as `LatestBlock`, `SafeBlock` or `FinalizedBlock` (agglayer reads the PascalCase variant names) |
| `l1_anvil_block_time` / `l1_anvil_slots_in_epoch` | `1` / `1` | Seconds per L1 block and L1 blocks per epoch |
| `l2_anvil_block_time` / `l2_anvil_slots_in_epoch` | `1` / `1` | The same per L2 instance |

Invalid values of `trigger_cert_mode`, `agglayer_settle_confirmations` and `agglayer_settlement_policy` fail at validation time, before any container is created.

- Each aggkit instance's rendered config and keystores are captured from `/etc/aggkit` into `config/aggkit-00X/`; agglayer's config and signer go to `config/agglayer/`. This is the tree the mounts variant bind-mounts, so there is nothing else to configure there.
- `aggkit_proxy_bridge_urls` and `aggkit_proxy_rpc_urls` (network id → URL, one entry per network including `0` for L1) are set in the second run and captured into `config/aggkit-proxy-001/config.toml`. The tracker settings are described in [AggKit 2-L2 with Bridge UI](./aggkit-2l2-with-bridge-ui.md#bridge-tracker-configuration).
- **Block timing.** The lag of `safe` and `finalized` behind `latest` is `block_time × slots_in_epoch` seconds per step, each a further whole epoch behind (`finalized` is two epochs behind `latest`). With the defaults of 1 second and 1 slot the lag is about a second, so `agglayer_settlement_policy: "latest"` buys little; raise the two arguments to exercise `safe` or `finalized` under a realistic lag. With `sequencer_type: anvil`, `l2_anvil_block_time` and `l2_anvil_slots_in_epoch` are validated (`>= 1`); the L1 equivalents are not, and `l1_anvil_block_time: 0` makes the `anvil-001` container exit at startup (`Duration must be greater than 0`).
- **Settlement latency.** The first receipt check of agglayer's settlement task returns "not included yet", and agglayer's default 60 s `initial-interval` for `retry-on-not-included-on-l1` gates the next attempt however few confirmations are required, so an L2→L1 settlement takes about a minute on a fast anvil L1. This package has no argument for that interval, and `agglayer_settle_confirmations` does not change it.
- **`[epoch.block-clock]`** in `static_files/agglayer/config.toml` drives epoch bookkeeping only; since [agglayer#1615](https://github.com/agglayer/agglayer/pull/1615) per-epoch certificate rate limiting no longer exists, so with `trigger_cert_mode: "ASAP"` it moves neither submission nor settlement timing.

## Reorg

Anvil's `anvil_reorg` JSON-RPC method works on this flavor's L1 and L2 chains, including against a restored bundle:

```
anvil_reorg(depth: number, txBlockPairs: [ [TransactionRequest, blockIndex], ... ])
```

- `depth`: how many blocks back from the current head to replace.
- `txBlockPairs`: `[]` for an empty reorg, or `[transactionRequestObject, blockIndex]` pairs to inject transactions. `blockIndex` is 0-based, counted from the first replaced block (`head - depth + 1`), not from the head.
- A successful call answers `{"jsonrpc":"2.0","id":1,"result":null}`.

```bash
# L1 (anvil-001)
curl -s -X POST http://127.0.0.1:8545 -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"anvil_reorg","params":[N,[]]}'

# L2 (l2-anvil-001 / l2-anvil-002)
curl -s -X POST http://127.0.0.1:11545 -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"anvil_reorg","params":[N,[]]}'
```

An empty-array reorg of an already-empty tip can legitimately produce a byte-identical block, so verify a reorg with an injected transaction or a block-hash diff at the **head**, never at `head - depth`.

For a reorg whose fork point stays above the chain's own bridge-contract deployment block, aggkit's syncers detect it and recover within the same poll cycle (`reorg detected at block N`, `reorged to block N, 0 rows deleted`) without any operator action.

### The ceiling: the bridge-contract deployment block

Reorging **at or below** a chain's bridge-contract deployment block erases the deployment transaction from the canonical chain. Nothing redeploys a missing contract, so `eth_getCode` at the bridge address returns `0x` permanently, the bridge REST API starts returning 500s (`no contract code at given address`), and every bridge-dependent container goes `unhealthy` and stays so.

The deployment block differs per capture, so stay several blocks clear of it. To find it for a bundle, bisect `eth_getCode` at the bridge address from `summary.json`'s `networks` section.

## Restore constraints and hazards

The default flavor's constraint carries over: **the source enclave must not have settled anything through agglayer before capture**. Agglayer's and aggkit's internal databases are never part of the snapshot, so restoring chain state that already reflects settlement activity is unsound (see [Agglayer Settlement Constraint](./snapshot.md#agglayer-settlement-constraint)). Capture must run immediately after enclave readiness, before any bridge transaction.

### Historical states

`anvil --load-state` on a plain dump restores blocks, transactions, receipts and logs for the whole history but only **one state, the tip**: `eth_getLogs` and `eth_getBlockByNumber` work at any height, while `eth_call` and `eth_getCode` work only at the snapshot block and later. Components that pin a state read to an earlier block (aggkit's initial local-exit-root read at `rollupCreationBlockNumber`, agglayer's settlement-signer nonce probe) would fail with `BlockOutOfRangeError`.

`extract-state.sh` therefore captures with `anvil_dumpState`'s `preserve_historical_states` option. Two machine-checkable invariants are enforced by `gate-snapshot-soundness.sh` before anything is published:

1. **`settlement_free: true`**: no certificate ever existed in the captured enclave.
2. **The expected chain set** (one L1 and `--expect-l2 N` L2s, each with a state file) **and `historical_states > 0` for every chain**. The chain set is read from the metadata; `historical_states` is recomputed from the state files.

A bundle failing either is never published. `historical_states` lives only in the capture-time `state/state-metadata.json`; `summary.json` carries `settlement_free` but not `historical_states`. The dump size is linear in block count, which is the practical reason to capture right after readiness.

### Timestamp seam on cold restore

Blocks loaded from state keep their original timestamps; blocks produced after the restore use the wall clock. The seam equals the snapshot's age at restore time. Settlement works across the seam.

### `--init` and `--dump-state` are mutually exclusive

Anvil rejects both flags at once, so capture goes through the `anvil_dumpState` **RPC** on all three chains rather than a CLI flag. The restore side (`--init` genesis plus `--load-state`) is unaffected.

## See also

- [AggKit 2-L2 with Bridge UI](./aggkit-2l2-with-bridge-ui.md): the live-enclave, op-reth/geth equivalent of this topology.
- [Kurtosis CDK Snapshot Tool](./snapshot.md): the default flavor; its settlement-freedom prerequisite and troubleshooting guidance apply here too.
