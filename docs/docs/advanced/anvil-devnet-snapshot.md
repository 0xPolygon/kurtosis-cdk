---
sidebar_position: 8
title: "Anvil Devnet Snapshot"
description: "Fast-boot, self-contained anvil + aggkit + agglayer devnet bundle, consumable by dev-ui, aggkit, and agglayer CI without a Kurtosis toolchain"
---

# Anvil Devnet Snapshot

A second [snapshot](./snapshot.md) flavor (`--flavor anvil-aggkit`) that captures a
2-rollup **anvil** enclave — L1, two L2s, agglayer, aggkit ×2 (each also serving the
bridge REST API in-process), an aggkit-proxy and the
[Agglayer Dev UI](https://github.com/agglayer/agglayer-dev-ui) — into a self-contained,
**9-service** `docker-compose.yml` + `summary.json` bundle, with a second
`docker-compose.mounts.yml` variant that trades the zero-mount contract for an
image-override seam on the aggkit-side services. It exists to give any consumer that
needs a real bridging backend a hermetic devnet without a Kurtosis toolchain:
`docker compose up -d --wait` reaches an all-healthy 3-chain devnet in about 24 seconds,
instead of the ~8 minutes a full op-reth/geth `kurtosis run` bring-up takes (see
[AggKit 2-L2 with Bridge UI](./aggkit-2l2-with-bridge-ui.md)).

This page documents the flavor's topology, how to produce and publish a bundle, the
exact bundle contract each consumer depends on (see
[Consuming this bundle](#consuming-this-bundle) for dev-ui, aggkit, and agglayer), the
config/image override seams available on top of the captured state (see
[Overrides](#overrides)), anvil's live reorg support (see [Reorg](#reorg)), and the
restore hazards anvil's `--load-state` semantics create — all of which differ
substantially from the default (geth/lighthouse) flavor described in
[Kurtosis CDK Snapshot Tool](./snapshot.md).

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
| `aggkit-001` / `aggkit-002` | aggsender + aggoracle + autoclaim + bridge per rollup (one process/container serves both the main components and the bridge REST API) | 5576 (rpc), 5577 (rest) |
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

`run1` does **not** need to spell out `l1_rpc_url`/`l1_ws_url`/`l1_beacon_url`:
`input_parser.set_anvil_args` derives all three from the deployment suffix, and
`set_l1_client_args` returns early for an anvil L1 rather than clobbering them back
to the ethereum-package's reth service names. `run2` **does** set them explicitly,
for an unrelated reason: its own suffix is `-002`, but the L1 it must talk to is
run1's `anvil-001`.

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
   self-contained `docker-compose.yml` (no bind mounts, no volumes) and `summary.json`,
   and `snapshot.sh` exits.

**Unlike the default flavor, `--flavor anvil-aggkit` does not auto-run `verify.sh`** —
`snapshot.sh` exits right after generating the summary (the printed line
"Verification for this flavor is not implemented yet" is stale wording left over from
before `verify.sh` gained its anvil-aggkit path; a fix belongs to a future cleanup
pass). Run verification as its own step, exactly as `.github/workflows/snapshot-devui.yml`
does:

```bash
./snapshot/snapshot.sh cdk --flavor anvil-aggkit
./snapshot/verify.sh snapshots/cdk-<timestamp>/
```

A full `snapshot.sh --flavor anvil-aggkit` run (seed → capture → build → compose →
summary, **not including verify**) took 51–80 seconds in measurement (68 seconds on a
fresh 2-L2 anvil enclave while writing this doc); bring-up of the source enclave (both
`kurtosis run` calls) took 224–254 seconds. `verify.sh`'s own full-success runtime for
this flavor is 177–214 seconds — size any automation around ~215 seconds plus margin,
not the snapshot step's own faster number.

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

Two compose files come out of every capture, both under the timestamped output
directory:

| File | Who it's for | Contract |
|---|---|---|
| `docker-compose.yml` | dev-ui (and anyone else who just wants the frozen devnet as-is) | Zero-mount: every image has state/config baked in |
| `docker-compose.mounts.yml` | aggkit / agglayer (anyone who wants to run their **own** build against the captured state) | Same topology, but `agglayer`/`aggkit-00X`/`aggkit-proxy-001` run the bare upstream image plus a read-only bind-mount of the emitted `config/` tree, and are override-able via env vars |

Both are generated by the same `generate-compose.sh`, from the same discovery/state
data, so they can never drift apart in topology, port numbers, or service names.

### `docker-compose.yml` (zero-mount variant)

Self-contained by construction: every service's image already has its captured state,
config and keystores baked in, so the compose file needs nothing else on disk.
`docker compose up -d --wait` blocks until every service's own healthcheck passes.

**The dev-ui container is opt-in via a compose profile.** `agglayer-dev-ui-002` carries
`profiles: ["devui"]`, so a plain `docker compose up -d --wait` brings up 8 of the 9
services and skips it — nothing in dev-ui's own CI (Playwright suite, `devnetReady.mjs`,
`e2e.yaml`) ever fetches bare `/` or talks to that container directly, so this is a
strict subset with no coverage loss. Bring it up explicitly for manual/local debugging:

```bash
docker compose -f docker-compose.yml --profile devui up -d
```

**Bare `/` through haproxy 503s by design in the default (profile-less) set.** The
captured `haproxy.cfg` originally had a `default_backend` fallback routing unmatched
requests to `agglayer-dev-ui-002`. With that container profile-gated off, haproxy tried
to eagerly resolve `agglayer-dev-ui-002` at boot, found no DNS record for it at all (not
merely unhealthy — the container doesn't exist on the network), logged `could not
resolve address 'agglayer-dev-ui-002'`, and **crash-looped** — a fatal boot failure of
the haproxy process itself, not something a healthcheck tweak can fix. Since nothing
CI-relevant ever hits bare `/`, the capture pipeline (`extract-state.sh`'s
`patch_haproxy_default_backend`) drops the `default_backend`/`backend_default` block
from the captured config entirely: an unmatched request now 503s instead of crashing
the process, which is exactly as inert to CI as the removed fallback was. Bringing
dev-ui up via `--profile devui` does **not** restore bare-`/` routing through the
proxy — the container is still directly reachable on its own published port
(`${DEVUI_PORT:-8557}`) either way.

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
| `aggkit-001` / `aggkit-002` | 5576 (rpc), 5577 (bridge rest) | `${L2_00X_AGGKIT_RPC_PORT:-11576/12576}` / `${L2_00X_AGGKIT_REST_PORT:-11577/12577}` |
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

### `docker-compose.mounts.yml` (mounts variant, image-override seam)

Same 9-service topology and same port table as `docker-compose.yml`, but three
services swap their derived (state-baked) image for the **bare upstream image**
recorded in `IMAGE_INFO.json`'s `base_image` field, plus a **read-only bind-mount** of
the emitted `./config/<svc>/` tree (see [Overrides](#overrides) below for what that
tree actually contains):

| Service(s) | Override env var | Default (bare upstream image) | Healthcheck |
|---|---|---|---|
| `agglayer` | `AGGLAYER_IMAGE` | recorded `agglayer` `base_image` (e.g. `ghcr.io/agglayer/agglayer:0.6.0-rc.8`) | compose-level `bash -c 'exec 3<>/dev/tcp/127.0.0.1/<grpc-port>'` TCP-connect probe (K5c) |
| `aggkit-001` / `aggkit-002` / `aggkit-proxy-001` | `AGGKIT_IMAGE` (one var shared by all three — the proxy binary ships in the same image, entrypoint overridden) | recorded `aggkit-proxy-001` `base_image` (e.g. `ghcr.io/agglayer/aggkit:0.11.0-rc5`) | **none** |

Two design decisions worth stating explicitly (K5/K5c), because they're easy to get
wrong by inference:

1. **The override default is the bare upstream image, not the derived `snapshot-<svc>`
   image with the mount merely shadowing its bake.** "Override the image" only means
   something honest if the un-overridden default is *also* the bare image — otherwise
   "override" is just swapping one already-augmented image for another. This also
   matches the shape aggkit's own e2e envs already use (`op-pp-2chains`'s `aggkit-001`:
   `image: aggkit:local`, bind-mounted config, no healthcheck, downstream depends via
   `condition: service_started`).
2. **`aggkit-00X`/`aggkit-proxy-001` get no compose-level healthcheck at all**, because
   aggkit's own images are genuinely distroless — `docker run --entrypoint sh
   <aggkit-image>` fails with `exec: "sh": executable file not found`. This matches
   aggkit's own precedent for those two services exactly. **`agglayer` is different**:
   its bare upstream image is a slim Debian base with both `/bin/sh` (dash) and
   `/bin/bash` present, so it gets a real TCP-connect healthcheck. This exists to close
   a genuine, reproducible deadlock: `aggkit-00X` on a bare `condition: service_started`
   dependency races agglayer's own async gRPC-listener bind against its own local
   claim-syncer autostart. Aggsender's first `SetClaimSyncerNextRequiredBlock` gRPC
   call can stall ~5s (its client's `MinConnectTimeout`) if agglayer isn't yet
   accepting connections, while the claim syncer's local DB races ahead past block 100
   in the same window from local L2 state alone; once local state has moved past 0, a
   later `ClaimSync.SetNextRequiredBlock` call permanently rejects the block-0 fallback
   and aggsender is stuck at `starting_claim_syncer_stage` forever. `agglayer`'s
   healthcheck uses only bash's builtin `/dev/tcp` (no curl/wget/nc needed), and
   `aggkit-00X`/`aggkit-proxy-001`'s `depends_on: agglayer` use
   `condition: service_healthy` to actually consume that signal.

**The trade-off this creates:** `AGGLAYER_IMAGE`, unlike `AGGKIT_IMAGE`, is no longer
override-able with an arbitrary image that lacks `/bin/bash` — such an override sits
permanently unhealthy and `aggkit-00X` never starts. This is a loud, fail-closed
error (the container reports `unhealthy` in `docker compose ps`), not a silent hang, and
is true of every mainstream base image. If you fork this file for a truly shell-less
`AGGLAYER_IMAGE`, you'll need to replace this healthcheck with something that image can
run.

**The anvil family (L1 + every L2) is unchanged and NOT override-able in either
compose file** — no env var, always the derived, state-baked image. Swapping it would
lose the captured chain state, which defeats the entire point of a snapshot. `haproxy`
and `agglayer-dev-ui-002` are likewise not override-able (never in scope): they keep
their derived image and only bind-mount their own config file
(`haproxy.cfg`/`config.json`) over the baked copy.

`apply-digests.sh`'s post-publish digest pin still applies to this file for the anvil
family, haproxy and dev-ui (same `${SNAPSHOT_IMAGE_PREFIX:-...}<svc>:${SNAPSHOT_IMAGE_TAG:-...}`
pattern as `docker-compose.yml`), but is a deliberate no-op for `agglayer`/
`aggkit-00X`/`aggkit-proxy-001` — their refs in this file are already-complete upstream
image strings this repo never republishes under its own digest, so there is no digest
of *this repo's own* for `apply-digests.sh` to pin over them.

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
dev-ui contract, including a real L1→L2 and L2→L1 bridge round trip) → publish 9
images to GHCR → upload `docker-compose.yml` + `summary.json` as a workflow artifact.

```bash
$ ./snapshot/scripts/gate-snapshot-soundness.sh
Usage: ./snapshot/scripts/gate-snapshot-soundness.sh <state-metadata.json>
```

Images publish under `ghcr.io/0xpolygon/kurtosis-cdk-snapshot-<service>` with the
moving human alias `snapshot-latest-devui` plus, per service, an immutable,
self-describing tag `<component-version>-<unix-ts>` (e.g. `0.11.0-rc5-1755100800`,
resolved from the exact upstream image ref that produced that service's baked
image) — the package name and the alias tag both contain the literal word
`snapshot`; the per-service immutable tag does not. The `snapshot-<sha>` tag has
been retired as the pinning mechanism: the authoritative pin is the
`@sha256:<digest>` reference recorded in the generated `docker-compose.yml`
(with the readable tag kept as a trailing comment) and in `summary.json`'s
`images.services.<svc>.{tag,digest}`. The 9 services:
`anvil-001`, `l2-anvil-001`, `l2-anvil-002`, `agglayer`, `aggkit-001`,
`aggkit-002`, `aggkit-proxy-001`,
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

## Consuming this bundle

This bundle has three intended consumers. Pick the subsection that matches you.

### As dev-ui: zero-mount, no build required

Pull `docker-compose.yml` + `summary.json` (a workflow artifact, or the published GHCR
tags) and run it as-is:

```bash
docker compose -f docker-compose.yml up -d --wait
```

Nothing else is needed on disk — every image already has state, config and keystores
baked in. This is the contract dev-ui's own CI depends on today, and the one this whole
page is built around: reach an all-healthy 3-chain devnet in ~24 seconds, talk to it
through `agglayer-dev-ui-proxy-002` on `${DEVNET_PROXY_PORT:-8555}` (the only port
dev-ui CI uses), tear it down with `docker compose down -v`.

### As aggkit: mounts variant + `AGGKIT_IMAGE`

If you're iterating on aggkit itself and want the captured 2-rollup, agglayer-backed
devnet state under **your own** aggkit build rather than the pinned snapshot version,
use `docker-compose.mounts.yml` and override `AGGKIT_IMAGE`:

```bash
AGGKIT_IMAGE=ghcr.io/agglayer/aggkit:0.11.0-rc4 \
  docker compose -f docker-compose.mounts.yml up -d --wait
```

This seam is proven, not aspirational: K5c re-ran this exact override (rc4 against a
bundle captured with rc5) and confirmed `aggkit-001`/`aggkit-002`/`aggkit-proxy-001`
all come up against the mounted `./config/<svc>/` tree and reach the same healthy state
as the un-overridden default. Point `AGGKIT_IMAGE` at a local build the same way
aggkit's own `op-pp-2chains` e2e env points its `aggkit-001` service at `aggkit:local`
— the mechanism is identical (bind-mounted config, no compose healthcheck on the
aggkit-role services, `condition: service_started` from anything that merely needs the
process running).

### As agglayer: the same seam, untried

`AGGLAYER_IMAGE` on `docker-compose.mounts.yml` is a genuine override seam by
construction — it exists specifically so an agglayer build-under-test can run against
this same captured state — but as of this writing it has only been exercised with the
**default** (recorded upstream) image, to validate the compose-level TCP healthcheck
K5c added (see [`docker-compose.mounts.yml`](#docker-composemountsyml-mounts-variant-image-override-seam)
above). Actually pointing `AGGLAYER_IMAGE` at a different agglayer build (a local image,
or a different released tag) has not been tried by this plan. The one hard requirement
if you do: **your `AGGLAYER_IMAGE` must carry `/bin/bash`** — the healthcheck is a bash
`/dev/tcp` TCP-connect probe against agglayer's own gRPC port, and a bash-less image
sits permanently `unhealthy`, which blocks `aggkit-00X` from ever starting (loud and
fail-closed, not a silent hang, since `aggkit-00X`'s `depends_on: agglayer` requires
`condition: service_healthy`).

## Overrides

Everything in this section is a **Kurtosis input arg** (`args:` in a `params-*.yml`
file passed to `kurtosis run --args-file=...`), consumed at **capture** time by the
two-run bring-up described in [Bring-up: the two-run params
pair](#bring-up-the-two-run-params-pair) — not a `docker-compose.mounts.yml` env var
(those are [Consuming this bundle](#consuming-this-bundle)'s concern, for
**restore**-time overrides). Every snippet below was executed at least once against a
live `anvil-aggkit` enclave while writing this page, and each has its own evidence file
under `plans/snapshot-v2-aggkit-e2e/K6-evidence/` (`06`–`17`), including the negative
(validation-failure) cases (`01`–`05`).

### AggKit-side overrides

**`aggkit_image`** — which upstream aggkit build the capture pipeline deploys.
`params-aggkit-anvil-l2l2-run1.yml`/`run2.yml` already override this away from the
package default (`ghcr.io/agglayer/aggkit:0.10.0-rc7`, `src/package_io/constants.star`)
to `ghcr.io/agglayer/aggkit:0.11.0-rc5`:

```yaml
args:
  aggkit_image: ghcr.io/agglayer/aggkit:0.11.0-rc5
```

Confirmed live: `docker inspect` on the running `aggkit-001` container reports exactly
that image string (`K6-evidence/07-image-override-confirmation.log`).

**`aggkit_components`** — which aggkit sub-processes run in the same container. This
flavor sets `"aggsender,aggoracle,autoclaim,bridge"` on both L2s (`run1.yml`/`run2.yml`)
— note **`bridge` is in the main process's own component list**, not a separate
service: there is no `aggkit-00X-bridge` sidecar (merged in K1). Confirmed live: with
this exact component list, `curl http://<aggkit-001>:5577/bridge/v1/bridges?network_id=1`
returns a normal bridge-REST response from the same container aggsender/aggoracle run
in (`K6-evidence/12-aggkit-bridge-rest-check.log`).

**`trigger_cert_mode` — and why this flavor pins it to `"ASAP"` explicitly.** Valid
values are `EpochBased`, `NewBridge`, `ASAP`, `Auto` (validated at Starlark time;
an invalid value fails fast — `K6-evidence/01-neg-trigger-cert-mode.log`:
`Unsupported Aggkit TriggerCertMode: 'Bogus', please use one of [...]`). `Auto` is
**not** a fifth mode — it's resolved to one of the other three based on the
aggsender's own `Mode`, and for this flavor's `PessimisticProof` aggsender mode, it
resolves to **`EpochBased`**, not `ASAP` (`agglayer/aggkit`
`aggsender/trigger/factory.go`'s `defaultTriggerForAggsenderMode`:
`AggchainProofMode, PessimisticProofMode` → `EpochBasedTriggerMode`). Confirmed live by
setting `trigger_cert_mode: "Auto"` and reading aggkit's own log line
(`K6-evidence/08-aggkit-001-full-logs.log`):

```
INFO	trigger/factory.go:35	Resolved Auto TriggerCertMode to EpochBased based on AggsenderMode PessimisticProof
```

`EpochBased` certificate triggering is driven by `[epoch.block-clock]` on the
**agglayer** side — see [why `[epoch.block-clock]` is not the knob you
want](#why-epochblock-clock-is-not-the-knob-you-want) below for why that table is
mostly bookkeeping now. `ASAP` triggers a new certificate as soon as the previous one
reaches a final state, which is what this flavor actually wants for fast, deterministic
CI cadence — hence pinning it explicitly rather than leaving it on `Auto` and inheriting
whatever `EpochBased` happens to do. (aggkit's own `op-pp`/`op-pp-2chains` e2e envs make
the same choice, explicit `TriggerCertMode = "ASAP"` in every instance.)

**Per-instance config + keystores.** Each aggkit instance's rendered config and signing
keys are captured verbatim from `/etc/aggkit` inside its container into
`config/aggkit-00X/` in the bundle (`config.toml`, `sequencer.keystore`,
`aggoracle.keystore`, `sovereignadmin.keystore`; an optional `claimsponsor.keystore` may
also be present). `agglayer`'s config + signer follow the same pattern
(`config/agglayer/config.toml`, `config/agglayer/aggregator.keystore`). This is exactly
the tree `docker-compose.mounts.yml` bind-mounts read-only over the bare upstream image
(see [`docker-compose.mounts.yml`](#docker-composemountsyml-mounts-variant-image-override-seam)
above) — nothing further to configure via a params-yml override here; the params-yml
inputs above are what *produce* this tree's contents at capture time.

**aggkit-proxy config.** `aggkit_proxy_bridge_urls`/`aggkit_proxy_rpc_urls` (network_id
→ bridge-REST URL / RPC URL maps, one entry per network including `0` for L1) are set on
`run2.yml` and captured into `config/aggkit-proxy-001/config.toml`. Confirmed live on a
full run1+run2 bring-up: `aggkit-proxy-001`'s `/bridge/v1/bridges?network_id={0,1,2}`
correctly multiplexes to the right upstream aggkit instance per network, and
`/tracker/v1/health` responds, both through the proxy directly and through haproxy's
`/aggkitapi` route (`K6-evidence/17-aggkit-proxy-and-haproxy-check.log`). The bridge
tracker's own `[Tracker]` config (retention, `L1GlobalExitRootAddress` fail-fast
validation, etc.) is unchanged by this flavor and already documented in [AggKit 2-L2
with Bridge UI](./aggkit-2l2-with-bridge-ui.md#bridge-tracker-configuration) — not
duplicated here.

### Agglayer overrides

**`agglayer_image`** — which upstream agglayer build the capture pipeline deploys
(package default `ghcr.io/agglayer/agglayer:0.6.0-rc.8`):

```yaml
args:
  agglayer_image: ghcr.io/agglayer/agglayer:0.6.0-rc.7
```

Confirmed live: the running `agglayer` container's image is exactly `0.6.0-rc.7`
(`K6-evidence/07-image-override-confirmation.log`).

**The `[settlement.pessimistic-proof-tx-config]` knobs (K3).** Two input args, both
validated at Starlark time:

```yaml
args:
  agglayer_settle_confirmations: 5      # >= 1 -- an L1 block-confirmation count
  agglayer_settlement_policy: "finalized"  # one of: latest | safe | finalized
```

Invalid values fail fast (`K6-evidence/02-neg-settlement-policy.log`:
`Unsupported agglayer_settlement_policy: 'bogus', ...`;
`K6-evidence/03-neg-agglayer-confirmations.log`:
`agglayer_settle_confirmations must be >= 1`). Confirmed live: the rendered
`/etc/agglayer/config.toml` on a running `agglayer` container shows exactly
`confirmations = 5` and `settlement-policy = "FinalizedBlock"`
(`K6-evidence/09-agglayer-rendered-config.toml`) — note the wire value is
**`FinalizedBlock`, PascalCase**, not `finalized`: agglayer's `SettlementPolicy` enum
has no `#[serde(rename_all = "kebab-case")]`, confirmed against
`crates/agglayer-config/tests/fixtures/settlement/*.toml` at `v0.6.0-rc.8`, which all
use the PascalCase variant names verbatim (`LatestBlock`/`SafeBlock`/`FinalizedBlock`).
The lowercase `latest`/`safe`/`finalized` tokens are this package's own user-facing
input values, translated in the template — do not document the wire value as
kebab-case; that's wrong and would silently fall back to the upstream default if
someone tried to hand-write it that way.

**Lead with this when tuning settlement latency, not `confirmations`:** K3 measured
end-to-end L2→L1 settlement wall-clock before/after the `confirmations` fix (12 → 1) on
the same anvil enclave shape: **60.008s → 60.006s, a ≈0 delta.** The dominant floor is
`retry-on-not-included-on-l1`'s default **60s `initial-interval`** — the settlement
task's first receipt check fires immediately and returns `NotIncludedYet`, and that
interval gates the *next* attempt regardless of how many confirmations are required on a
1-second-block anvil L1. Neither `retry-on-not-included-on-l1`'s `initial-interval` nor
`epoch-duration` has an input-arg override in this package today — the
`confirmations`/`settlement-policy` migration above is a **correctness** fix (single
source of truth, no silently-ignored config, no stale-config startup warning at
rc.7+), not a latency knob.

### Why `[epoch.block-clock]` is not the knob you want

`static_files/agglayer/config.toml`'s `[epoch.block-clock]` table (`epoch-duration`,
`genesis-block`) looks like a natural certificate-cadence knob, and used to be one — but
as of `v0.6.0-rc.2` (PR [#1615](https://github.com/agglayer/agglayer/pull/1615), commit
`41d7a17e`), per-epoch certificate rate limiting was **deleted**. `epoch-duration` still
parses and still drives epoch bookkeeping/storage indexing, but under this package's
default `trigger_cert_mode: "ASAP"` it moves **neither settlement nor submission
timing**. (It still matters if you set `trigger_cert_mode: "EpochBased"` explicitly, or
land on it via `Auto` on a `PessimisticProof`/`AggchainProof` aggsender — see
[AggKit-side overrides](#aggkit-side-overrides) above.) This table also has a dead
predecessor worth knowing about so you don't go looking for it: an old `[outbound]`
block used to carry a `confirmations` key that had no effect on settlement since
agglayer PR #1393 (`agglayer-settlement-service`'s introduction) made `OutboundConfig`
deprecated outright; K3 deleted that dead block from this repo's template rather than
leaving it as a red herring.

### Anvil block/finality timing

Two pairs of input args (one pair per layer) control the **latest → safe → finalized**
lag on this flavor's anvil chains, each mapped straight onto anvil's own
`--block-time`/`--slots-in-an-epoch` CLI flags (`src/l1/anvil.star`,
`src/chain/anvil/anvil_l2.star`):

```yaml
args:
  l1_anvil_block_time: 2        # seconds per L1 block
  l1_anvil_slots_in_epoch: 3    # L1 blocks per epoch
  l2_anvil_block_time: 2        # seconds per L2 block (per L2 instance)
  l2_anvil_slots_in_epoch: 2    # L2 blocks per epoch (per L2 instance)
```

**The formula is `block_time × slots_in_epoch` seconds per finality step**, and each of
`safe`/`finalized` is a further **whole epoch** behind `latest` (i.e. `finalized` is two
epochs behind `latest`, not one) — confirmed by direct RPC measurement against a live
enclave with the values above (`K6-evidence/11-anvil-block-timing.log`):

| Layer | `latest` | `safe` | `finalized` | latest→safe (blocks / seconds) | latest→finalized (blocks / seconds) |
|---|---|---|---|---|---|
| L1 (block_time=2, slots=3) | #99 | #96 | #93 | 3 blocks / 6s | 6 blocks / 12s |
| L2 (block_time=2, slots=2) | #44 | #42 | #40 | 2 blocks / 4s | 4 blocks / 8s |

Both match the formula exactly: `2 × 3 = 6s` on L1, `2 × 2 = 4s` on L2. With this
package's anvil defaults (`block_time=1`, `slots_in_epoch=1` on both layers) the
`latest`→`safe` lag is only ~1s — nowhere near a real L1's multi-minute safe/finalized
lag, so `agglayer_settlement_policy: "latest"` buys little on a stock anvil enclave;
raise these two args first if you actually want to exercise `"safe"`/`"finalized"`
behavior under a realistic lag.

**The `>= 1` floor is asymmetric between layers — a real gap, not a formatting choice.**
`l2_anvil_block_time`/`l2_anvil_slots_in_epoch` **are** validated at Starlark time
(`args_sanity_check`): `l2_anvil_block_time: 0` fails fast with `l2_anvil_block_time /
l2_anvil_slots_in_epoch must be >= 1` before any container is created
(`K6-evidence/04-neg-l2-anvil-floor.log`). **The L1 equivalents have no such check** —
`grep`ing `input_parser.star` for `l1_anvil_block_time`/`l1_anvil_slots_in_epoch` turns
up no `< 1`/`fail(...)` guard at all. Setting `l1_anvil_block_time: 0` sails straight
through Starlark validation and deploys `anvil-001`, which then **crashes at the anvil
binary level**: `error: invalid value '0' for '--block-time <SECONDS>': Duration must
be greater than 0`, exit code 2, container left `STOPPED`
(`K6-evidence/05-l1-anvil-floor-probe.log`, `K6-evidence/05b-l1-anvil-floor-probe-anvil-logs.log`).
The practical effect is the same either way (don't set either to `0`), but the failure
**mode** differs: L2 fails in ~seconds with a clear Starlark message before touching
Docker; L1 fails only once `add_service` tries to bring the container up, and needs a
`docker logs anvil-001` to see why.

**Why `anvil_image` is pinned to `v1.5.1`** and not left as an overridable knob here —
see [Why anvil](#why-anvil) above; short version: agglayer's settlement task needs
`eth_getTransactionBySenderAndNonce`, which only exists from anvil `v1.5.0` onward, and
an older anvil makes every certificate loop forever in `InError`.

## Reorg

Anvil's `anvil_reorg` JSON-RPC method works on both this flavor's L1 and L2 chains,
including against a `--load-state`-restored bundle — this is T2's finding, re-run
successfully while writing this page against a live `anvil-aggkit` enclave
(`K6-evidence/13-reorg-recipe-rerun.log`, `K6-evidence/14-post-reorg-enclave-status.log`).

**Exact JSON-RPC shape:**

```
anvil_reorg(depth: number, txBlockPairs: [ [TransactionRequest, blockIndex], ... ])
```

- `depth` — how many blocks back from the current head to replace.
- `txBlockPairs` — `[]` for an empty reorg (replacement blocks contain no
  transactions), or `[transactionRequestObject, blockIndex]` pairs to inject specific
  transactions. **`blockIndex` is 0-based, counted from the first replaced block**
  (`head - depth + 1`), **not from the head.**
- Response on success: `{"jsonrpc":"2.0","id":1,"result":null}`.

**Copy-pasteable recipe** (re-run successfully against a live enclave; the same shape
works against a restored `docker-compose.yml`/`docker-compose.mounts.yml` bundle —
just point at the published ports instead):

```bash
# L1 (anvil-001)
curl -s -X POST http://127.0.0.1:8545 -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"anvil_reorg","params":[N,[]]}'

# L2 (l2-anvil-001 / l2-anvil-002)
curl -s -X POST http://127.0.0.1:11545 -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"anvil_reorg","params":[N,[]]}'
```

**A no-op-looking result is not proof of failure.** An empty-array reorg of an
already-empty tip can legitimately produce a **byte-identical block** (anvil
deterministically reuses the original timestamp, zero difficulty, zero nonce, empty
tx/receipt roots). Always verify a reorg with either an injected transaction or a
block-hash diff at the **head** — never at `head - depth`, where a genuinely successful
reorg can still show no visible change.

**What recovery looks like.** For any reorg whose fork point stays *above* the chain's
own bridge-contract deployment block, aggkit's syncers self-detect and self-heal within
the same poll cycle — no operator action needed, and no container leaves `healthy`:

```
reorg detected at block 114   (claimsync/processor.go / bridgesync/processor.go)
reorged to block 114, 0 rows deleted
```

(Both lines confirmed live at depth 5 on this flavor's own enclave,
`K6-evidence/13-reorg-recipe-rerun.log`; the bridge REST API returned a normal response
immediately afterward, no restart needed.)

### The real ceiling: the bridge-contract deployment block, not the load point

**This replaces an earlier, narrower framing of this section around anvil's
`--load-state` tip-only restore behavior** — see [the reconciliation
note](#a-naive-anvil---load-state-would-only-restore-the-tip-state--why-this-bundle-doesnt-hit-that)
under Restore constraints below for why that framing doesn't apply to the published
bundle. The reorg ceiling that actually matters is different, and unrelated to
`--load-state` at all:

Reorging **at or below** a chain's own bridge-contract deployment block erases that
contract's deployment transaction from the canonical chain. Nothing in
aggkit/agglayer/anvil redeploys a missing contract, so `eth_getCode` at the bridge
address returns `0x` **permanently**. The bridge REST API starts 500ing
(`"failed to get deposit count from L2 bridge contract: ... no contract code at given
address"`), and every bridge-dependent container (`aggkit-*` bridge routes,
`aggkit-proxy-001`, the dev-ui proxy) goes `unhealthy` and **stays that way** — this is
permanent breakage, not a transient one the syncers recover from on their own.

T2 measured this on the published bundle: L1's bridge deployment block was **48**
against a capture point of 253 (200+ blocks of headroom — depths up to 74, forking one
block *above* 253, all fully recovered; depths of 100+ forking down toward/through
block 48 permanently broke the bridge). L2-001's deployment block was **1** — almost
the entire L2 chain is safe to reorg into. **The exact off-by-one boundary was left
ambiguous by ±1 block** in T2's own testing, so treat "stay several blocks clear of the
deployment block" as the operative rule, not a precise cutoff — and expect the
deployment block to differ per capture. If you need the exact number for a specific
bundle, bisect it with `eth_getCode` against the deterministic bridge address
(`0xC8cbEBf950B9Df44d987c8619f092beA980fF038`).

## Restore constraints and hazards

The default flavor's constraint carries over unchanged: **the source enclave must not
have settled anything through agglayer before capture** — agglayer/aggkit internal
databases are never part of the snapshot, so restoring L1/L2 state that already
reflects settlement activity is unsound (see [Agglayer Settlement
Constraint](./snapshot.md#agglayer-settlement-constraint)). Capture must run
**immediately after enclave readiness**, before any bridge transaction.

### A naive `anvil --load-state` would only restore the tip state — why this bundle doesn't hit that

**Update (T2, re-verified against the published bundle):** the paragraph below describes
a real anvil behavior and the mechanism this flavor's pipeline uses to defeat it — but
on every bundle this flavor actually publishes, **the hazard does not manifest**. T2
reorged L1 all the way to genesis (depth 326, fork at block 0) on the currently
published bundle and found `eth_call`/`eth_getBalance` returning valid results at every
pre-capture height throughout, with no `BlockOutOfRangeError` at any depth. Treat what
follows as "how the gate keeps this from happening", not as an open caveat you need to
work around yourself.

By default, `anvil --load-state` restores blocks, transactions, receipts and logs for
the entire captured history, but only **one state — the tip**: `eth_getLogs`/
`eth_getBlockByNumber` work at any height after restore, but `eth_call`/`eth_getCode`
only work at the snapshot block and later. Any component that pins a state read to a
pre-snapshot block (aggkit's initial local-exit-root read at
`rollupCreationBlockNumber`; agglayer's settlement-signer nonce-inclusion probe against
an earlier wallet transaction) would fail with `BlockOutOfRangeError` on a **naively**
restored bundle.

The fix is to capture with `anvil_dumpState`'s historical-states option
(`preserve_historical_states`) so the dump preserves state at every block, not just the
tip — this is what this flavor's `extract-state.sh` always does. To make sure a future
regression can't silently ship a naive (tip-only) dump, the capture step publishes two
**machine-checkable gates** in `state/state-metadata.json`, both enforced by
`gate-snapshot-soundness.sh` before any publish:

1. **`settlement_free: true`** — no certificate ever settled during the captured
   enclave's lifetime.
2. **Every chain's `historical_states > 0`** — the dump actually preserved
   pre-snapshot state, not just the tip.

**A bundle failing either gate cannot settle certificates after restore, and is never
published.** Every bundle you can actually pull already passed gate 2, which is exactly
why T2 found the tip-only hazard didn't reproduce. The dump size is linear in block
count (a fresh, settlement-free capture measured ~111 MB total across three chains at
268 L1 blocks; a long-lived, heavily-bridged enclave would produce gigabytes) — this is
the concrete reason capture must happen immediately after readiness rather than "at
some point before too much history accumulates."

**Does the published bundle's `summary.json` itself say so?** No — check this
yourself rather than trusting a stale claim: `historical_states` lives only in the
capture-time `state/state-metadata.json` that `gate-snapshot-soundness.sh` reads before
publish; `generate-summary.sh` copies that file's `settlement_free` field into
`summary.json` but never copies `historical_states` across (confirmed by reading
`generate-summary.sh` — no reference to that field anywhere in it). So `summary.json`
tells you the bundle is settlement-free, but not, by itself, that it preserved
historical states — you have to trust the publish gate (or T2's empirical result above)
for that. This is unchanged behavior; nothing in K1–K6 touched `generate-summary.sh`'s
field list, so it applies equally to bundles published before and after this plan.

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
