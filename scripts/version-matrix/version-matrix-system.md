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
| **tracking head** | ⚠️ | Head-tracked package drifting from upstream, but not yet stale |

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

Not every package releases often enough for "latest release" to mean anything.
`ethereum-package` last tagged `6.1.0` in April 2026 and kept shipping daily, so
comparing our pin against that tag reported `⚡️ newer than stable` permanently —
true, useless, and hiding months of real drift.

`PACKAGE_TRACKING_MODE` sets what "latest" means per package:

```python
PACKAGE_TRACKING_MODE = {
    "github.com/ethpandaops/ethereum-package": "head",
    "github.com/xavier-romero/kurtosis-blockscout": "head",
}
```

- `release` (the default) compares the pin against the latest release or tag.
- `head` compares it against the default branch tip, and the matrix labels the
  column `HEAD (<sha>)` so a sha is never presented as a stable version.

Two kinds of package belong in `head`: those that ship faster than they tag
(`ethereum-package`), and those that have never tagged at all
(`kurtosis-blockscout`). Without an entry, the latter falls back to comparing a
repo against its own branch tip and always looks up to date; the extractor prints
a hint when it finds a package with no releases *and* no tags.

For a head-tracked package, being behind HEAD is the normal steady state, so
distance alone cannot be the alarm. Age is: the pin reports `⚠️ tracking head`
with its commit distance until the pinned commit is older than
`HEAD_TRACKING_STALE_AFTER_DAYS` (14 days — these packages ship most days, so two
weeks is already a meaningful gap), at which point it escalates to
`🚨 behind stable`. If the compare API is unavailable, the age check still
applies on its own rather than reporting nothing.

Age is only consulted when the pin has actually fallen behind: a pin that still
equals HEAD reports `✅ matches stable` however old it is, so a dormant upstream
never raises a false alarm.

Add a package here when its upstream expects consumers to pin commits; remove it
if the project starts tagging releases you can track instead.
