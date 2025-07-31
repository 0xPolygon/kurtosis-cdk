# Automated Version Matrix System

This document describes the automated version matrix system for Kurtosis CDK, which ensures that version compatibility information is automatically maintained and reliably communicated.

## Overview

The version matrix system automates the process of tracking component versions across different Kurtosis environments and test scenarios. It provides:

- **Automated extraction** of version information from code and configurations
- **Comprehensive mapping** of versions used in different test scenarios
- **Status tracking** for versions (latest, deprecated, experimental)
- **Human-readable documentation** generation
- **CI automation** for regular updates

## Architecture

### Components

1. **Version Extraction** (`scripts/version-matrix/extract-versions.py`)
   - Parses `input_parser.star` for default component versions
   - Scans `.github/tests/` for test scenario configurations
   - Fetches latest release information from GitHub APIs
   - Generates machine-readable version data (`version-matrix.json`)

2. **Markdown Generation** (`scripts/version-matrix/generate-markdown.py`)
   - Creates human-readable version matrix documentation
   - Includes status indicators and source links
   - Groups test scenarios by architecture type
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

The system tracks four status types for each component version:

| Status | Icon | Description |
|--------|------|-------------|
| **Latest** | ✅ | Current latest release, recommended for use |
| **Experimental** | 🧪 | Newer than latest release, may be pre-release or beta |
| **Deprecated** | ⚠️ | Older than latest release but still functional |
