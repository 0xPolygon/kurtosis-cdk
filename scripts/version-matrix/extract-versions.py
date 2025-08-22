#!/usr/bin/env python3
"""
Automated version matrix extraction tool for Kurtosis CDK.

This script automatically extracts version information from:
1. input_parser.star (DEFAULT_IMAGES)
2. .github/tests/ configurations
3. Git tags and releases from component repositories

It generates an updated version matrix with status indicators.
"""

import os
import re
import json
import yaml
import requests
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass, asdict
from datetime import datetime, timedelta


@dataclass
class ComponentVersion:
    """Represents a version of a component."""
    version: str
    image: str
    latest_version: Optional[str] = None
    version_source_url: Optional[str] = None
    latest_version_source_url: Optional[str] = None
    status: Optional[str] = None
    # last_updated: Optional[str] = None
    # fork_compatibility: Optional[List[str]] = None


@dataclass
class TestEnvironment:
    """Represents a test environment configuration."""
    type: str
    config_file_path: str
    components: Dict[str, ComponentVersion]


class VersionMatrixExtractor:
    """Extracts and manages version matrix information."""

    def __init__(self, repo_root: Path):
        self.repo_root = repo_root
        self.input_parser_path = repo_root / "input_parser.star"
        self.test_files_paths = [
            (repo_root / ".github" / "tests" / "chains" /
             "op-succinct.yml", "cdk-opgeth-zkrollup"),
            (repo_root / ".github" / "tests" / "nightly" /
             "op-rollup" / "op-default.yml", "cdk-opgeth-sovereign"),
            (repo_root / ".github" / "tests" / "combinations" /
             "fork12-cdk-erigon-rollup.yml", "cdk-erigon-zkrollup"),
            (repo_root / ".github" / "tests" / "combinations" /
             "fork12-cdk-erigon-validium.yml", "cdk-erigon-validium"),
            (repo_root / ".github" / "tests" / "combinations" /
             "fork12-cdk-erigon-sovereign.yml", "cdk-erigon-sovereign"),
            # (repo_root / ".github" / "tests" / "combinations" / "fork11-cdk-erigon-rollup.yml", "cdk-erigon-zkrollup"),
            # (repo_root / ".github" / "tests" / "combinations" / "fork11-cdk-erigon-validium.yml", "cdk-erigon-validium"),
            # (repo_root / ".github" / "tests" / "combinations" / "fork9-cdk-erigon-rollup.yml", "cdk-erigon-zkrollup"),
            # (repo_root / ".github" / "tests" / "combinations" / "fork9-cdk-erigon-validium.yml", "cdk-erigon-validium"),
        ]

        # Component mapping
        self.component_mapping = {
            "aggkit_image": "aggkit",
            "aggkit_prover_image": "aggkit-prover",
            "agglayer_image": "agglayer",
            "agglayer_contracts_image": "agglayer-contracts",
            "cdk_erigon_node_image": "cdk-erigon",
            "cdk_node_image": "cdk-node",
            # "cdk_validium_node_image": "cdk-validium-node",
            "geth_image": "geth",
            "lighthouse_image": "lighthouse",
            "op_batcher_image": "op-batcher",
            "op_contract_deployer_image": "op-deployer",
            "op_geth_image": "op-geth",
            "op_node_image": "op-node",
            "op_proposer_image": "op-proposer",
            "op_succinct_proposer_image": "op-succinct-proposer",
            "zkevm_da_image": "zkevm-da",
            "zkevm_bridge_service_image": "zkevm-bridge-service",
            # "zkevm_node_image": "zkevm-node",
            "zkevm_pool_manager_image": "zkevm-pool-manager",
            "zkevm_prover_image": "zkevm-prover",
            # "zkevm_sequence_sender_image": "zkevm-sequence-sender",
        }

        # GitHub repositories for version checking
        self.repos = {
            "aggkit": "agglayer/aggkit",
            "aggkit-prover": "agglayer/provers",
            "agglayer": "agglayer/agglayer",
            "agglayer-contracts": "agglayer/agglayer-contracts",
            "cdk-erigon": "0xPolygon/cdk-erigon",
            "cdk-node": "0xPolygon/cdk",
            # "cdk-validium-node": "0xPolygon/cdk-validium-node",
            "geth": "ethereum/go-ethereum",
            "lighthouse": "sigp/lighthouse",
            "op-batcher": "ethereum-optimism/optimism",
            "op-deployer": "ethereum-optimism/optimism",
            "op-geth": "ethereum-optimism/op-geth",
            "op-node": "ethereum-optimism/optimism",
            "op-proposer": "ethereum-optimism/optimism",
            "op-succinct-proposer": "agglayer/op-succinct",
            "zkevm-da": "0xPolygon/cdk-data-availability",
            "zkevm-bridge-service": "0xPolygon/zkevm-bridge-service",
            # "zkevm-node": "0xPolygon/zkevm-node",
            "zkevm-pool-manager": "0xPolygon/zkevm-pool-manager",
            "zkevm-prover": "0xPolygon/zkevm-prover",
            # "zkevm-sequence-sender": "0xPolygon/zkevm-sequence-sender", # TODO: Remove this component from kurtosis-cdk
        }

    def extract_default_images(self) -> Dict[str, ComponentVersion]:
        """Extract default image versions from input_parser.star."""
        components = {}

        try:
            with open(self.input_parser_path, 'r') as f:
                content = f.read()

            # Extract DEFAULT_IMAGES dictionary
            default_images_match = re.search(
                r'DEFAULT_IMAGES\s*=\s*\{(.*?)\}',
                content,
                re.DOTALL
            )

            if not default_images_match:
                raise ValueError(
                    "DEFAULT_IMAGES not found in input_parser.star")

            images_content = default_images_match.group(1)

            # Parse each image line
            for line in images_content.split('\n'):
                line = line.strip()
                if not line or line.startswith('#'):
                    continue

                match = re.search(r'"([^"]+)":\s*"([^"]+)"', line)
                if match:
                    key, image = match.groups()
                    if key in self.component_mapping:
                        name = self.component_mapping[key]
                        version = self._extract_version_from_image(image)
                        version_source_url = self._get_source_url(
                            name, version)
                        latest_version = self._get_latest_version(name)
                        latest_version_source_url = self._get_source_url(
                            name, latest_version)
                        status = self._determine_status(
                            version, latest_version)

                        components[name] = ComponentVersion(
                            version=version,
                            latest_version=latest_version,
                            image=image,
                            version_source_url=version_source_url,
                            latest_version_source_url=latest_version_source_url,
                            status=status,
                        )

        except Exception as e:
            print(f"Error extracting default images: {e}")

        return components

    def _extract_version_from_image(self, image: str) -> str:
        """Extract version from Docker image tag."""
        if ':' not in image:
            return "latest"

        tag = image.split(':')[-1]

        # Handle various tag formats
        if tag in ['latest', 'main', 'master']:
            return tag

        # Specific handling for agglayer-contracts images
        if 'agglayer-contracts' in image:
            tag = tag.split('-fork')[0]

        # Specific handling for zkevm-prover images
        if 'zkevm-prover' in image and tag.find('-fork.'):
            tag = tag.split('-fork.')[0]

        # Remove common prefixes
        version = re.sub(r'^v?', '', tag)
        return version

    def _get_source_url(self, name: str, version: str) -> Optional[str]:
        """Generate source URL for the component version."""
        # Map image to repository
        if not version:
            return None

        for comp_name, repo in self.repos.items():
            if comp_name.lower() == name.lower():
                if comp_name in ['op-batcher', 'op-deployer', 'op-node', 'op-proposer']:
                    return f"https://github.com/{repo}/releases/tag/{comp_name}/v{version.lstrip('v')}"

                if version not in ['latest', 'main', 'master']:
                    return f"https://github.com/{repo}/releases/tag/v{version.lstrip('v')}"
                else:
                    return f"https://github.com/{repo}/releases/latest"
        return None

    def _get_latest_version(self, component: str) -> Optional[str]:
        """Fetch the latest version from GitHub releases."""
        repo = self.repos.get(component)
        if not repo:
            return None

        try:
            if component in ['op-batcher', 'op-deployer', 'op-node', 'op-proposer']:
                url = f"https://api.github.com/repos/{repo}/releases"
                response = requests.get(url, timeout=10, headers={
                    'Authorization': f'token {os.getenv("GITHUB_TOKEN")}'})
                if response.status_code == 200:
                    releases = response.json()
                    for release in releases:
                        if 'tag_name' in release:
                            tag_name = release['tag_name']
                            if tag_name.startswith(component):
                                version = re.sub(
                                    r'^v?', '', tag_name.split("/")[-1])
                                return version
                return None

            url = f"https://api.github.com/repos/{repo}/releases/latest"
            response = requests.get(url, timeout=10, headers={
                                    'Authorization': f'token {os.getenv("GITHUB_TOKEN")}'})

            if response.status_code == 200:
                release_data = response.json()
                tag = release_data['tag_name']
                version = re.sub(r'^v?', '', tag)
                return version
            else:
                return None

        except Exception as e:
            print(f"Error fetching latest version for {component}: {e}")
            return None

    def _determine_status(self, version: str, latest_version: str) -> Optional[str]:
        """Determine the status of a version based on various factors."""
        # Check if version is unknown
        if not latest_version:
            return None

        # Helper function to convert version string to comparable integer
        def version_to_int(v):
            # Remove any non-digit prefix and split by dots
            clean_version = v.split('-')[0]  # Remove suffixes like "-beta1"
            parts = clean_version.split('.')

            # Pad with zeros if less parts available
            while len(parts) < 3:
                parts.append('0')

            try:
                # Convert to integer with larger multipliers to handle big numbers
                # 1000000 for major, 1000 for minor, 1 for patch
                major = int(parts[0]) if parts[0].isdigit() else 0
                minor = int(parts[1]) if parts[1].isdigit() else 0
                patch = int(parts[2]) if parts[2].isdigit() else 0
                return major * 1000000 + minor * 1000 + patch
            except (ValueError, IndexError):
                return 0

        # Check if version is greater than latest (e.g., pre-release)
        try:
            version_float = version_to_int(version)
            version_suffix = version.split('-')[1] if '-' in version else ''
            latest_float = version_to_int(latest_version)
            latest_suffix = latest_version.split('-')[1] if '-' in latest_version else ''

            if version_float > latest_float:
                return "experimental"
            elif version_float < latest_float:
                return "deprecated"
            else:
                if version_suffix == latest_suffix:
                    return "latest"
                return "experimental"

        except Exception as e:
            print(f"Error determining status for version {version}: {e}")
            return "unknown"

    def extract_test_environments(self, default_images: Dict[str, str]) -> Dict[str, TestEnvironment]:
        """Extract test environments from .github/tests/ configurations."""
        environments = {}

        try:
            # Walk through test configuration files
            for (yaml_file, environment_type) in self.test_files_paths:
                try:
                    with open(yaml_file, 'r') as f:
                        config = yaml.safe_load(f)

                    if not config:
                        continue

                    environment_name = yaml_file.stem
                    environment_file_path = yaml_file.relative_to(
                        self.repo_root)

                    # Extract environment information
                    args = config.get('args', {})

                    # Extract component versions from the config
                    components = self._extract_components_from_config(args)
                    components_with_defaults = {
                        name: comp for name, comp in components.items()
                    }
                    components_with_defaults.update({
                        name: comp for name, comp in default_images.items()
                        if name not in components
                    })

                    # Filter components based on environment type
                    allowed_components = self._get_allowed_components(
                        environment_type)
                    filtered_components = {
                        name: comp for name, comp in components_with_defaults.items()
                        if name in allowed_components
                    }

                    environments[environment_name] = TestEnvironment(
                        type=environment_type,
                        config_file_path=str(environment_file_path),
                        components=filtered_components,
                    )

                except Exception as e:
                    print(f"Error processing {yaml_file}: {e}")
                    continue

        except Exception as e:
            print(f"Error scanning test environments: {e}")

        return environments

    def _get_allowed_components(self, environment_name: str) -> List[str]:
        """Get list of components allowed for a environment type."""

        environment_components = {
            "cdk-erigon-zkrollup": [
                'aggkit-prover',
                'agglayer',
                'agglayer-contracts',
                'cdk-erigon',
                'cdk-node',
                'zkevm-bridge-service',
                'zkevm-pool-manager',
                'zkevm-prover',
            ],
            "cdk-erigon-validium": [
                'aggkit-prover',
                'agglayer',
                'agglayer-contracts',
                'cdk-erigon',
                # TODO: Check if we should use cdk-validium-node instead.
                'cdk-node',
                # 'cdk-validium-node',  # different from cdk-erigon-zkrollup
                'zkevm-bridge-service',
                'zkevm-da',  # different from cdk-erigon-zkrollup
                'zkevm-pool-manager',
                'zkevm-prover',
            ],
            "cdk-erigon-sovereign": [
                'aggkit-prover',
                'aggkit',  # different from cdk-erigon-zkrollup and cdk-erigon-validium
                'agglayer',
                'agglayer-contracts',
                'cdk-erigon',
                'zkevm-bridge-service',
                'zkevm-pool-manager',
            ],
            "cdk-opgeth-zkrollup": [
                'aggkit',
                'aggkit-prover',
                'agglayer',
                'agglayer-contracts',
                'op-batcher',
                'op-deployer',
                'op-node',
                'op-geth',
                'op-succinct-proposer',
                'zkevm-bridge-service',
            ],
            "cdk-opgeth-sovereign": [
                'aggkit',
                'aggkit-prover',
                'agglayer',
                'agglayer-contracts',
                'op-batcher',
                'op-deployer',
                'op-node',
                'op-geth',
                'op-proposer',  # different from cdk-opgeth-zkrollup
                'zkevm-bridge-service',
            ]
        }

        # Find the matching environment pattern
        for pattern, components in environment_components.items():
            if environment_name == pattern:
                return components

        # If no pattern matches, return an empty list
        return []

    def _extract_components_from_config(self, args: dict) -> Dict[str, ComponentVersion]:
        """Extract component versions from test configuration args."""
        components = {}

        for key, value in args.items():
            if key.endswith('_image') and key in self.component_mapping:
                name = self.component_mapping[key]
                version = self._extract_version_from_image(value)
                version_source_url = self._get_source_url(name, version)
                latest_version = self._get_latest_version(name)
                latest_version_source_url = self._get_source_url(
                    name, latest_version)

                components[name] = ComponentVersion(
                    image=value,
                    version=version,
                    version_source_url=version_source_url,
                    latest_version=latest_version,
                    latest_version_source_url=latest_version_source_url,
                    status=self._determine_status(version, latest_version)
                )

        return components

    def generate_version_matrix(self) -> Dict:
        """Generate comprehensive version matrix."""
        print("Extracting default images...")
        default_images = self.extract_default_images()

        print("Extracting test environments...")
        test_environments = self.extract_test_environments(default_images)

        # Count environments by type
        environment_counts = {
            'total': len(test_environments)
        }
        for environment in test_environments.values():
            architecture = 'unknown'
            if environment.type.startswith('cdk-opgeth'):
                architecture = 'cdk-opgeth'
            elif environment.type.startswith('cdk-erigon'):
                architecture = 'cdk-erigon'

            environment_counts[architecture] = environment_counts.get(
                architecture, 0) + 1

        # Build comprehensive matrix
        matrix = {
            'generated_at': datetime.now().isoformat(),
            'default_images': {name: asdict(comp) for name, comp in default_images.items()},
            'test_environments': {name: asdict(environment) for name, environment in test_environments.items()},
            'summary': {
                'total_components': len(default_images),
                'environments': environment_counts,
            }
        }

        return matrix

    def save_matrix_json(self, matrix: Dict, output_path: Optional[Path] = None):
        """Save matrix as JSON file."""
        if output_path is None:
            output_path = f"{self.repo_root}/scripts/version-matrix/matrix.json"

        with open(output_path, 'w') as f:
            json.dump(matrix, f, indent=2, sort_keys=True)

        print(f"Version matrix saved to {output_path}")


def main():
    """Main execution function."""
    # Check if GITHUB_TOKEN is set
    if not os.getenv('GITHUB_TOKEN'):
        print("Error: GITHUB_TOKEN environment variable is not set.")
        print("Please set it to access GitHub API for version information.")
        exit(1)

    repo_root = Path(__file__).parent.parent.parent
    extractor = VersionMatrixExtractor(repo_root)

    print("Starting version matrix extraction...")
    matrix = extractor.generate_version_matrix()
    extractor.save_matrix_json(matrix)

    # Print summary
    summary = matrix['summary']
    print(f"\n=== Version Matrix Summary ===")
    print(f"Total Components: {summary['total_components']}")
    print(f"Total Test environments: {summary['environments']['total']}")
    print(f"Matrix generated at: {matrix['generated_at']}")


if __name__ == "__main__":
    main()
