#!/usr/bin/env python3
"""
Generate updated CDK_VERSION_MATRIX.MD from extracted version data.

This script creates a comprehensive Markdown version matrix that includes:
1. Component compatibility matrix by fork
2. Test environment configurations
3. Version status indicators (stable, deprecated, experimental, pinned)
4. Links to source repositories and releases
5. The L1 and OP Stack hard fork schedules
"""

import json
import re
from pathlib import Path
from typing import Dict, Optional
from dataclasses import dataclass

REPO_URL = "https://github.com/0xPolygon/kurtosis-cdk"

# Hard fork rows never use 🚨: the bump workflow acts on 🚨 rows, and a fork is
# not something to bump.
L1_EPOCH_URL = "https://beaconscan.com/epoch/{}"
SEPOLIA_EPOCH_URL = "https://beaconscan.com/sepolia/epoch/{}"

FORK_STATUSES = {
    "enabled": ("✅", "Activated by the devnet and known to the pinned clients."),
    "not enabled": ("💤", "Known to the pinned clients, but the devnet leaves it off."),
    "not supported yet": ("⏳", "Exposed by the package, but not known to a pinned client yet."),
    "enabled but unsupported": ("❌", "Configured by the devnet, but a pinned client does not know it and ignores the setting."),
    "op-deployer default": ("⚙️", "Left unset by the devnet, so op-deployer's standard schedule decides when it activates."),
}


@dataclass
class MatrixEntry:
    """Represents an entry in the version matrix."""
    fork_id: str
    consensus: str
    components: Dict[str, str]
    sources: Dict[str, str]
    status: Dict[str, str]


def _short_ref(ref: str) -> str:
    """Shorten commit SHAs like the package table does, but never a tag."""
    return ref[:12] if re.fullmatch(r"[0-9a-f]{40}", ref) else ref


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
        if data.get('hard_forks'):
            md += "- [Hard Forks](#hard-forks)\n"
        md += "\n"

        # Test environments organized by execution client
        md += "## Test Environments\n\n"
        md += "This section lists all test environments with their configurations and component versions, organized by execution client.\n\n"

        test_environments = data.get('test_environments', {})
        
        # Categorize environments by execution client
        op_reth_envs = {}
        cdk_erigon_envs = {}
        besu_envs = {}

        for env_key, environment in test_environments.items():
            if 'cdk-opreth' in env_key:
                op_reth_envs[env_key] = environment
            elif 'cdk-erigon' in env_key:
                cdk_erigon_envs[env_key] = environment
            elif 'cdk-besu' in env_key:
                besu_envs[env_key] = environment

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

        if besu_envs:
            md += "### CDK Besu\n\n"
            for env_key, environment in sorted(besu_envs.items()):
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

        # Generate CDK Besu section
        if besu_envs:
            md += "## CDK Besu\n\n"
            md += "Environments using [Besu](https://github.com/hyperledger/besu) as the L2 execution client.\n\n"

            for env_key, environment in sorted(besu_envs.items()):
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

        forks = data.get('hard_forks')
        if forks:
            md += self._generate_hard_forks(forks)

        return md

    @staticmethod
    def _newest_first(forks: list) -> list:
        """Latest activation first; a fork not scheduled yet comes before any scheduled one."""
        def key(fork):
            return tuple(
                float("inf") if fork.get(field) is None else fork[field]
                for field in ("mainnet", "testnet", "devnet")
            )
        return sorted(reversed(forks), key=key, reverse=True)

    def _generate_hard_forks(self, forks: Dict) -> str:
        md = "\n## Hard Forks\n\n"
        md += "Fork schedule of the devnet, checked against the source of the "
        md += "clients and packages at the versions pinned above. It only changes "
        md += "when a pin or the package config does, so a fork that is merely "
        md += "announced upstream never shows up as drift. These rows are "
        md += "informational and never bumped automatically.\n\n"
        md += "| Devnet status | Meaning |\n"
        md += "|--------|---------|\n"
        for status, (emoji, meaning) in FORK_STATUSES.items():
            md += f"| {emoji} {status} | {meaning} |\n"

        l1 = forks['l1']
        md += "\n### L1 (Ethereum)\n\n"
        md += "Fork epochs are the ethereum-package `minimal` preset defaults, "
        md += f"overridden in [`src/l1/ethereum.star`]({REPO_URL}/blob/main/src/l1/ethereum.star). "
        md = md.rstrip() + "\n\n"
        md += "| CL fork | EL fork | Devnet status | Devnet epoch | Sepolia epoch | Mainnet epoch |\n"
        md += "|------|---------|---------------|--------------|---------------|---------------|\n"
        scheduled = self._newest_first([f for f in l1['forks'] if not self._is_unscheduled(f)])
        for fork in scheduled:
            md += (
                f"| {fork['name']} | {fork.get('el_name') or '—'}"
                f" | {self._fork_status(fork)}"
                f" | {self._activation(fork['devnet'])} | {self._testnet(fork, SEPOLIA_EPOCH_URL)}"
                f" | {self._mainnet(fork, L1_EPOCH_URL)} |\n"
            )
        md += f"\n{self._sources(l1)}\n"
        md += self._unscheduled_note([f for f in l1['forks'] if self._is_unscheduled(f)])

        op = forks['op']
        md += "\n### L2 (OP Stack)\n\n"
        md += "Fork times are offsets in seconds from the L2 genesis: the "
        md += "optimism-package defaults, overridden in "
        md += f"[`src/package_io/op_input_parser.star`]({REPO_URL}/blob/main/src/package_io/op_input_parser.star). "
        md += "Forks before Fjord always activate at genesis. "
        md = md.rstrip() + "\n\n"
        md += "| Fork | Devnet status | Devnet offset (s) |\n"
        md += "|------|---------------|-------------------|\n"
        for fork in self._newest_first(op['forks']):
            md += (
                f"| {fork['name']} | {self._fork_status(fork)}"
                f" | {self._activation(fork['devnet'])} |\n"
            )
        md += f"\n{self._sources(op)}\n"
        return md

    @staticmethod
    def _sources(section: Dict) -> str:
        """Name the pinned versions a fork table was checked against."""
        links = [f"[{s['name']} {_short_ref(s['ref'])}]({s['url']})"
                 for s in section['sources']]
        return "Checked against:\n\n" + "\n".join(f"- {link}" for link in links)

    @staticmethod
    def _activation(value: Optional[int]) -> str:
        return "—" if value is None else str(value)

    @staticmethod
    def _is_unscheduled(fork: Dict) -> bool:
        return (fork.get('status') == 'not enabled'
                and fork.get('testnet') is None
                and fork.get('mainnet') is None)

    @classmethod
    def _unscheduled_note(cls, forks) -> str:
        if not forks:
            return ""
        items = ", ".join(f"`{f['name']}`" for f in forks)
        return f"\nNot enabled on devnet and not scheduled on testnet or mainnet: {items}.\n"

    @staticmethod
    def _testnet(fork: Dict, url: Optional[str] = None) -> str:
        if fork.get('testnet') is None:
            return "—"
        value = str(fork['testnet'])
        return f"[{value}]({url.format(value)})" if url else value

    @staticmethod
    def _mainnet(fork: Dict, url: Optional[str] = None) -> str:
        if fork.get('mainnet') is not None:
            value = str(fork['mainnet'])
            return f"[{value}]({url.format(value)})" if url else value
        return "—"

    @staticmethod
    def _fork_status(fork: Dict) -> str:
        status = fork.get('status')
        emoji = FORK_STATUSES.get(status, ('❓', None))[0]
        display = f"{emoji} {status}" if status else 'N/A'
        if fork.get('note'):
            display += f" — {fork['note']}"
        return display

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
                'ahead': '⚡️',
                'up to date': '✅',
                'behind': '🚨',
                'pinned': '📌',
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
                latest_label = f"HEAD ({latest_version[:12]})"
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
                'ahead': '⚡️',
                'up to date': '✅',
                'behind': '🚨',
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
