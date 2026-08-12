---
sidebar_position: 8
title: "Anvil-Flavor DevUI Snapshot"
description: "Fast-boot, self-contained anvil + aggkit + dev-ui devnet, captured as a docker-compose bundle for hermetic CI"
---

# Anvil-Flavor DevUI Snapshot

A second [snapshot](./snapshot.md) flavor (`--flavor anvil-aggkit`) that captures a
2-rollup **anvil** enclave — L1, two L2s, agglayer, aggkit ×2, an aggkit-proxy and the
[Agglayer Dev UI](https://github.com/agglayer/agglayer-dev-ui) — into a self-contained
`docker-compose.yml` + `summary.json` bundle. It exists to give
[`agglayer/agglayer-dev-ui`](https://github.com/agglayer/agglayer-dev-ui)'s CI a real
bridging backend without a Kurtosis toolchain: `docker compose up -d --wait` reaches an
all-healthy 3-chain devnet in about 24 seconds, instead of the ~8 minutes a full
op-reth/geth `kurtosis run` bring-up takes (see
[AggKit 2-L2 with Bridge UI](./aggkit-2l2-with-bridge-ui.md)).

This page documents the flavor's topology, how to produce and publish a bundle, the
exact bundle contract dev-ui's CI depends on, and the restore hazards anvil's
`--load-state` semantics create — all of which differ substantially from the
default (geth/lighthouse) flavor described in [Kurtosis CDK Snapshot Tool](./snapshot.md).

## Why anvil

Anvil self-produces L2 blocks with no beacon chain, no genesis-timestamp handling, and
boots in seconds. `sequencer_type: anvil` is a third chain type (alongside `cdk-erigon`
and `op-reth`): the sovereign bridge/GER contracts are predeployed through L2 genesis
allocs (the same `create_sovereign_predeployed_genesis` pipeline the OP and CDK stacks
already use), and the optimism-package (op-node/op-reth/op-deployer) is skipped
entirely. `l1_engine: anvil` is unrelated but frequently paired with it: this flavor
uses anvil for the L1 too, so *every* chain in the enclave supports state capture over
the same `anvil_dumpState` JSON-RPC method.

### Why `anvil_image` is pinned to `v1.5.1`, not a newer/older tag

`src/package_io/constants.star`'s `anvil_image` is pinned:

```python
"anvil_image": "ghcr.io/foundry-rs/foundry:v1.5.1",
```

**Do not un-pin this to `latest` or drop it to `v1.4.x`.** agglayer's settlement task
probes nonce inclusion on the L1 with `eth_getTransactionBySenderAndNonce` after
sending a verify transaction. Anvil only gained that RPC method in `v1.5.0` (every
`v1.4.x` build answers `-32601 Method not found`). agglayer treats that response as
`assumed non-recoverable` and **panics** at
`agglayer-settlement-service/src/settlement_task.rs:543`, permanently marking the
certificate `InError` — even though the settlement transaction itself lands on L1
successfully; only the bookkeeping probe fails. Every certificate then loops forever
(aggkit logs `An InError cert exists but skipping send cert`), so **no L2→L1 exit ever
settles** on an anvil L1 older than `v1.5.0`. `v1.5.1` is the smallest bump past
`v1.5.0` that also carries `v1.5.0`'s patch fixes, chosen deliberately over `latest` to
minimize unrelated anvil drift.

## Topology

Compose service names equal Kurtosis service names, so the snapshot scripts' config
rewriting is near-zero:

| Service | Role | Container port(s) |
|---|---|---|
| `anvil-001` | L1 | 8545 |
| `l2-anvil-001` | L2 rollup 1 (network_id 1, chain_id 20201) | 8545 |
| `l2-anvil-002` | L2 rollup 2 (network_id 2, chain_id 20202) | 8545 |
| `agglayer` | Settlement / certificate pipeline | 4443 (grpc), 4444 (readrpc), 4446 (admin), 9092 (prometheus) |
| `aggkit-001` / `aggkit-002` | aggsender + aggoracle + autoclaim per rollup | 5576 (rpc) |
| `aggkit-001-bridge` / `aggkit-002-bridge` | aggkit bridge REST per rollup | 5576 (rpc), 5577 (rest) |
| `aggkit-proxy-001` | `--components=proxy,tracker`; multiplexes all 3 networks by `network_id` | 8080 |
| `agglayer-dev-ui-proxy-002` (haproxy) | Single CORS-enabled origin: `/l1rpc`, `/l2rpc-001`, `/l2rpc-002`, `/l2rpc` (alias), `/aggkitapi` | 80 |
| `agglayer-dev-ui-002` | `agglayer_dev_ui_aggkit_image`, opt-in | 80 |

### Bring-up: the two-run params pair

Like the [2-L2 op-reth setup](./aggkit-2l2-with-bridge-ui.md), the anvil flavor uses
**two consecutive `kurtosis run` calls into the same enclave**:
`params-aggkit-anvil-l2l2-run1.yml` deploys L1 (anvil) + agglayer + rollup 1; run2
(`deploy_l1: false`, `deploy_agglayer: false`) adds rollup 2, `aggkit-proxy-001`, and
(via `bridge_ui`) the haproxy proxy and dev-ui container. `optimism_package:` must be
**absent entirely** from both files — `sequencer_type: anvil` rejects one at Starlark
validation time.

```bash
kurtosis run --enclave=cdk --args-file=params-aggkit-anvil-l2l2-run1.yml .
kurtosis run --enclave=cdk --args-file=params-aggkit-anvil-l2l2-run2.yml .
```

Both files must spell out `l1_rpc_url`/`l1_ws_url`/`l1_beacon_url` pointing at
`http://anvil-001:8545` explicitly — a pre-existing bug in
`input_parser.set_l1_client_args` (unrelated to this work, tracked for a future fix)
clobbers those URLs back to the ethereum-package's reth service names whenever they
are not set explicitly for an anvil L1.

### The two dev-ui image constants

`src/package_io/constants.star` carries **two separate** dev-ui image keys — this is
deliberate, not an oversight, and not a version bump of one into the other:

| Key | Consumer | Mount contract |
|---|---|---|
| `agglayer_dev_ui_image` | `run_server()`, `bridge_ui_backend: bridge_hub` mode | mounts a rendered `config.ts`, Next-dev-server-style container |
| `agglayer_dev_ui_aggkit_image` | `run_dev_ui()`, `bridge_ui_backend: aggkit` mode, opt-in via `aggkit_deploy_dev_ui` | GHCR image, `nginx:alpine` runtime (no Node), mounts a runtime-rendered `config.json` at `/etc/agglayer-dev-ui/config.json` |

`agglayer_dev_ui_image` continues to point at the GCP-hosted bridge-hub-mode build and
is exercised by `.github/tests/additional-services.yml` (wired into `test.yml` and
`nightly.yml`); it was deliberately left unbumped so this flavor's work does not touch
bridge-hub mode at all. `agglayer_dev_ui_aggkit_image` is the published
`ghcr.io/agglayer/agglayer-dev-ui:dispatch-feat-aggkit-backend-*` tag from
`agglayer/agglayer-dev-ui`'s `feat/aggkit-backend` branch (PR #24), consumed as an
image reference only — no source build happens in kurtosis-cdk. Deploying it is opt-in:
`aggkit_deploy_dev_ui: true` (set by `params-aggkit-anvil-l2l2-run2.yml`), so every
other `bridge_ui_backend: aggkit` deployment is unaffected by default.

## Capturing a snapshot: `snapshot.sh --flavor anvil-aggkit`

Once the enclave is up and **before any bridge/settlement activity**, run:

```bash
./snapshot/snapshot.sh cdk --flavor anvil-aggkit
```

`--help` documents every flag, including the two flavor-specific ones
(`--skip-seed`, `--erc20-address`):

```
$ ./snapshot/snapshot.sh --help
Ethereum L1 Snapshot Tool

Usage:
  ./snapshot/snapshot.sh <ENCLAVE_NAME> [OPTIONS]

Arguments:
  ENCLAVE_NAME        Name of the Kurtosis enclave to snapshot

Options:
  --out <DIR>            Output directory (default: snapshots)
  --tag <TAG>            Custom tag suffix for images
  --flavor <FLAVOR>      Snapshot flavor: default | anvil-aggkit
                         (default: default -- geth/lighthouse L1)
  --skip-verify          Skip automated verification step
  --skip-seed            anvil-aggkit only: do not seed dev-ui fixtures
  --erc20-address <ADDR> anvil-aggkit only: reuse this ERC20 instead of
                         deploying a fresh one
  --keep-intermediates   Keep artifacts/, datadirs/, images/, metadata/ and
                         discovery.json instead of deleting them at the end
  -h, --help             Show this help message
```

For this flavor, `--flavor anvil-aggkit` changes every stage of the pipeline:

1. **Seed** (`snapshot/scripts/seed-devui-fixtures.sh`) deploys an E2E ERC20 on L1,
   funded to the well-known devnet wallet `0xE34aaF64b29273B7D567FCFc40544c014EEe9970`,
   via a **containerized** foundry (host `forge`/`cast` are unusable on some
   machines — see below) — `--skip-seed`/`--erc20-address` bypass this.
2. **Discover** (`discover-containers.sh`) recognizes the anvil/aggkit/proxy/haproxy/
   dev-ui service set (fixing a phantom-prefix bug where `aggkit-proxy-*` used to
   match the generic `^aggkit-` L2 pattern).
3. **Extract** (`extract-state.sh`) captures all three anvils **live**, over the
   `anvil_dumpState` RPC — nothing is ever stopped, so this flavor has no "resume the
   original enclave" step (that step is what the default flavor's stop/restart
   sequence is for; anvil's RPC-based capture makes it unnecessary). `--init` and
   `--dump-state` are mutually exclusive on anvil, which is why capture cannot reuse
   the L1 anvil's own CLI-flag `--dump-state` pattern.
4. **Build** (`build-images.sh`) bakes state/config into thin derived images (`FROM`
   the original image, `COPY` the captured state/config/keystores).
5. **Compose + summary** (`generate-compose.sh`, `generate-summary.sh`) emit a
   self-contained `docker-compose.yml` (no bind mounts, no volumes) and `summary.json`.
6. **Verify** runs automatically unless `--skip-verify` is passed.

A full end-to-end run (seed → capture → build → compose → summary → verify) took
51–80 seconds in measurement; bring-up of the source enclave (both `kurtosis run`
calls) took 224–254 seconds.

### Host `cast`/`forge` are commonly unusable for scripting this flavor

On some machines the host `cast`/`forge` binaries are Docker-wrapper scripts without
`--network host`, so `127.0.0.1:<port>` resolves *inside the wrapper's own container*,
not the host, and every call against a Kurtosis-published port fails "Connection
refused" even though `curl` against the same port works. Separately, host `forge` can
fail outright with a missing-GLIBC error on older base images. Any script (including
`seed-devui-fixtures.sh`) that talks to a live enclave over one of these tools must run
it containerized with the host network explicitly attached, e.g.:

```bash
docker run --rm --network host --entrypoint=/usr/local/bin/cast \
  ghcr.io/foundry-rs/foundry:v1.5.1 block-number --rpc-url http://127.0.0.1:8545
```

## The bundle contract

### `docker-compose.yml`

Self-contained by construction: every service's image already has its captured state,
config and keystores baked in, so the compose file needs nothing else on disk.
`docker compose up -d --wait` blocks until every service's own healthcheck passes.

Port formula lives in exactly one place, `snapshot/scripts/lib/ports.sh`, sourced by
every script that needs a port number so the compose file, `summary.json`, and this
table can never drift apart:

| Service | Container port | Host port (env override, default) |
|---|---|---|
| `agglayer-dev-ui-proxy-002` (haproxy) | 80 | `${DEVNET_PROXY_PORT:-8555}` — **the only port dev-ui CI uses** |
| `aggkit-proxy-001` | 8080 | `${AGGKIT_PROXY_PORT:-8556}` |
| `agglayer-dev-ui-002` | 80 | `${DEVUI_PORT:-8557}` |
| `anvil-001` (L1) | 8545 | `${L1_RPC_PORT:-8545}` |
| `l2-anvil-001` | 8545 | `${L2_001_HTTP_PORT:-11545}` |
| `l2-anvil-002` | 8545 | `${L2_002_HTTP_PORT:-12545}` |
| `aggkit-001` / `aggkit-002` | 5576 | `${L2_00X_AGGKIT_RPC_PORT:-11576/12576}` |
| `aggkit-001-bridge` / `aggkit-002-bridge` | 5576 / 5577 | `${L2_00X_AGGKIT_BRIDGE_RPC_PORT:-11586/12586}` / `${L2_00X_AGGKIT_REST_PORT:-11577/12577}` |
| `agglayer` | 4443/4444/4446/9092 | same (debug only) |

Every port above is env-overridable, computed from the same `snapshot_l2_port`/
`snapshot_fixed_port` helpers:

```
$ source snapshot/scripts/lib/ports.sh
$ echo "l2 http port (001): $(snapshot_l2_port 001 http)"
l2 http port (001): 11545
$ echo "devnet proxy fixed port expr: $(snapshot_fixed_port_expr devnet_proxy)"
devnet proxy fixed port expr: ${DEVNET_PROXY_PORT:-8555}
```

### `summary.json`

Machine-readable description of the bundle. Top-level fields:

| Field | Contents |
|---|---|
| `flavor` | `"anvil-aggkit"` |
| `settlement_free` | Must be `true` to publish — see [Restore constraints](#restore-constraints-and-hazards) |
| `agglayer_certificates_at_capture` | Per-network certificate height/status at capture time |
| `erc20_address` | The seeded fixture ERC20 — **nonce-dependent, changes on every capture** |
| `chain_ids` / `network_ids` | `{l1, l2_001, l2_002}` |
| `proxy` | haproxy service, host port, `routes[]` (path/url/kind/upstream/chain_id/network_id) |
| `aggkit_proxy` | REST/bridge/tracker/sync-status URLs, both internal and via-proxy |
| `agglayer` | grpc/read_rpc/admin/metrics URLs |
| `dev_ui` | service, image reference, URL, `config_path` |
| `networks.l1` / `networks.l2["001"\|"002"]` | per-chain RPC URLs, contract addresses, `block_number_at_capture` |
| `accounts` | `e2e_wallet`, `funded[]`, `operational[]` (proof/certificate signers), `keystores[]` (paths, not secrets), `mnemonics` |
| `fixtures` | the seeded ERC20's deploy details |
| `images` | `tag`, `image_prefix`, `busybox_image`, per-service `{name, base_image, size}` under `images.services` |
| `compose` | `bind_mounts: 0`, `volumes: 0`, `host_ports` keyed by service |

Every value in `summary.json` — including private keys — is a well-known,
publicly-documented Kurtosis/Foundry devnet fixture. Nothing sensitive is published by
vendoring or publishing this file.

## The publish workflow

`.github/workflows/snapshot-devui.yml` runs the whole pipeline in CI: checkout →
`kurtosis-pre-run` → the two `kurtosis run` calls → `snapshot.sh --flavor anvil-aggkit`
→ **gate** on `state-metadata.json`'s soundness invariants → `verify.sh` (the full
dev-ui contract, including a real L1→L2 and L2→L1 bridge round trip) → publish 11
images to GHCR → upload `docker-compose.yml` + `summary.json` as a workflow artifact.

```bash
$ ./snapshot/scripts/gate-snapshot-soundness.sh
Usage: ./snapshot/scripts/gate-snapshot-soundness.sh <state-metadata.json>
```

Images publish under `ghcr.io/0xpolygon/kurtosis-cdk-snapshot-<service>` with tags
`snapshot-<sha>` and `snapshot-latest-devui` — both the package name and every tag
deliberately contain the literal word `snapshot`. The 11 services:
`anvil-001`, `l2-anvil-001`, `l2-anvil-002`, `agglayer`, `aggkit-001`,
`aggkit-001-bridge`, `aggkit-002`, `aggkit-002-bridge`, `aggkit-proxy-001`,
`agglayer-dev-ui-proxy-002`, `agglayer-dev-ui-002`.

Publishing is opt-in: `workflow_dispatch`'s `publish` input **defaults to `false`**
(dry-run — `docker tag` runs for real and is side-effect-free, `docker push` is only
echoed). A push to the working branch also triggers a dry run automatically via a
path filter, so the tag/push logic is exercised on every push without ever risking an
unintended publish. Only an explicit dispatch with `publish: true` pushes images:

```bash
# Actually publishes to GHCR -- requires explicit authorization; not run by
# this doc's own verification pass. See "Commands not executed" below.
gh workflow run snapshot-devui.yml --repo 0xPolygon/kurtosis-cdk \
  --ref feat/aggkit-bridge-ui-backend -f publish=true
```

Poll the run (never `gh run watch` in automation — poll inline instead):

```bash
$ gh run list --repo 0xPolygon/kurtosis-cdk --workflow snapshot-devui.yml --limit 5 \
    --json databaseId,status,conclusion,headSha,event,createdAt
[{"conclusion":"success","createdAt":"2026-08-12T18:24:25Z","databaseId":31627467579,"event":"push", ...}]

$ gh run view 31616965584 --repo 0xPolygon/kurtosis-cdk --json conclusion,headSha,displayTitle,event
{"conclusion":"success","displayTitle":"snapshot-devui","event":"workflow_dispatch","headSha":"d5dea8709c8dd3ca3cd3f2af1cf583d4ce75f022"}
```

GHCR packages under this org came back **public by default** on their first-ever
publish — no visibility toggle was required. Verify anonymously at any time:

```bash
$ docker logout ghcr.io
Removing login credentials for ghcr.io
$ docker pull ghcr.io/0xpolygon/kurtosis-cdk-snapshot-agglayer-dev-ui-002:snapshot-latest-devui
snapshot-latest-devui: Pulling from 0xpolygon/kurtosis-cdk-snapshot-agglayer-dev-ui-002
Status: Image is up to date for ghcr.io/0xpolygon/kurtosis-cdk-snapshot-agglayer-dev-ui-002:snapshot-latest-devui
```

If a future org policy change makes a new package default private, the one-time fix
(package settings → visibility → public, or the equivalent `gh api -X PATCH
/orgs/0xPolygon/packages/container/<package>` call) is documented in full in the
workflow file's header comment.

## Restore constraints and hazards

The default flavor's constraint carries over unchanged: **the source enclave must not
have settled anything through agglayer before capture** — agglayer/aggkit internal
databases are never part of the snapshot, so restoring L1/L2 state that already
reflects settlement activity is unsound (see [Agglayer Settlement
Constraint](./snapshot.md#agglayer-settlement-constraint)). Capture must run
**immediately after enclave readiness**, before any bridge transaction.

### `anvil --load-state` only restores the tip state — the central hazard

`anvil --load-state` restores blocks, transactions, receipts and logs for the entire
captured history, but by default only **one state — the tip**. `eth_getLogs`/
`eth_getBlockByNumber` work at any height after restore; `eth_call`/`eth_getCode` only
work at the snapshot block and later. Any component that pins a state read to a
pre-snapshot block (aggkit's initial local-exit-root read at
`rollupCreationBlockNumber`; agglayer's settlement-signer nonce-inclusion probe against
an earlier wallet transaction) fails with `BlockOutOfRangeError` on a naively restored
bundle.

The fix is to capture with `anvil_dumpState`'s historical-states option
(`preserve_historical_states`) so the dump preserves state at every block, not just the
tip. This is why the flavor's capture step publishes two **machine-checkable gates** in
`state/state-metadata.json`, both enforced by `gate-snapshot-soundness.sh` before any
publish:

1. **`settlement_free: true`** — no certificate ever settled during the captured
   enclave's lifetime.
2. **Every chain's `historical_states > 0`** — the dump actually preserved
   pre-snapshot state, not just the tip.

**A bundle failing either gate cannot settle certificates after restore.** The dump
size is linear in block count (a fresh, settlement-free capture measured ~111 MB total
across three chains at 268 L1 blocks; a long-lived, heavily-bridged enclave would
produce gigabytes) — this is the concrete reason capture must happen immediately after
readiness rather than "at some point before too much history accumulates."

### Timestamp seam on cold restore

Blocks loaded from state keep their **original** timestamps; new blocks produced after
restore use the wall clock. The seam at the boundary therefore equals the snapshot's
age at restore time — measured at 63 seconds for a ~1-minute-old snapshot and 1139
seconds (~19 minutes) for a ~19-minute-old one. **Settlement still works across this
seam** — deliberately exercised on a snapshot cold-restored after a full unshortened
10+ minute wait, with both an L1→L2 autoclaim and a full L2→L1 certificate settlement +
manual claim succeeding.

### `--init` and `--dump-state` are mutually exclusive

Anvil rejects passing both flags at once. Capture therefore goes through the
`anvil_dumpState` **RPC**, not a CLI flag, on all three chains — this also means the L2
anvils cannot copy the L1 anvil's own `src/l1/anvil.star` `--dump-state` CLI pattern.
`--init` and `--load-state` do not conflict with each other, so the restore side (an
`--init` genesis plus `--load-state`) is unaffected.

## See also

- [AggKit 2-L2 with Bridge UI](./aggkit-2l2-with-bridge-ui.md) — the live-enclave,
  op-reth/geth equivalent of this flavor's topology; useful for comparing what a fresh
  `kurtosis run` bring-up looks like against what this flavor freezes into a bundle.
- [Kurtosis CDK Snapshot Tool](./snapshot.md) — the default (geth/lighthouse) flavor
  this one is built alongside; its settlement-freedom prerequisite and troubleshooting
  guidance apply here too.
