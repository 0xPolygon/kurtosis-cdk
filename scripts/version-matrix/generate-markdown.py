#!/usr/bin/env python3
"""
Generate updated CDK_VERSION_MATRIX.MD from extracted version data.

This script creates a comprehensive Markdown version matrix that includes:
1. Component compatibility matrix by fork
2. Test environment configurations
3. Version status indicators (stable, deprecated, experimental, pinned)
4. Links to source repositories and releases
"""

import json
from pathlib import Path
from typing import Dict
from dataclasses import dataclass


@dataclass
class MatrixEntry:
    """Represents an entry in the version matrix."""
    fork_id: str
    consensus: str
    components: Dict[str, str]
    sources: Dict[str, str]
    status: Dict[str, str]


class MarkdownMatrixGenerator:
    """Generates Markdown version matrix from extracted data."""

    def __init__(self, repo_root: Path):
        self.repo_root = repo_root
        self.matrix_json_path = repo_root / "scripts/version-matrix/matrix.json"
        self.output_path = repo_root / "docs/docs/version-matrix.md"

    def load_matrix_data(self) -> Dict:
        """Load the extracted version matrix data."""
        if not self.matrix_json_path.exists():
            raise FileNotFoundError(
                f"Matrix data not found at {self.matrix_json_path}")

        with open(self.matrix_json_path, 'r') as f:
            return json.load(f)

    def generate_markdown_report(self, data: Dict) -> str:
        """Generate markdown report from version matrix."""
        md = f"""---
sidebar_position: 3
---

# Version Matrix

> This document is automatically generated.
"""

        # Contents overview
        md += "\n## Contents\n\n"
        md += "- [Test Environments](#test-environments)\n"
        md += "- [Default Images](#default-images)\n"
        if data.get('packages'):
            md += "- [Kurtosis Packages](#kurtosis-packages)\n"
        md += "\n"

        # Test environments organized by execution client
        md += "## Test Environments\n\n"
        md += "This section lists all test environments with their configurations and component versions, organized by execution client.\n\n"

        test_environments = data.get('test_environments', {})
        
        # Categorize environments by execution client
        op_reth_envs = {}
        cdk_erigon_envs = {}
        
        for env_key, environment in test_environments.items():
            if 'cdk-opreth' in env_key:
                op_reth_envs[env_key] = environment
            elif 'cdk-erigon' in env_key:
                cdk_erigon_envs[env_key] = environment

        # Generate table of contents
        if op_reth_envs:
            md += "### CDK OP Reth\n\n"
            for env_key, environment in sorted(op_reth_envs.items()):
                environment_type = environment.get('type')
                md += f"- [{environment_type}](#{environment_type})\n"
            md += "\n"
        
        if cdk_erigon_envs:
            md += "### CDK Erigon\n\n"
            for env_key, environment in sorted(cdk_erigon_envs.items()):
                environment_type = environment.get('type')
                md += f"- [{environment_type}](#{environment_type})\n"
            md += "\n"

        # Generate CDK OP Reth section
        if op_reth_envs:
            md += "## CDK OP Reth\n\n"
            md += "Environments using [op-reth](https://github.com/ethereum-optimism/optimism/tree/develop/rust/op-reth) as the L2 execution client.\n\n"
            
            for env_key, environment in sorted(op_reth_envs.items()):
                environment_type = environment.get('type', 'unknown')
                config_file_path = environment.get('config_file_path', '')
                components = environment.get('components', {})

                md += f"### {environment_type}\n\n"
                md += f"- File path: `{config_file_path}`\n\n"
                md += self._generate_component_table(components)
                md += "\n"

        # Generate CDK Erigon section
        if cdk_erigon_envs:
            md += "## CDK Erigon\n\n"
            md += "Environments using [cdk-erigon](https://github.com/0xPolygon/cdk-erigon) as the L2 execution client.\n\n"
            
            for env_key, environment in sorted(cdk_erigon_envs.items()):
                environment_type = environment.get('type', 'unknown')
                config_file_path = environment.get('config_file_path', '')
                components = environment.get('components', {})

                md += f"### {environment_type}\n\n"
                md += f"- File path: `{config_file_path}`\n\n"
                md += self._generate_component_table(components)
                md += "\n"

        # Default images table
        md += "## Default Images\n\n"
        md += self._generate_component_table(data.get('default_images', {}))

        # External Kurtosis packages
        packages = data.get('packages', {})
        if packages:
            md += "\n## Kurtosis Packages\n\n"
            md += "External Kurtosis packages this package depends on. Versions are pinned "
            md += "in the [`replace` block of `kurtosis.yml`](https://github.com/0xPolygon/kurtosis-cdk/blob/main/kurtosis.yml), "
            md += "which is the single place to bump them.\n\n"
            md += self._generate_package_table(packages)

        return md

    def _generate_package_table(self, packages: Dict) -> str:
        """Generate the external Kurtosis packages table."""
        table = "| Package | Pinned Version | Latest Stable Version | Status |\n"
        table += "|---------|----------------|-----------------------|--------|\n"

        for package_name, package in sorted(packages.items()):
            pin = package.get('pin', 'N/A')
            pin_source_url = package.get('pin_source_url', '#')
            latest_version = package.get('latest_version', 'N/A')
            latest_version_source_url = package.get('latest_version_source_url', '#')
            status = package.get('status')
            commit_distance = package.get('commit_distance')
            pin_reason = package.get('pin_reason')

            status_emoji = {
                'newer than stable': '⚡️',
                'matches stable': '✅',
                'behind stable': '🚨',
                'pinned': '📌',
                'tracking head': '⚠️',
            }.get(status, '❓')

            status_display = f"{status_emoji} {status}" if status else 'N/A'
            if commit_distance:
                status_display += f" — {commit_distance}"
            if pin_reason:
                status_display += f" — {pin_reason}"

            # Commit pins are shortened to keep the column narrow; the status
            # column already reports how far a pin has drifted.
            pin_label = pin[:12] if len(pin) > 12 else pin
            pin_display = f"[{pin_label}]({pin_source_url})" if pin else 'N/A'

            # Head-tracked packages release too rarely for a tag to be a useful
            # baseline, so the comparison point is the branch tip. Say so rather
            # than presenting a bare sha as a "stable version".
            latest_label = latest_version
            if latest_version and package.get('tracking_mode') == 'head':
                latest_label = f"HEAD ({latest_version})"
            latest_display = (
                f"[{latest_label}]({latest_version_source_url})"
                if latest_version else 'N/A'
            )

            table += f"| [{package_name}](https://{package_name}) | {pin_display} | {latest_display} | {status_display} |\n"
        return table

    def _generate_component_table(self, components: Dict) -> str:
        """Generate a components table with header."""
        table = "| Component | Version Deployed in Kurtosis	 | Latest Stable Version | Status |\n"
        table += "|-----------|-------------------------------|-----------------------|--------|\n"

        for component_name, component in sorted(components.items()):
            version_deployed = component.get('version', 'N/A')
            version_deployed_source_url = component.get(
                'version_source_url', '#')
            latest_version = component.get('latest_version', 'N/A')
            latest_version_source_url = component.get(
                'latest_version_source_url', '#')
            status = component.get('status', 'N/A')
            pin_reason = component.get('pin_reason')

            # Format status with emoji
            status_emoji = {
                'newer than stable': '⚡️',
                'matches stable': '✅',
                'behind stable': '🚨',
                'pinned': '📌',
            }.get(status, '❓')

            status_display = f"{status_emoji} {status}" if status != 'N/A' and status is not None else 'N/A'
            if pin_reason:
                status_display += f" — {pin_reason}"
            version_deployed_display = f"[{version_deployed}]({version_deployed_source_url})" if version_deployed else 'N/A'
            latest_version_display = f"[{latest_version}]({latest_version_source_url})" if latest_version else 'N/A'

            table += f"| {component_name} | {version_deployed_display} | {latest_version_display} | {status_display} |\n"
        return table

    def save_markdown(self, content: str):
        """Save the generated Markdown content."""
        with open(self.output_path, 'w') as f:
            f.write(content)

        print(f"Updated version matrix saved to {self.output_path}")


def main():
    """Main execution function."""
    repo_root = Path(__file__).parent.parent.parent
    generator = MarkdownMatrixGenerator(repo_root)

    print("Loading matrix data...")
    data = generator.load_matrix_data()

    print("Generating Markdown content...")
    content = generator.generate_markdown_report(data)

    print("Saving updated matrix...")
    generator.save_markdown(content)

    print("Version matrix Markdown generated successfully!")


if __name__ == "__main__":
    main()
