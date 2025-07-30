# Automated Version Matrix System

This document describes the automated version matrix system for Kurtosis CDK, which ensures that version compatibility information is automatically maintained and reliably communicated.

## Overview

The version matrix system automates the process of tracking component versions across different Kurtosis environments and test scenarios. It provides:

- **Automated extraction** of version information from code and configurations
- **Comprehensive mapping** of versions used in different test scenarios (FEP, PP, CDK-Erigon)
- **Status tracking** for versions (stable, deprecated, experimental, pinned)
- **CI automation** for regular updates
- **Validation** to ensure version consistency

## Architecture

### Components

1. **Version Extraction** (`scripts/version-matrix/extract-versions.py`)
   - Parses `input_parser.star` for default component versions
   - Scans `.github/tests/` for test scenario configurations
   - Fetches latest release information from GitHub APIs
   - Generates machine-readable version data

2. **Markdown Generation** (`scripts/version-matrix/generate-markdown.py`)
   - Creates human-readable version matrix documentation
   - Includes status indicators and source links
   - Groups test scenarios by type (FEP, PP, CDK-Erigon)
   - Provides comprehensive component details

3. **Validation** (`scripts/version-matrix/validate-versions.py`)
   - Checks for version consistency across configurations
   - Identifies deprecated or experimental versions in critical components
   - Validates fork compatibility
   - Reports missing version information

4. **CI Automation** (`.github/workflows/version-matrix-update.yml`)
   - Runs daily to check for updates
   - Automatically commits changes when detected
   - Provides detailed summary reports
   - Can be triggered manually

### Data Flow

```
input_parser.star ──┐
                    ├─► extract-versions.py ──► version-matrix.json
.github/tests/ ─────┤                                    │
                    │                                    ├─► generate-markdown.py ──► CDK_VERSION_MATRIX.MD
GitHub APIs ───────┘                                    │
                                                         └─► validate-versions.py ──► Validation Report
```

## Usage

### Manual Updates

Use the convenience script to update the version matrix manually:

```bash
# Update matrix files
./scripts/version-matrix/update-matrix.sh

# Only validate existing configuration
./scripts/version-matrix/update-matrix.sh --validate-only

# Update and commit changes
./scripts/version-matrix/update-matrix.sh --commit

# Force update even if no changes detected
./scripts/version-matrix/update-matrix.sh --force
```

### Individual Scripts

Run individual components:

```bash
cd scripts/version-matrix

# Extract version data
python3 extract-versions.py

# Generate Markdown documentation
python3 generate-markdown.py

# Validate version consistency
python3 validate-versions.py
```

### CI Integration

The system is automatically integrated with GitHub Actions:

- **Daily updates** at 2 AM UTC
- **Triggered by changes** to version-related files
- **Manual triggers** available through GitHub UI
- **Pull request creation** for non-main branches

## Version Status System

The system tracks four status types for each component version:

| Status | Icon | Description |
|--------|------|-------------|
| **Stable** | ✅ | Production-ready, recommended for use |
| **Deprecated** | ⚠️ | No longer recommended, will be removed in future versions |
| **Experimental** | 🧪 | Under development, may have breaking changes |
| **Pinned** | 📌 | Specific version required due to compatibility or bug fixes |

### Status Determination

The system automatically determines status based on:

- **Version patterns** (alpha, beta, RC, dev → experimental)
- **Special indicators** (hotfix, patch → pinned)
- **Age heuristics** (very old versions → deprecated)
- **Manual overrides** (for special cases)

## Test Scenario Mapping

The system maps versions across different test scenarios:

### FEP (Full Execution Proofs)
- Uses `consensus_contract_type: fep`
- Leverages OP Succinct stack for proof generation
- Requires fork_id: 0 for ECDSA consensus

### PP (Pessimistic Proofs)  
- Uses `consensus_contract_type: pessimistic`
- Traditional ZK proof system
- Compatible with various fork IDs

### CDK-Erigon
- Uses `sequencer_type: erigon`
- Works with `rollup` and `cdk_validium` consensus types
- High performance sequencer implementation

### Component Matrix

The system tracks versions for these core components:

- **CDK Erigon**: High-performance sequencer
- **ZkEVM Prover**: Zero-knowledge proof generation
- **Agglayer Contracts**: Smart contract infrastructure
- **Data Availability**: Off-chain data storage (validium mode)
- **Bridge Service**: Cross-chain asset transfers
- **AggKit/Agglayer**: Aggregation layer components
- **CDK Node**: Core CDK infrastructure
- **Supporting Services**: Status checker, test runner, etc.

## Configuration Files

### Input Sources

1. **`input_parser.star`** - Default component versions
   ```python
   DEFAULT_IMAGES = {
       "cdk_erigon_node_image": "hermeznetwork/cdk-erigon:v2.61.19",
       "zkevm_prover_image": "hermeznetwork/zkevm-prover:v8.0.0-RC16-fork.12",
       # ... more components
   }
   ```

2. **`.github/tests/`** - Test scenario configurations
   ```yaml
   args:
     consensus_contract_type: rollup
     sequencer_type: erigon
     agglayer_contracts_image: europe-west2-docker.pkg.dev/.../agglayer-contracts:v11.0.0-rc.2-fork.12
   ```

3. **`.github/tests/matrix.yml`** - Fork compatibility matrix
   ```yaml
   12-validium:
     fork_id: '12'
     consensus: validium
     cdk_erigon:
       version: v2.61.19
       source: https://github.com/0xPolygonHermez/cdk-erigon/releases/tag/v2.61.19
   ```

### Output Files

1. **`CDK_VERSION_MATRIX.MD`** - Human-readable documentation
2. **`version-matrix.json`** - Machine-readable data for tooling

## Validation Rules

The validation system enforces several rules:

### Critical Component Rules
- Critical components must use stable versions
- Experimental versions in critical components generate warnings
- Deprecated versions in critical components generate errors

### Consistency Rules
- Version mismatches between scenarios and defaults are reported
- Invalid consensus types are flagged as errors
- Missing version information generates errors

### Format Rules
- Version strings must follow semantic versioning patterns
- Source URLs must be valid GitHub release links
- Fork IDs must be numeric

### Freshness Rules
- Components significantly behind latest releases generate warnings
- Age-based deprecation warnings for very old versions

## Integration with Development Workflow

### For Developers

1. **Version Updates**: Modify `input_parser.star` when updating component versions
2. **Test Scenarios**: Add new `.yml` files in `.github/tests/` for new scenarios
3. **Validation**: Run `./scripts/version-matrix/update-matrix.sh --validate-only` before commits

### For CI/CD

1. **Automated Checks**: Version validation runs on PR creation
2. **Daily Updates**: Matrix automatically updates with latest release information
3. **Change Detection**: Only commits when actual changes are detected

### For Documentation

1. **Single Source of Truth**: `CDK_VERSION_MATRIX.MD` provides authoritative version information
2. **Status Indicators**: Clear visual indicators for version status
3. **Source Links**: Direct links to component releases and repositories

## Troubleshooting

### Common Issues

1. **Missing Dependencies**
   ```bash
   pip install requests pyyaml
   ```

2. **GitHub API Rate Limits**
   - Set `GITHUB_TOKEN` environment variable
   - The system gracefully handles API failures

3. **Version Format Issues**
   - Ensure version strings follow semantic versioning
   - Check for typos in image tags

4. **Validation Failures**
   - Review validation output for specific issues
   - Check consensus type and fork ID consistency

### Debug Information

Enable verbose output:
```bash
export DEBUG=1
./scripts/version-matrix/update-matrix.sh
```

Check generated data:
```bash
# View extracted data
cat version-matrix.json | jq '.summary'

# Check specific component
cat version-matrix.json | jq '.default_components["CDK Erigon"]'
```

## Future Enhancements

Planned improvements include:

1. **Enhanced Status Detection**: More sophisticated rules for determining version status
2. **Release Notes Integration**: Automatic inclusion of release notes and changelogs
3. **Dependency Tracking**: Cross-component dependency validation
4. **Performance Metrics**: Track deployment success rates by version combination
5. **Custom Overrides**: Support for manual status overrides in special cases

## Contributing

To contribute to the version matrix system:

1. **Test Changes**: Always run validation before submitting PRs
2. **Update Documentation**: Keep this documentation current with changes
3. **Add Test Cases**: Include test scenarios for new component combinations
4. **Follow Patterns**: Maintain consistency with existing naming and structure

For questions or issues, please refer to the main Kurtosis CDK documentation or create an issue in the repository.