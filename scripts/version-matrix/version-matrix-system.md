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
                    ├─► extract-versions.py ──► version-matrix.json ──► generate-markdown.py ──► VERSION_MATRIX.md
.github/tests/ ─────┤
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
