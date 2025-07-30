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
    name: str
    version: str
    image: str
    source_url: Optional[str] = None
    status: str = "stable"  # stable, deprecated, experimental, pinned
    last_updated: Optional[str] = None
    fork_compatibility: Optional[List[str]] = None


@dataclass
class TestScenario:
    """Represents a test scenario configuration."""
    name: str
    description: str
    consensus_type: str
    sequencer_type: Optional[str]
    fork_id: Optional[str]
    components: Dict[str, ComponentVersion]
    deployment_stages: Dict[str, bool]


class VersionMatrixExtractor:
    """Extracts and manages version matrix information."""
    
    def __init__(self, repo_root: Path):
        self.repo_root = repo_root
        self.input_parser_path = repo_root / "input_parser.star"
        self.matrix_file = repo_root / "CDK_VERSION_MATRIX.MD"
        self.tests_dir = repo_root / ".github" / "tests"
        
        # Component mapping
        self.component_mapping = {
            "aggkit_image": "AggKit",
            "agglayer_image": "Agglayer",
            "aggkit_prover_image": "AggKit Prover",
            "cdk_erigon_node_image": "CDK Erigon",
            "cdk_node_image": "CDK Node",
            "cdk_validium_node_image": "CDK Validium Node",
            "agglayer_contracts_image": "Agglayer Contracts",
            "zkevm_da_image": "Data Availability",
            "zkevm_node_image": "ZkEVM Node",
            "zkevm_pool_manager_image": "Pool Manager",
            "zkevm_prover_image": "ZkEVM Prover",
            "zkevm_sequence_sender_image": "Sequence Sender",
            "zkevm_bridge_service_image": "Bridge Service",
            "zkevm_bridge_ui_image": "Bridge UI",
            "op_succinct_proposer_image": "OP Succinct Proposer",
            "test_runner_image": "Test Runner",
            "status_checker_image": "Status Checker"
        }
        
        # GitHub repositories for version checking
        self.repos = {
            "CDK Erigon": "0xPolygonHermez/cdk-erigon",
            "ZkEVM Prover": "0xPolygonHermez/zkevm-prover", 
            "Agglayer Contracts": "agglayer/agglayer-contracts",
            "Data Availability": "0xPolygon/cdk-data-availability",
            "Bridge Service": "0xPolygonHermez/zkevm-bridge-service",
            "AggKit": "agglayer/aggkit",
            "Agglayer": "agglayer/agglayer",
            "CDK Node": "0xPolygon/cdk",
            "CDK Validium Node": "0xPolygon/cdk-validium-node"
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
                raise ValueError("DEFAULT_IMAGES not found in input_parser.star")
            
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
                        version = self._extract_version_from_image(image)
                        source_url = self._get_source_url(image, version)
                        
                        components[self.component_mapping[key]] = ComponentVersion(
                            name=self.component_mapping[key],
                            version=version,
                            image=image,
                            source_url=source_url,
                            status=self._determine_status(image, version)
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
        
        # Remove common prefixes
        version = re.sub(r'^v?', '', tag)
        return version

    def _get_source_url(self, image: str, version: str) -> Optional[str]:
        """Generate source URL for the component version."""
        # Map image to repository
        for comp_name, repo in self.repos.items():
            if any(keyword in image.lower() for keyword in comp_name.lower().split()):
                if version not in ['latest', 'main', 'master']:
                    return f"https://github.com/{repo}/releases/tag/v{version.lstrip('v')}"
                else:
                    return f"https://github.com/{repo}"
        return None

    def _determine_status(self, image: str, version: str) -> str:
        """Determine the status of a version based on various factors."""
        # Check for experimental indicators
        if any(keyword in version.lower() for keyword in ['alpha', 'beta', 'rc', 'dev', 'experimental']):
            return "experimental"
        
        # Check for specific pinned versions (common patterns)
        if any(keyword in version.lower() for keyword in ['hotfix', 'patch', 'fork']):
            return "pinned"
        
        # Check for very old versions (simplified check)
        if re.match(r'^[0-4]\.', version):  # Versions starting with 0-4 might be older
            return "deprecated"
            
        return "stable"

    def extract_test_scenarios(self) -> Dict[str, TestScenario]:
        """Extract test scenarios from .github/tests/ configurations."""
        scenarios = {}
        
        try:
            # Walk through test configuration files
            for yaml_file in self.tests_dir.rglob("*.yml"):
                if yaml_file.name in ['matrix.yml']:
                    continue  # Skip the matrix file itself
                
                try:
                    with open(yaml_file, 'r') as f:
                        config = yaml.safe_load(f)
                    
                    if not config:
                        continue
                    
                    scenario_name = yaml_file.stem
                    relative_path = yaml_file.relative_to(self.tests_dir)
                    
                    # Extract scenario information
                    args = config.get('args', {})
                    deployment_stages = config.get('deployment_stages', {})
                    
                    consensus_type = args.get('consensus_contract_type', 'unknown')
                    sequencer_type = args.get('sequencer_type')
                    fork_id = args.get('fork_id')
                    
                    # Determine scenario type from path and config
                    scenario_type = self._classify_scenario(relative_path, args, deployment_stages)
                    
                    # Extract component versions from the config
                    components = self._extract_components_from_config(args)
                    
                    scenarios[scenario_name] = TestScenario(
                        name=scenario_name,
                        description=scenario_type,
                        consensus_type=consensus_type,
                        sequencer_type=sequencer_type,
                        fork_id=str(fork_id) if fork_id is not None else None,
                        components=components,
                        deployment_stages=deployment_stages
                    )
                    
                except Exception as e:
                    print(f"Error processing {yaml_file}: {e}")
                    continue
        
        except Exception as e:
            print(f"Error scanning test scenarios: {e}")
            
        return scenarios

    def _classify_scenario(self, path: Path, args: dict, deployment_stages: dict) -> str:
        """Classify the type of test scenario."""
        path_str = str(path).lower()
        
        # Check deployment stages for scenario type
        if deployment_stages.get('deploy_op_succinct'):
            return "FEP (Full Execution Proofs) - OP Succinct"
        
        if deployment_stages.get('deploy_optimism_rollup'):
            return "OP Stack Rollup"
        
        # Check consensus type
        consensus = args.get('consensus_contract_type', '').lower()
        if consensus == 'fep':
            return "FEP (Full Execution Proofs)"
        elif consensus == 'pessimistic':
            return "PP (Pessimistic Proofs)"
        elif consensus in ['rollup', 'cdk_validium']:
            sequencer = args.get('sequencer_type', '')
            if sequencer == 'erigon':
                return f"CDK-Erigon ({consensus.replace('_', ' ').title()})"
            else:
                return f"CDK ({consensus.replace('_', ' ').title()})"
        elif consensus == 'ecdsa':
            return "Aggchain ECDSA"
        
        # Classify by path
        if 'consensus' in path_str:
            return f"Consensus Test ({consensus})"
        elif 'fork' in path_str:
            fork_id = args.get('fork_id', 'unknown')
            return f"Fork {fork_id} Test"
        elif 'combination' in path_str:
            return "Component Combination Test"
        elif 'chain' in path_str:
            return "Chain Configuration Test"
        
        return "Standard Test Configuration"

    def _extract_components_from_config(self, args: dict) -> Dict[str, ComponentVersion]:
        """Extract component versions from test configuration args."""
        components = {}
        
        for key, value in args.items():
            if key.endswith('_image') and key in self.component_mapping:
                comp_name = self.component_mapping[key]
                version = self._extract_version_from_image(value)
                source_url = self._get_source_url(value, version)
                
                components[comp_name] = ComponentVersion(
                    name=comp_name,
                    version=version,
                    image=value,
                    source_url=source_url,
                    status=self._determine_status(value, version)
                )
        
        return components

    def extract_matrix_info(self) -> Dict:
        """Extract information from existing matrix.yml file."""
        matrix_info = {}
        
        matrix_file = self.tests_dir / "matrix.yml"
        if matrix_file.exists():
            try:
                with open(matrix_file, 'r') as f:
                    matrix_info = yaml.safe_load(f) or {}
            except Exception as e:
                print(f"Error reading matrix.yml: {e}")
        
        return matrix_info

    def check_latest_releases(self) -> Dict[str, Dict]:
        """Check latest releases from GitHub repositories."""
        release_info = {}
        
        for component, repo in self.repos.items():
            try:
                # Use GitHub API to get latest release
                url = f"https://api.github.com/repos/{repo}/releases/latest"
                response = requests.get(url, timeout=10)
                
                if response.status_code == 200:
                    release_data = response.json()
                    release_info[component] = {
                        'latest_version': release_data['tag_name'],
                        'published_at': release_data['published_at'],
                        'url': release_data['html_url']
                    }
                else:
                    print(f"Could not fetch latest release for {component}: {response.status_code}")
                    
            except Exception as e:
                print(f"Error checking releases for {component}: {e}")
        
        return release_info

    def generate_version_matrix(self) -> Dict:
        """Generate comprehensive version matrix."""
        print("Extracting default images...")
        default_components = self.extract_default_images()
        
        print("Extracting test scenarios...")
        test_scenarios = self.extract_test_scenarios()
        
        print("Extracting matrix information...")
        matrix_info = self.extract_matrix_info()
        
        print("Checking latest releases...")
        latest_releases = self.check_latest_releases()
        
        # Build comprehensive matrix
        matrix = {
            'generated_at': datetime.now().isoformat(),
            'default_components': {name: asdict(comp) for name, comp in default_components.items()},
            'test_scenarios': {name: asdict(scenario) for name, scenario in test_scenarios.items()},
            'matrix_configurations': matrix_info,
            'latest_releases': latest_releases,
            'summary': {
                'total_components': len(default_components),
                'total_scenarios': len(test_scenarios),
                'supported_forks': list(set(
                    scenario.fork_id for scenario in test_scenarios.values() 
                    if scenario.fork_id
                )),
                'consensus_types': list(set(
                    scenario.consensus_type for scenario in test_scenarios.values()
                ))
            }
        }
        
        return matrix

    def save_matrix_json(self, matrix: Dict, output_path: Optional[Path] = None):
        """Save matrix as JSON file."""
        if output_path is None:
            output_path = self.repo_root / "version-matrix.json"
        
        with open(output_path, 'w') as f:
            json.dump(matrix, f, indent=2, sort_keys=True)
        
        print(f"Version matrix saved to {output_path}")


def main():
    """Main execution function."""
    repo_root = Path(__file__).parent.parent.parent
    extractor = VersionMatrixExtractor(repo_root)
    
    print("Starting version matrix extraction...")
    matrix = extractor.generate_version_matrix()
    
    # Save the matrix
    extractor.save_matrix_json(matrix)
    
    # Print summary
    summary = matrix['summary']
    print(f"\n=== Version Matrix Summary ===")
    print(f"Total Components: {summary['total_components']}")
    print(f"Total Test Scenarios: {summary['total_scenarios']}")
    print(f"Supported Forks: {', '.join(sorted(summary['supported_forks']))}")
    print(f"Consensus Types: {', '.join(sorted(summary['consensus_types']))}")
    print(f"Matrix generated at: {matrix['generated_at']}")


if __name__ == "__main__":
    main()