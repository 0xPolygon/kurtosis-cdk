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

        # Status icons
        self.status_icons = {
            "latest": "✅",
            "deprecated": "⚠️",
            "experimental": "🧪",
        }

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

        # Test environments organized by execution client
        md += "\n## Test Environments\n\n"
        md += "This section lists all test environments with their configurations and component versions, organized by execution client.\n\n"

        test_environments = data.get('test_environments', {})
        
        # Categorize environments by execution client
        op_geth_envs = {}
        cdk_erigon_envs = {}
        
        for env_key, environment in test_environments.items():
            if 'cdk-opgeth' in env_key:
                op_geth_envs[env_key] = environment
            elif 'cdk-erigon' in env_key:
                cdk_erigon_envs[env_key] = environment

        # Generate table of contents
        if op_geth_envs:
            md += "### CDK OP Geth\n\n"
            for env_key, environment in sorted(op_geth_envs.items()):
                environment_type = environment.get('type')
                md += f"- [{environment_type}](#{environment_type})\n"
            md += "\n"
        
        if cdk_erigon_envs:
            md += "### CDK Erigon\n\n"
            for env_key, environment in sorted(cdk_erigon_envs.items()):
                environment_type = environment.get('type')
                md += f"- [{environment_type}](#{environment_type})\n"
            md += "\n"

        # Generate CDK OP Geth section
        if op_geth_envs:
            md += "## CDK OP Geth\n\n"
            md += "Environments using [op-geth](https://github.com/ethereum-optimism/optimism) as the L2 execution client.\n\n"
            
            for env_key, environment in sorted(op_geth_envs.items()):
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

        return md

    def _generate_component_table(self, components: Dict) -> str:
        """Generate a components table with header."""
        table = "| Component | Current Version | Latest Version | Status |\n"
        table += "|-----------|-----------------|----------------|--------|\n"

        for component_name, component in sorted(components.items()):
            current_version = component.get('version', 'N/A')
            current_version_source_url = component.get(
                'version_source_url', '#')
            latest_version = component.get('latest_version', 'N/A')
            latest_version_source_url = component.get(
                'latest_version_source_url', '#')
            status = component.get('status', 'N/A')

            # Format status with emoji
            status_emoji = {
                'latest': '✅',
                'experimental': '🧪',
                'deprecated': '⚠️',
            }.get(status, '❓')

            status_display = f"{status} {status_emoji}" if status != 'N/A' and status is not None else 'N/A'
            current_version_display = f"[{current_version}]({current_version_source_url})" if current_version else 'N/A'
            latest_version_display = f"[{latest_version}]({latest_version_source_url})" if latest_version else 'N/A'

            table += f"| {component_name} | {current_version_display} | {latest_version_display} | {status_display} |\n"
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
