# Automated Version Matrix System

This document describes the automated version matrix system for Kurtosis CDK, which ensures that version compatibility information is automatically maintained and reliably communicated.

## Overview

The version matrix system automates the process of tracking component versions across different Kurtosis environments and test environments. It provides:

- **Automated extraction** of version information from code and configurations
- **Comprehensive mapping** of versions used in different test environments
- **Status tracking** for versions (latest, deprecated, experimental)
- **Human-readable documentation** generation
- **CI automation** for regular updates

## Architecture

### Components

1. **Version Extraction** (`scripts/version-matrix/extract-versions.py`)
   - Parses `input_parser.star` for default component versions
   - Scans `.github/tests/` for test environment configurations
   - Parses the `replace` block in `kurtosis.yml` for external Kurtosis package pins
   - Reads the L1 and OP Stack hard fork schedules (`hard_forks.py`)
   - Fetches latest release information from GitHub APIs
   - Generates machine-readable version data (`version-matrix.json`)

2. **Markdown Generation** (`scripts/version-matrix/generate-markdown.py`)
   - Creates human-readable version matrix documentation
   - Includes status indicators and source links
   - Groups test environments by architecture type
   - Provides comprehensive component details

3. **CI Automation** (`.github/workflows/version-matrix-update.yml`)
   - Runs daily to check for updates
   - Automatically commits changes when detected
   - Provides detailed summary reports
   - Can be triggered manually

### Data Flow

```
input_parser.star ──┐
                    │
.github/tests/ ─────┼─► extract-versions.py ──► version-matrix.json ──► generate-markdown.py ──► VERSION_MATRIX.md
                    │
kurtosis.yml ───────┤
                    │
GitHub APIs ────────┘
```

## Usage

Run the scripts individually to update the version matrix:

```bash
# Set a Github token to access GitHub API for version information.
export GITHUB_TOKEN="..."
# source .env

# Extract version data
# File saved to scripts/version-matrix/matrix.json
python3 scripts/version-matrix/extract-versions.py

# Generate Markdown documentation
# File saved to docs/docs/version-matrix.md
python3 scripts/version-matrix/generate-markdown.py
```

## CI Integration

The system is automatically integrated with GitHub Actions:

- **Daily updates** at 2 AM UTC
- **Triggered by changes** to version-related files
- **Manual triggers** available through GitHub UI
- **Pull request creation** for non-main branches

## Version Status System

The system tracks status types for each component version:

| Status | Icon | Description |
|--------|------|-------------|
| **matches stable** | ✅ | Current latest release, recommended for use |
| **newer than stable** | ⚡️ | Newer than latest release, may be pre-release or beta |
| **behind stable** | 🚨 | Older than latest release and should be bumped |
| **pinned** | 📌 | Deliberately held back — see the reason in the matrix |

### Pinned versions

Some environments cannot track the latest release yet: for example
`cdk-opreth-sovereign-pessimistic` and `cdk-erigon-sovereign-pessimistic` only
support aggkit `0.5.x`, and `cdk-erigon-validium` / `cdk-erigon-zkrollup` are
held on cdk-erigon `2.61.x`. Without a rule for this, those rows show 🚨
permanently, which trains everyone to ignore the alarm and hides real
regressions.

Declare such cases in `PINNED_VERSIONS` in `extract-versions.py`, keyed by
`(environment, component)` with a short reason:

```python
PINNED_VERSIONS = {
    ("cdk-erigon-validium", "cdk-erigon"): "Only supports cdk-erigon 2.61.x so far.",
}
```

Keep every reason in the same short form — `Only supports <component> <line> so
far.` — so the status column reads consistently and stays narrow.

The pin only ever downgrades a `behind stable` result. Once the pinned
component catches up with (or overtakes) stable, its real status is reported
again — that is the signal to delete the entry. Pins are scoped to a single
environment, so a component pinned in one environment still reports 🚨 in the
others.

## External Kurtosis Packages

Alongside container images, the matrix tracks the external Kurtosis packages
this package depends on (`ethereum-package`, `optimism-package`, and so on).

Those versions live in exactly one place: the `replace` block of
`kurtosis.yml`. `replace` overrides the version of every matching reference in
the repo — including transitive dependencies — so the `.star` files reference
packages *without* an `@<version>` suffix and a bump only happens once.

```yaml
replace:
  github.com/ethpandaops/ethereum-package: github.com/ethpandaops/ethereum-package@<commit> # <date>
```

`scripts/version-matrix/verify-package-pins.py` runs in CI (offline, no token
needed) and fails if:

- a `.star` file pins a version inline — `replace` silently overrides it, so the
  inline version is misleading rather than effective;
- a referenced package has no `replace` entry, or an entry without a version —
  both resolve at upstream HEAD;
- a `replace` entry is no longer referenced anywhere — stale config.

Status is computed the same way as for images, except commit pins are compared
by *ancestry* rather than by date: the script asks the GitHub compare API
whether the pinned commit is ahead of or behind the latest release, because a
commit can be authored after a release was published while still being an
ancestor of it. The resulting distance (e.g. `14 commits behind 1.0.0`) is shown
in the matrix. Packages deliberately held back go in `PINNED_PACKAGES`, keyed by
package locator, using the same short reason form as `PINNED_VERSIONS`.

### Release-tracked vs head-tracked packages

What "latest" means follows from how a package is pinned in `kurtosis.yml`:

- A **tag** pin (`@v2.0.0`) is release-tracked: compared against the latest
  release or tag.
- A **commit** pin (`@6dd3f26…`) is head-tracked: compared against the default
  branch tip, and the matrix labels the column `HEAD (<sha>)` so a sha is never
  presented as a stable version. We pin commits when upstream ships faster than
  it tags, so the latest tag would report `⚡️ newer than stable` forever.

A head-tracked pin reports `🚨 behind stable` with its commit distance as soon as
HEAD moves past it, so the nightly bump PR follows the branch tip: one refreshed
PR per upstream change rather than a pin drifting unnoticed. A pin ahead of HEAD
(an unmerged or rewritten commit) reports `⚡️ newer than stable`.

## Hard Forks

`hard_forks.py` compares what the devnet activates with what the pinned clients
support, for two domains:

| Domain   | Devnet schedule                                                                         | Checked against                                                    |
|----------|-----------------------------------------------------------------------------------------|--------------------------------------------------------------------|
| L1       | ethereum-package `minimal` preset defaults, overridden in `src/l1/ethereum.star`        | geth `params/config.go`, lighthouse built-in mainnet `config.yaml` |
| OP Stack | optimism-package `*_time_offset` defaults, overridden in `src/package_io/op_input_parser.star` | the mainline forks of op-node `op-core/forks/forks.go`             |

Upstream files are read at the refs this repo pins (image tags, the `kurtosis.yml`
package pins), never at upstream HEAD. The tables therefore only change when a
pin or the package config changes: a fork that is merely announced or scheduled
upstream never makes the nightly diff non-empty. A failed fetch fails the script
instead of rendering a fork as unsupported.

| Status                  | Icon | Description                                                               |
|-------------------------|------|---------------------------------------------------------------------------|
| enabled                 | ✅   | Activated by the devnet and known to the pinned clients                   |
| not enabled             | 💤   | Known to the pinned clients, but the devnet leaves it off                 |
| not supported yet       | ⏳   | Exposed by the package, but not known to a pinned client yet              |
| enabled but unsupported | ❌   | Configured by the devnet, but a pinned client ignores the setting         |
| op-deployer default     | ⚙️   | Left unset, so op-deployer's standard schedule decides when it activates |

An OP Stack fork left unset is omitted from the op-deployer intent, so its
activation follows op-deployer's standard schedule, which cannot be read from
source: set its `*_time_offset` to pin it. Fork rows never use 🚨, so the bump
workflow leaves them alone: enabling a fork is a decision, not a version bump.
The L1 code is shared with kurtosis-pos's copy of `hard_forks.py`: keep both in
sync. A new L1 fork needs its EL name in `L1_EL_FORKS`, or its geth column reads
`—`.
