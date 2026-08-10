#!/usr/bin/env python3
"""
Automated version matrix extraction tool for Kurtosis CDK.

This script automatically extracts version information from:
1. constants.star (DEFAULT_IMAGES)
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
from typing import Dict, List, Optional
from dataclasses import dataclass, asdict, replace
from datetime import datetime


@dataclass
class ComponentVersion:
    """Represents a version of a component."""
    version: str
    image: str
    latest_version: Optional[str] = None
    version_source_url: Optional[str] = None
    latest_version_source_url: Optional[str] = None
    status: Optional[str] = None
    pin_reason: Optional[str] = None


# Components deliberately held back from the latest stable release, keyed by
# (environment, component). These render as "pinned" instead of "behind stable"
# so that genuine regressions stay visible in the matrix.
#
# Keep every reason in the same short form: "Only supports <component> <line> so far."
PINNED_VERSIONS = {
    ("cdk-erigon-sovereign-pessimistic", "aggkit"): "Only supports aggkit 0.5.x so far.",
    ("cdk-opreth-sovereign-pessimistic", "aggkit"): "Only supports aggkit 0.5.x so far.",
    ("cdk-erigon-validium", "cdk-erigon"): "Only supports cdk-erigon 2.61.x so far.",
    ("cdk-erigon-zkrollup", "cdk-erigon"): "Only supports cdk-erigon 2.61.x so far.",
    ("cdk-opreth-zkrollup", "op-succinct-proposer"): "Only supports op-succinct 3.10.x so far.",
}


@dataclass
class TestEnvironment:
    """Represents a test environment configuration."""
    type: str
    config_file_path: str
    components: Dict[str, ComponentVersion]


@dataclass
class PackageVersion:
    """Represents a pinned external Kurtosis package dependency."""
    pin: str
    pin_date: Optional[str] = None
    pin_source_url: Optional[str] = None
    latest_version: Optional[str] = None
    latest_version_date: Optional[str] = None
    latest_version_source_url: Optional[str] = None
    status: Optional[str] = None
    commit_distance: Optional[str] = None
    tracking_mode: str = "release"
    pin_reason: Optional[str] = None


# External Kurtosis packages deliberately held back, keyed by package locator.
# Same convention as PINNED_VERSIONS: these render as "pinned" rather than
# "behind stable" so real drift stays visible.
PINNED_PACKAGES = {}

# What "latest" means for each package, keyed by package locator.
#
# - "release" (default): compare the pin against the latest release/tag. Right
#   for packages that tag every change worth consuming.
# - "head": compare the pin against the default branch HEAD. Right for packages
#   that release rarely and expect consumers to pin commits — ethereum-package
#   last tagged 6.1.0 in April 2026 while continuing to ship daily, so measuring
#   against that tag reports "newer than stable" forever and hides real drift.
PACKAGE_TRACKING_MODE = {
    "github.com/ethpandaops/ethereum-package": "head",
    # Has never cut a release or tag, so HEAD is the only comparison point.
    "github.com/xavier-romero/kurtosis-blockscout": "head",
}

# A head-tracked pin is always behind HEAD on an active upstream, so distance
# alone is not a signal. Alarm once the pin is old enough that we are plausibly
# missing fixes: these packages ship most days, so two weeks is already a
# meaningful gap.
HEAD_TRACKING_STALE_AFTER_DAYS = 14


class VersionMatrixExtractor:
    """Extracts and manages version matrix information."""

    def __init__(self, repo_root: Path):
        self.repo_root = repo_root
        self.constants_path = repo_root / "src" / "package_io" / "constants.star"
        self.kurtosis_yaml_path = repo_root / "kurtosis.yml"

        cdk_erigon_tests_path = repo_root / ".github" / "tests" / "cdk-erigon"
        op_reth_tests_path = repo_root / ".github" / "tests" / "op-reth"
        op_succinct_tests_path = repo_root / ".github" / "tests" / "op-succinct"
        self.test_files_paths = [
            # cdk-erigon
            ("cdk-erigon-zkrollup", cdk_erigon_tests_path / "rollup.yml"),
            ("cdk-erigon-validium", cdk_erigon_tests_path / "validium.yml"),
            ("cdk-erigon-sovereign-pessimistic", cdk_erigon_tests_path / "sovereign-pessimistic.yml"),
            ("cdk-erigon-sovereign-ecdsa-multisig", cdk_erigon_tests_path / "sovereign-ecdsa-multisig.yml"),
            # op-reth
            ("cdk-opreth-sovereign-pessimistic", op_reth_tests_path / "sovereign-pessimistic.yml"),
            ("cdk-opreth-sovereign-ecdsa-multisig", op_reth_tests_path / "sovereign-ecdsa-multisig.yml"),
            ("cdk-opreth-zkrollup", op_succinct_tests_path / "mock-prover.yml"),
        ]

        # Component mapping
        self.component_mapping = {
            "aggkit_image": "aggkit",
            "aggkit_prover_image": "aggkit-prover",
            "agglayer_image": "agglayer",
            "agglayer_contracts_image": "agglayer-contracts",
            "cdk_erigon_image": "cdk-erigon",
            "cdk_node_image": "cdk-node",
            "status_checker_image": "status-checker",
            "geth_image": "geth",
            "reth_image": "reth",
            "lighthouse_image": "lighthouse",
            "op_batcher_image": "op-batcher",
            "op_contract_deployer_image": "op-deployer",
            "op_reth_image": "op-reth",
            "op_node_image": "op-node",
            "op_proposer_image": "op-proposer",
            "op_succinct_proposer_image": "op-succinct-proposer",
            "cdk_data_availability_image": "cdk-data-availability",
            "zkevm_bridge_service_image": "zkevm-bridge-service",
            "zkevm_pool_manager_image": "zkevm-pool-manager",
            "zkevm_prover_image": "zkevm-prover",
        }

        # Components that should be excluded from default images since they're covered in test environments
        self.cdk_core_components = {
            "aggkit",
            "aggkit-prover", 
            "agglayer",
            "agglayer-contracts",
            "cdk-erigon",
            "cdk-node",
            "op-batcher",
            "op-deployer", 
            "op-reth",
            "op-node",
            "op-proposer",
            "op-succinct-proposer",
            "zkevm-bridge-service",
            "cdk-data-availability",
            "zkevm-pool-manager",
            "zkevm-prover"
        }

        # GitHub repositories for version checking
        self.repos = {
            # polygon cdk components
            "aggkit": "agglayer/aggkit",
            "aggkit-prover": "agglayer/provers",
            "agglayer": "agglayer/agglayer",
            "agglayer-contracts": "agglayer/agglayer-contracts",
            "cdk-erigon": "0xPolygon/cdk-erigon",
            "cdk-node": "0xPolygon/cdk",
            "status-checker": "0xPolygon/status-checker",
            # legacy zkevm components
            "cdk-data-availability": "0xPolygon/cdk-data-availability",
            "zkevm-bridge-service": "0xPolygon/zkevm-bridge-service",
            "zkevm-pool-manager": "0xPolygon/zkevm-pool-manager",
            "zkevm-prover": "0xPolygon/zkevm-prover",
            # optimism components
            "op-batcher": "ethereum-optimism/optimism",
            "op-deployer": "ethereum-optimism/optimism",
            "op-reth": "ethereum-optimism/optimism",
            "op-node": "ethereum-optimism/optimism",
            "op-proposer": "ethereum-optimism/optimism",
            # succinct components
            "op-succinct-proposer": "agglayer/op-succinct",
            # ethereum components
            "geth": "ethereum/go-ethereum",
            "reth": "paradigmxyz/reth",
            "lighthouse": "sigp/lighthouse",
        }

    def extract_default_images(self) -> Dict[str, ComponentVersion]:
        """Extract default image versions from constants.star."""
        components = {}

        try:
            with open(self.constants_path, 'r') as f:
                content = f.read()

            # Extract DEFAULT_IMAGES dictionary
            default_images_match = re.search(
                r'DEFAULT_IMAGES\s*=\s*\{(.*?)\}',
                content,
                re.DOTALL
            )

            if not default_images_match:
                raise ValueError(
                    "DEFAULT_IMAGES not found in constants.star")

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

    def filter_default_images(self, default_images: Dict[str, ComponentVersion]) -> Dict[str, ComponentVersion]:
        return {
            name: component for name, component in default_images.items()
            if name not in self.cdk_core_components
        }

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
        
        # Specific handling for op-deployer images
        if 'op-deployer' in image and tag.find('-cdk'):
            tag = tag.split('-cdk')[0]

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
                if comp_name == 'agglayer' and version == '0.4.4-remove-agglayer-prover':
                    return f"https://github.com/{repo}/tree/38ffe04e71bb6b0eb22a244dbd40d189e1b0d78f"

                if comp_name in ['op-batcher', 'op-deployer', 'op-node', 'op-proposer', 'op-reth']:
                    return f"https://github.com/{repo}/releases/tag/{comp_name}/v{version.lstrip('v')}"

                if version not in ['latest', 'main', 'master']:
                    return f"https://github.com/{repo}/releases/tag/v{version.lstrip('v')}"
                else:
                    return f"https://github.com/{repo}/releases/latest"
        return None

    @staticmethod
    def _is_prerelease(tag_name: str) -> bool:
        """Whether a tag looks like a prerelease rather than a stable version.

        Covers the usual alpha/beta/rc markers plus test builds such as
        op-deployer's "0.8.0-pcd-test.2", which must never be reported as stable.
        """
        return re.search(r'-(alpha|beta|rc|test)', tag_name, re.IGNORECASE) is not None

    def _get_latest_version(self, component: str) -> Optional[str]:
        """Fetch the latest version from GitHub releases."""
        repo = self.repos.get(component)
        if not repo:
            return None

        try:
            if component in ['op-batcher', 'op-deployer', 'op-node', 'op-proposer', 'op-reth']:
                url = f"https://api.github.com/repos/{repo}/releases?per_page=100"
                response = requests.get(url, timeout=10, headers={
                    'Authorization': f'token {os.getenv("GITHUB_TOKEN")}'})

                if response.status_code == 200:
                    releases = response.json()
                    for release in releases:
                        if 'tag_name' in release:
                            tag_name = release['tag_name']
                            if tag_name.startswith(component):
                                # Skip prereleases when picking latest stable
                                if self._is_prerelease(tag_name):
                                    continue
                                version = re.sub(
                                    r'^v?', '', tag_name.split("/")[-1])
                                return version
                else:
                    print(f"Error fetching latest version for {component}: {response.status_code} from {url}")
                    return None

            # These components don't have any release, thus we rely on tags
            if component in [
                'zkevm-prover', 'zkevm-bridge-service', 'op-succinct-proposer',
                'zkevm-pool-manager', 'cdk-data-availability'
            ]:
                url = f"https://api.github.com/repos/{repo}/tags"
                response = requests.get(
                    url, timeout=10,
                    headers={'Authorization': f'token {os.getenv("GITHUB_TOKEN")}'}
                )
                if response.status_code == 200:
                    tags = response.json()
                    for tag in tags:
                        if 'name' in tag:
                            tag_name = tag['name']

                            # Don't consider v9 tags for zkevm-prover
                            if component == 'zkevm-prover' and tag_name.startswith('v9'):
                                continue

                            # Skip prereleases when picking latest stable
                            if self._is_prerelease(tag_name):
                                continue

                            latest_version = re.sub(r'^v?', '', tag_name)
                            return latest_version
                else:
                    print(f"Error fetching latest version for {component}: {response.status_code} from {url}")
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
                print(f"Error fetching latest version for {component}: {response.status_code} from {url}")
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

            # special case for agglayer-contracts
            experimental_status = "newer than stable"
            stable_status = "matches stable"
            deprecated_status = "behind stable"
            
            if version_suffix.endswith("aggchain.multisig"):
                return experimental_status

            if version_float > latest_float:
                return experimental_status
            elif version_float < latest_float:
                return deprecated_status
            else:
                if version_suffix == latest_suffix:
                    return stable_status
                # special case for op-deployer - we use the latest version with a small fix on top, suffixed with `-cdk`
                if version_suffix == "cdk" and not latest_suffix:
                    return stable_status
                # special case for op-succinct-proposer - we use the latest version with a small fix on top, suffixed with `-agglayer`
                if version_suffix == "agglayer" and not latest_suffix:
                    return stable_status

                return experimental_status

        except Exception as e:
            print(f"Error determining status for version {version}: {e}")
            return "unknown"

    def extract_test_environments(self, default_images: Dict[str, str]) -> Dict[str, TestEnvironment]:
        """Extract test environments from .github/tests/ configurations."""
        environments = {}

        try:
            # Walk through test configuration files
            for (environment_type, yaml_file) in self.test_files_paths:
                try:
                    with open(yaml_file, 'r') as f:
                        config = yaml.safe_load(f)

                    if not config:
                        continue

                    environment_file_path = yaml_file.relative_to(
                        self.repo_root)

                    # Extract environment information
                    args = config.get('args', {})

                    # Extract component versions from the config
                    components = self._extract_components_from_config(args)
                    
                    # Also extract OP components from optimism_package section
                    op_components = self._extract_op_components_from_config(config)
                    components.update(op_components)
                    
                    components_with_defaults = {
                        name: comp for name, comp in components.items()
                    }
                    # Copy inherited defaults so per-environment adjustments
                    # (e.g. pinning) don't leak into other environments.
                    components_with_defaults.update({
                        name: replace(comp)
                        for name, comp in default_images.items()
                        if name not in components
                    })

                    # Filter components based on environment type
                    allowed_components = self._get_allowed_components(
                        environment_type)
                    filtered_components = {
                        name: comp for name, comp in components_with_defaults.items()
                        if name in allowed_components
                    }

                    self._apply_pins(environment_type, filtered_components)

                    environments[environment_type] = TestEnvironment(
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

    def _apply_pins(self, environment_name: str, components: Dict[str, ComponentVersion]):
        """Re-label deliberately held-back components as pinned.

        Only downgrades a "behind stable" status: if a pinned component ever
        catches up with (or overtakes) stable, the real status is kept so that
        the pin can be retired.
        """
        for name, component in components.items():
            reason = PINNED_VERSIONS.get((environment_name, name))
            if reason and component.status == "behind stable":
                component.status = "pinned"
                component.pin_reason = reason

    def _get_allowed_components(self, environment_name: str) -> List[str]:
        """Get list of components allowed for a environment type."""

        environment_components = {
            # cdk-erigon
            "cdk-erigon-zkrollup": [
                'agglayer',
                'agglayer-contracts',
                'cdk-erigon',
                'cdk-node',
                'zkevm-bridge-service',
                'zkevm-pool-manager',
                'zkevm-prover',
            ],
            "cdk-erigon-validium": [
                'agglayer',
                'agglayer-contracts',
                'cdk-erigon',
                # TODO: Check if we should use cdk-validium-node instead.
                'cdk-node',
                # 'cdk-validium-node',  # different from cdk-erigon-zkrollup
                'zkevm-bridge-service',
                'cdk-data-availability',  # specific to validium
                'zkevm-pool-manager',
                'zkevm-prover',
            ],
            "cdk-erigon-sovereign-pessimistic": [
                'aggkit',  # different from cdk-erigon-zkrollup and cdk-erigon-validium
                'agglayer',
                'agglayer-contracts',
                'cdk-erigon',
                'zkevm-bridge-service',
                'zkevm-pool-manager',
            ],
            "cdk-erigon-sovereign-ecdsa-multisig": [
                'aggkit',
                'agglayer',
                'agglayer-contracts',
                'cdk-erigon',
                'zkevm-bridge-service',
                'zkevm-pool-manager',
            ],
            # cdk-opreth
            "cdk-opreth-sovereign-pessimistic": [
                'aggkit',
                'agglayer',
                'agglayer-contracts',
                'op-batcher',
                'op-deployer',
                'op-node',
                'op-reth',
                'op-proposer',
                'zkevm-bridge-service',
            ],
            "cdk-opreth-sovereign-ecdsa-multisig": [
                'aggkit',
                'agglayer',
                'agglayer-contracts',
                'op-batcher',
                'op-deployer',
                'op-node',
                'op-reth',
                'op-proposer',
                'zkevm-bridge-service',
            ],
            "cdk-opreth-zkrollup": [
                'aggkit',
                'aggkit-prover',
                'agglayer',
                'agglayer-contracts',
                'op-batcher',
                'op-deployer',
                'op-node',
                'op-reth',
                'op-succinct-proposer',  # different from cdk-opreth-sovereign
                'zkevm-bridge-service',
            ],
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

        # Extract from direct args (e.g., aggkit_image, etc.)
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

    def _extract_op_components_from_config(self, config: dict) -> Dict[str, ComponentVersion]:
        """Extract OP component versions from optimism_package configuration."""
        components = {}
        
        optimism_package = config.get('optimism_package', {})
        if not optimism_package:
            return components
        
        # Extract from chains configuration
        chains = optimism_package.get('chains', {})
        for chain_id, chain_config in chains.items():
            if not isinstance(chain_config, dict):
                continue
                
            # Extract from participants (op-node and op-reth)
            participants = chain_config.get('participants', {})
            for participant_name, participant_config in participants.items():
                if not isinstance(participant_config, dict):
                    continue
                    
                # Extract op-reth from el (execution layer)
                el_config = participant_config.get('el', {})
                if isinstance(el_config, dict) and 'image' in el_config:
                    image = el_config['image']
                    if 'op-reth' in image:
                        name = 'op-reth'
                        version = self._extract_version_from_image(image)
                        version_source_url = self._get_source_url(name, version)
                        latest_version = self._get_latest_version(name)
                        latest_version_source_url = self._get_source_url(name, latest_version)
                        
                        components[name] = ComponentVersion(
                            image=image,
                            version=version,
                            version_source_url=version_source_url,
                            latest_version=latest_version,
                            latest_version_source_url=latest_version_source_url,
                            status=self._determine_status(version, latest_version)
                        )
                
                # Extract op-node from cl (consensus layer)
                cl_config = participant_config.get('cl', {})
                if isinstance(cl_config, dict) and 'image' in cl_config:
                    image = cl_config['image']
                    if 'op-node' in image:
                        name = 'op-node'
                        version = self._extract_version_from_image(image)
                        version_source_url = self._get_source_url(name, version)
                        latest_version = self._get_latest_version(name)
                        latest_version_source_url = self._get_source_url(name, latest_version)
                        
                        components[name] = ComponentVersion(
                            image=image,
                            version=version,
                            version_source_url=version_source_url,
                            latest_version=latest_version,
                            latest_version_source_url=latest_version_source_url,
                            status=self._determine_status(version, latest_version)
                        )
            
            # Extract from batcher_params
            batcher_params = chain_config.get('batcher_params', {})
            if isinstance(batcher_params, dict) and 'image' in batcher_params:
                image = batcher_params['image']
                if 'op-batcher' in image:
                    name = 'op-batcher'
                    version = self._extract_version_from_image(image)
                    version_source_url = self._get_source_url(name, version)
                    latest_version = self._get_latest_version(name)
                    latest_version_source_url = self._get_source_url(name, latest_version)
                    
                    components[name] = ComponentVersion(
                        image=image,
                        version=version,
                        version_source_url=version_source_url,
                        latest_version=latest_version,
                        latest_version_source_url=latest_version_source_url,
                        status=self._determine_status(version, latest_version)
                    )
            
            # Extract from proposer_params
            proposer_params = chain_config.get('proposer_params', {})
            if isinstance(proposer_params, dict) and 'image' in proposer_params:
                image = proposer_params['image']
                if 'op-proposer' in image:
                    name = 'op-proposer'
                    version = self._extract_version_from_image(image)
                    version_source_url = self._get_source_url(name, version)
                    latest_version = self._get_latest_version(name)
                    latest_version_source_url = self._get_source_url(name, latest_version)
                    
                    components[name] = ComponentVersion(
                        image=image,
                        version=version,
                        version_source_url=version_source_url,
                        latest_version=latest_version,
                        latest_version_source_url=latest_version_source_url,
                        status=self._determine_status(version, latest_version)
                    )
        
        # Extract from top-level optimism_package configurations
        # Check for direct image specifications
        for key, value in optimism_package.items():
            if isinstance(value, str) and key.endswith('_image') and key in self.component_mapping:
                name = self.component_mapping[key]
                version = self._extract_version_from_image(value)
                version_source_url = self._get_source_url(name, version)
                latest_version = self._get_latest_version(name)
                latest_version_source_url = self._get_source_url(name, latest_version)
                
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
        filtered_default_images = self.filter_default_images(default_images)

        print("Extracting test environments...")
        test_environments = self.extract_test_environments(default_images)

        print("Extracting external Kurtosis packages...")
        packages = self.extract_packages()

        # Count environments by type
        environment_counts = {
            'total': len(test_environments)
        }
        for environment in test_environments.values():
            architecture = 'unknown'
            if environment.type.startswith('cdk-opreth'):
                architecture = 'cdk-opreth'
            elif environment.type.startswith('cdk-erigon'):
                architecture = 'cdk-erigon'

            environment_counts[architecture] = environment_counts.get(
                architecture, 0) + 1

        # Build comprehensive matrix
        matrix = {
            'generated_at': datetime.now().isoformat(),
            'default_images': {name: asdict(comp) for name, comp in filtered_default_images.items()},
            'test_environments': {name: asdict(environment) for name, environment in test_environments.items()},
            'packages': {name: asdict(package) for name, package in packages.items()},
            'summary': {
                'total_components': len(default_images),
                'total_packages': len(packages),
                'environments': environment_counts,
            }
        }

        return matrix

    def extract_packages(self) -> Dict[str, PackageVersion]:
        """Extract external Kurtosis package pins from the kurtosis.yml replace block."""
        packages = {}

        try:
            with open(self.kurtosis_yaml_path, 'r') as f:
                kurtosis_yaml = yaml.safe_load(f)
        except Exception as e:
            print(f"Error reading {self.kurtosis_yaml_path}: {e}")
            return packages

        replace_options = (kurtosis_yaml or {}).get('replace') or {}
        if not replace_options:
            print("No `replace` block found in kurtosis.yml, skipping packages.")
            return packages

        for package_locator, replacement in replace_options.items():
            # A replacement may redirect to a different repo (e.g. a fork) and
            # optionally append `@<tag|branch|commit>`. The pin is what actually
            # gets resolved, so report against the replacement target.
            target, _, pin = replacement.partition('@')
            repo = self._repo_from_locator(target)
            if not repo:
                print(f"Could not derive a GitHub repo from '{target}', skipping.")
                continue

            pin = pin or 'HEAD'
            pin_date = self._get_ref_date(repo, pin)
            tracking_mode = PACKAGE_TRACKING_MODE.get(package_locator, 'release')

            if tracking_mode == 'head':
                latest_version, latest_version_date = self._get_head_version(repo)
                status, commit_distance = self._determine_head_tracked_status(
                    repo, pin, pin_date, latest_version)
            else:
                latest_version, latest_version_date = self._get_latest_package_version(repo)
                status, commit_distance = self._determine_package_status(
                    repo, pin, pin_date, latest_version, latest_version_date)

            packages[package_locator] = PackageVersion(
                pin=pin,
                pin_date=pin_date,
                pin_source_url=self._get_package_source_url(repo, pin),
                latest_version=latest_version,
                latest_version_date=latest_version_date,
                latest_version_source_url=(
                    self._get_package_source_url(repo, latest_version)
                    if latest_version else None
                ),
                status=status,
                commit_distance=commit_distance,
                tracking_mode=tracking_mode,
                pin_reason=PINNED_PACKAGES.get(package_locator),
            )

        return packages

    def _repo_from_locator(self, locator: str) -> Optional[str]:
        """Turn a github.com/org/repo[/sub/path] locator into 'org/repo'."""
        match = re.match(r'(?:https?://)?github\.com/([^/]+)/([^/@]+)', locator)
        return f"{match.group(1)}/{match.group(2)}" if match else None

    def _is_commit_sha(self, ref: str) -> bool:
        return bool(re.fullmatch(r'[0-9a-f]{7,40}', ref or '', re.IGNORECASE))

    def _github_get(self, path: str, allow_missing: bool = False):
        """GET a GitHub API path, returning parsed JSON or None.

        Set allow_missing for endpoints where a 404 is a legitimate answer
        rather than a failure — a repo that has never cut a release returns 404
        from /releases/latest, and logging that as an error is just noise.
        """
        try:
            response = requests.get(
                f"https://api.github.com/{path}", timeout=10,
                headers={'Authorization': f'token {os.getenv("GITHUB_TOKEN")}'})
            if response.status_code == 200:
                return response.json()
            if response.status_code == 404 and allow_missing:
                return None
            print(f"Error fetching {path}: {response.status_code}")
        except Exception as e:
            print(f"Error fetching {path}: {e}")
        return None

    def _get_ref_date(self, repo: str, ref: str) -> Optional[str]:
        """Resolve the commit date (YYYY-MM-DD) of a tag, branch or commit."""
        if not ref:
            return None

        candidates = [ref]
        # Kurtosis pins are often written `@v1.1.0` while the upstream tag is
        # `1.1.0` (or the reverse), so try both spellings before giving up.
        if not self._is_commit_sha(ref):
            stripped = ref.lstrip('v')
            candidates += [stripped, f"v{stripped}"]

        for candidate in dict.fromkeys(candidates):
            data = self._github_get(f"repos/{repo}/commits/{candidate}")
            if data:
                date = data.get('commit', {}).get('committer', {}).get('date')
                return date[:10] if date else None
        return None

    def _get_latest_package_version(self, repo: str) -> tuple:
        """Return (version, date) of the newest release, falling back to tags.

        A repo with neither is not release-tracked at all; add it to
        PACKAGE_TRACKING_MODE as "head" rather than silently comparing it
        against its own branch tip, which would always look up to date.
        """
        # A 404 here just means the repo has never published a release.
        release = self._github_get(
            f"repos/{repo}/releases/latest", allow_missing=True)
        if release and release.get('tag_name'):
            return release['tag_name'], (release.get('published_at') or '')[:10] or None

        tags = self._github_get(f"repos/{repo}/tags?per_page=1")
        if isinstance(tags, list) and tags:
            tag_name = tags[0].get('name')
            if tag_name:
                return tag_name, self._get_ref_date(repo, tag_name)

        print(f"No releases or tags found for {repo}; consider tracking it by "
              f"head in PACKAGE_TRACKING_MODE.")
        return None, None

    def _get_head_version(self, repo: str) -> tuple:
        """Return (short_sha, date) of the default branch HEAD."""
        commits = self._github_get(f"repos/{repo}/commits?per_page=1")
        if isinstance(commits, list) and commits:
            sha = commits[0].get('sha', '')
            date = commits[0].get('commit', {}).get('committer', {}).get('date')
            return sha[:12] if sha else None, date[:10] if date else None
        return None, None

    def _determine_head_tracked_status(self, repo: str, pin: str,
                                       pin_date: Optional[str],
                                       head_version: Optional[str]) -> tuple:
        """Judge a pin that tracks HEAD rather than releases.

        Being behind HEAD is the normal steady state for these packages, so
        distance alone is not a signal. What matters is age: a pin only becomes
        a problem once it is old enough that we are plausibly missing fixes.
        """
        if not head_version:
            return None, None

        if pin[:12] == head_version[:12]:
            return "matches stable", None

        comparison = self._github_get(f"repos/{repo}/compare/{head_version}...{pin}")
        distance = None
        if comparison:
            behind_by = comparison.get('behind_by', 0)
            if behind_by > 0:
                distance = f"{behind_by} commits behind HEAD"
            elif comparison.get('ahead_by', 0) > 0:
                # Pinned to an unmerged or since-rewritten commit.
                return "newer than stable", (
                    f"{comparison['ahead_by']} commits ahead of HEAD")

        age_days = self._days_since(pin_date)
        if age_days is not None and age_days > HEAD_TRACKING_STALE_AFTER_DAYS:
            age_note = f"pinned commit is {age_days} days old"
            return "behind stable", (
                f"{distance}, {age_note}" if distance else age_note)

        # Recent enough to be deliberate: report the drift without alarming.
        return "tracking head", distance

    def _days_since(self, date: Optional[str]) -> Optional[int]:
        """Whole days between an ISO date (YYYY-MM-DD) and today."""
        if not date:
            return None
        try:
            return (datetime.now() - datetime.strptime(date, "%Y-%m-%d")).days
        except ValueError:
            return None

    def _get_package_source_url(self, repo: str, ref: str) -> Optional[str]:
        """Build a browsable URL for a package ref."""
        if not ref:
            return None
        if self._is_commit_sha(ref):
            return f"https://github.com/{repo}/tree/{ref}"
        return f"https://github.com/{repo}/releases/tag/{ref}"

    def _determine_package_status(self, repo: str, pin: str, pin_date: Optional[str],
                                  latest_version: Optional[str],
                                  latest_version_date: Optional[str]) -> tuple:
        """Determine whether a package pin is up to date, and how far it has drifted.

        Returns (status, commit_distance) where commit_distance is a short
        human-readable summary like "14 commits behind 1.0.0", or None.
        """
        if not latest_version:
            return None, None

        # A tag pin can be compared directly against the latest release tag.
        if not self._is_commit_sha(pin) and not self._is_commit_sha(latest_version):
            if pin.lstrip('v') == latest_version.lstrip('v'):
                return "matches stable", None
            return self._determine_status(
                pin.lstrip('v'), latest_version.lstrip('v')), None

        # A commit pin equal to the latest ref is up to date.
        if pin[:12] == (latest_version or '')[:12]:
            return "matches stable", None

        # For a commit pin, ask GitHub where it sits relative to the latest
        # release. Comparing raw dates would be wrong: a commit can be authored
        # after a release was published while still being an ancestor of it.
        comparison = self._github_get(f"repos/{repo}/compare/{latest_version}...{pin}")
        if comparison:
            behind_by = comparison.get('behind_by', 0)
            ahead_by = comparison.get('ahead_by', 0)
            if behind_by > 0:
                return "behind stable", f"{behind_by} commits behind {latest_version}"
            if ahead_by > 0:
                return "newer than stable", f"{ahead_by} commits ahead of {latest_version}"
            return "matches stable", None

        # Fall back to dates only when the comparison is unavailable.
        if pin_date and latest_version_date:
            if pin_date > latest_version_date:
                return "newer than stable", None
            if pin_date < latest_version_date:
                return "behind stable", None
            return "matches stable", None

        return None, None

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
    print(f"Total Packages: {summary['total_packages']}")
    print(f"Total Test environments: {summary['environments']['total']}")
    print(f"Matrix generated at: {matrix['generated_at']}")


if __name__ == "__main__":
    main()
