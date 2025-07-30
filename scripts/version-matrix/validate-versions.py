#!/usr/bin/env python3
"""
Validate version consistency across Kurtosis CDK configurations.

This script checks for:
1. Version mismatches between input_parser.star and test configurations
2. Deprecated or experimental versions in production scenarios
3. Missing version information
4. Fork compatibility issues
"""

import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Tuple, Set
from dataclasses import dataclass
from enum import Enum


class ValidationLevel(Enum):
    ERROR = "ERROR"
    WARNING = "WARNING" 
    INFO = "INFO"


@dataclass
class ValidationIssue:
    level: ValidationLevel
    message: str
    file_path: str
    component: str = ""
    line_number: int = 0


class VersionValidator:
    """Validates version consistency across CDK configurations."""
    
    def __init__(self, repo_root: Path):
        self.repo_root = repo_root
        self.matrix_json_path = repo_root / "version-matrix.json"
        self.issues: List[ValidationIssue] = []
        
        # Define critical components that must have stable versions
        self.critical_components = {
            "CDK Erigon",
            "ZkEVM Prover", 
            "Agglayer Contracts",
            "Data Availability"
        }
        
        # Define deprecated version patterns
        self.deprecated_patterns = [
            r"v?[0-4]\.",  # Very old versions
            r".*deprecated.*",
            r".*old.*"
        ]
        
        # Define experimental patterns
        self.experimental_patterns = [
            r".*alpha.*",
            r".*beta.*", 
            r".*rc\d*.*",
            r".*dev.*",
            r".*experimental.*"
        ]

    def load_matrix_data(self) -> Dict:
        """Load the version matrix data."""
        if not self.matrix_json_path.exists():
            self.add_issue(
                ValidationLevel.ERROR,
                "Version matrix data not found. Run extract-versions.py first.",
                str(self.matrix_json_path)
            )
            return {}
        
        try:
            with open(self.matrix_json_path, 'r') as f:
                return json.load(f)
        except Exception as e:
            self.add_issue(
                ValidationLevel.ERROR,
                f"Failed to load version matrix data: {e}",
                str(self.matrix_json_path)
            )
            return {}

    def add_issue(self, level: ValidationLevel, message: str, file_path: str, 
                  component: str = "", line_number: int = 0):
        """Add a validation issue."""
        self.issues.append(ValidationIssue(
            level=level,
            message=message,
            file_path=file_path,
            component=component,
            line_number=line_number
        ))

    def validate_component_versions(self, data: Dict):
        """Validate individual component versions."""
        default_components = data.get('default_components', {})
        
        for comp_name, comp_info in default_components.items():
            version = comp_info.get('version', '')
            status = comp_info.get('status', 'unknown')
            image = comp_info.get('image', '')
            
            # Check for missing version
            if not version or version == 'unknown':
                self.add_issue(
                    ValidationLevel.ERROR,
                    f"Missing version information for {comp_name}",
                    "input_parser.star",
                    comp_name
                )
                continue
            
            # Check for deprecated versions in critical components
            if comp_name in self.critical_components and status == 'deprecated':
                self.add_issue(
                    ValidationLevel.ERROR,
                    f"Critical component {comp_name} is using deprecated version {version}",
                    "input_parser.star",
                    comp_name
                )
            
            # Check for experimental versions in critical components
            if comp_name in self.critical_components and status == 'experimental':
                self.add_issue(
                    ValidationLevel.WARNING,
                    f"Critical component {comp_name} is using experimental version {version}",
                    "input_parser.star", 
                    comp_name
                )
            
            # Validate version format
            if not self._is_valid_version_format(version):
                self.add_issue(
                    ValidationLevel.WARNING,
                    f"Component {comp_name} has unusual version format: {version}",
                    "input_parser.star",
                    comp_name
                )
            
            # Check for very old versions
            if self._is_deprecated_version(version):
                self.add_issue(
                    ValidationLevel.WARNING,
                    f"Component {comp_name} may be using deprecated version: {version}",
                    "input_parser.star",
                    comp_name
                )

    def validate_test_scenario_consistency(self, data: Dict):
        """Validate consistency across test scenarios."""
        test_scenarios = data.get('test_scenarios', {})
        default_components = data.get('default_components', {})
        
        # Check for version mismatches between scenarios and defaults
        for scenario_name, scenario_data in test_scenarios.items():
            scenario_components = scenario_data.get('components', {})
            
            for comp_name, comp_info in scenario_components.items():
                if comp_name in default_components:
                    scenario_version = comp_info.get('version', '') if isinstance(comp_info, dict) else comp_info
                    default_version = default_components[comp_name].get('version', '')
                    
                    if scenario_version != default_version:
                        self.add_issue(
                            ValidationLevel.INFO,
                            f"Version mismatch in scenario '{scenario_name}': "
                            f"{comp_name} uses {scenario_version} vs default {default_version}",
                            f".github/tests/{scenario_name}.yml",
                            comp_name
                        )

    def validate_fork_compatibility(self, data: Dict): 
        """Validate fork compatibility configurations."""
        matrix_configs = data.get('matrix_configurations', {})
        supported_forks = data.get('summary', {}).get('supported_forks', [])
        
        # Check for missing fork configurations
        expected_forks = {'9', '11', '12', '13'}  # Known supported forks
        actual_forks = set(supported_forks)
        
        missing_forks = expected_forks - actual_forks
        if missing_forks:
            self.add_issue(
                ValidationLevel.WARNING,
                f"Missing fork configurations for: {', '.join(sorted(missing_forks))}",
                ".github/tests/matrix.yml"
            )
        
        # Check for invalid fork IDs
        for config_name, config_data in matrix_configs.items():
            if isinstance(config_data, dict):
                fork_id = str(config_data.get('fork_id', ''))
                if fork_id and not fork_id.isdigit():
                    self.add_issue(
                        ValidationLevel.ERROR,
                        f"Invalid fork ID '{fork_id}' in configuration '{config_name}'",
                        ".github/tests/matrix.yml"
                    )

    def validate_consensus_types(self, data: Dict):
        """Validate consensus type configurations."""
        test_scenarios = data.get('test_scenarios', {})
        valid_consensus_types = {'rollup', 'cdk_validium', 'pessimistic', 'ecdsa', 'fep'}
        
        for scenario_name, scenario_data in test_scenarios.items():
            consensus_type = scenario_data.get('consensus_type', '')
            
            if not consensus_type:
                self.add_issue(
                    ValidationLevel.WARNING,
                    f"Missing consensus type in scenario '{scenario_name}'",
                    f".github/tests/{scenario_name}.yml"
                )
            elif consensus_type not in valid_consensus_types:
                self.add_issue(
                    ValidationLevel.ERROR,
                    f"Invalid consensus type '{consensus_type}' in scenario '{scenario_name}'. "
                    f"Valid types: {', '.join(sorted(valid_consensus_types))}",
                    f".github/tests/{scenario_name}.yml"
                )

    def validate_source_urls(self, data: Dict):
        """Validate component source URLs."""
        default_components = data.get('default_components', {})
        
        for comp_name, comp_info in default_components.items():
            source_url = comp_info.get('source_url', '')
            version = comp_info.get('version', '')
            
            if not source_url and version not in ['latest', 'main', 'master']:
                self.add_issue(
                    ValidationLevel.INFO,
                    f"Missing source URL for {comp_name} version {version}",
                    "input_parser.star",
                    comp_name
                )
            elif source_url and not self._is_valid_url(source_url):
                self.add_issue(
                    ValidationLevel.WARNING,
                    f"Invalid source URL for {comp_name}: {source_url}",
                    "input_parser.star",
                    comp_name
                )

    def validate_version_freshness(self, data: Dict):
        """Validate that versions are reasonably fresh."""
        default_components = data.get('default_components', {})
        latest_releases = data.get('latest_releases', {})
        
        for comp_name, comp_info in default_components.items():
            current_version = comp_info.get('version', '')
            
            if comp_name in latest_releases:
                latest_version = latest_releases[comp_name].get('latest_version', '')
                
                if latest_version and current_version != latest_version.lstrip('v'):
                    # Check if current version is significantly behind
                    if self._is_version_significantly_behind(current_version, latest_version):
                        self.add_issue(
                            ValidationLevel.WARNING,
                            f"Component {comp_name} version {current_version} is behind "
                            f"latest release {latest_version}",
                            "input_parser.star",
                            comp_name
                        )

    def _is_valid_version_format(self, version: str) -> bool:
        """Check if version follows a valid format."""
        # Allow various common version formats
        patterns = [
            r'^v?\d+\.\d+\.\d+',  # Semantic versioning
            r'^v?\d+\.\d+',       # Major.minor
            r'^v?\d+',            # Major only
            r'^(latest|main|master)$',  # Special versions
        ]
        
        return any(re.match(pattern, version, re.IGNORECASE) for pattern in patterns)

    def _is_deprecated_version(self, version: str) -> bool:
        """Check if version appears to be deprecated."""
        return any(re.search(pattern, version, re.IGNORECASE) 
                  for pattern in self.deprecated_patterns)

    def _is_valid_url(self, url: str) -> bool:
        """Basic URL validation."""
        return url.startswith(('http://', 'https://')) and '.' in url

    def _is_version_significantly_behind(self, current: str, latest: str) -> bool:
        """Check if current version is significantly behind latest."""
        # Simple heuristic - compare major versions
        try:
            current_clean = re.sub(r'^v?', '', current)
            latest_clean = re.sub(r'^v?', '', latest)
            
            current_major = int(current_clean.split('.')[0])
            latest_major = int(latest_clean.split('.')[0])
            
            # Flag if major version is more than 1 behind
            return latest_major - current_major > 1
        except (ValueError, IndexError):
            return False

    def run_all_validations(self) -> List[ValidationIssue]:
        """Run all validation checks."""
        print("Loading version matrix data...")
        data = self.load_matrix_data()
        
        if not data:
            return self.issues
        
        print("Validating component versions...")
        self.validate_component_versions(data)
        
        print("Validating test scenario consistency...")
        self.validate_test_scenario_consistency(data)
        
        print("Validating fork compatibility...")
        self.validate_fork_compatibility(data)
        
        print("Validating consensus types...")
        self.validate_consensus_types(data)
        
        print("Validating source URLs...")
        self.validate_source_urls(data)
        
        print("Validating version freshness...")
        self.validate_version_freshness(data)
        
        return self.issues

    def print_results(self):
        """Print validation results."""
        if not self.issues:
            print("✅ All validation checks passed!")
            return True
        
        # Group issues by level
        errors = [issue for issue in self.issues if issue.level == ValidationLevel.ERROR]
        warnings = [issue for issue in self.issues if issue.level == ValidationLevel.WARNING]
        infos = [issue for issue in self.issues if issue.level == ValidationLevel.INFO]
        
        print(f"\n=== Validation Results ===")
        print(f"Total issues found: {len(self.issues)}")
        print(f"Errors: {len(errors)}, Warnings: {len(warnings)}, Info: {len(infos)}")
        
        # Print errors
        if errors:
            print(f"\n❌ ERRORS ({len(errors)}):")
            for issue in errors:
                print(f"  - {issue.file_path}: {issue.message}")
                if issue.component:
                    print(f"    Component: {issue.component}")
        
        # Print warnings
        if warnings:
            print(f"\n⚠️  WARNINGS ({len(warnings)}):")
            for issue in warnings:
                print(f"  - {issue.file_path}: {issue.message}")
                if issue.component:
                    print(f"    Component: {issue.component}")
        
        # Print info (only first 10 to avoid spam)
        if infos:
            print(f"\nℹ️  INFO ({len(infos)}):")
            for issue in infos[:10]:
                print(f"  - {issue.file_path}: {issue.message}")
                if issue.component:
                    print(f"    Component: {issue.component}")
            if len(infos) > 10:
                print(f"  ... and {len(infos) - 10} more info messages")
        
        return len(errors) == 0  # Return True if no errors


def main():
    """Main execution function."""
    repo_root = Path(__file__).parent.parent.parent
    validator = VersionValidator(repo_root)
    
    print("Starting version validation...")
    validator.run_all_validations()
    
    success = validator.print_results()
    
    # Exit with error code if validation failed
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()