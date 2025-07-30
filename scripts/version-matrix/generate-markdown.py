#!/usr/bin/env python3
"""
Generate updated CDK_VERSION_MATRIX.MD from extracted version data.

This script creates a comprehensive Markdown version matrix that includes:
1. Component compatibility matrix by fork
2. Test scenario configurations  
3. Version status indicators (stable, deprecated, experimental, pinned)
4. Links to source repositories and releases
"""

import json
import yaml
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional
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
        self.matrix_json_path = repo_root / "version-matrix.json"
        self.output_path = repo_root / "CDK_VERSION_MATRIX.MD"
        
        # Status icons
        self.status_icons = {
            "stable": "✅",
            "deprecated": "⚠️", 
            "experimental": "🧪",
            "pinned": "📌"
        }
        
        # Core components for the main matrix
        self.core_components = [
            "CDK Erigon",
            "ZkEVM Prover", 
            "Agglayer Contracts",
            "Data Availability",
            "Bridge Service"
        ]

    def load_matrix_data(self) -> Dict:
        """Load the extracted version matrix data."""
        if not self.matrix_json_path.exists():
            raise FileNotFoundError(f"Matrix data not found at {self.matrix_json_path}")
        
        with open(self.matrix_json_path, 'r') as f:
            return json.load(f)

    def extract_fork_matrix(self, data: Dict) -> List[MatrixEntry]:
        """Extract fork-based matrix entries from the data."""
        entries = []
        matrix_configs = data.get('matrix_configurations', {})
        
        for config_name, config_data in matrix_configs.items():
            if isinstance(config_data, dict):
                fork_id = config_data.get('fork_id', 'unknown')
                consensus = config_data.get('consensus', 'unknown')
                
                components = {}
                sources = {}
                status = {}
                
                # Extract component versions
                for comp_name in self.core_components:
                    comp_key = comp_name.lower().replace(' ', '_')
                    if comp_key in config_data:
                        comp_info = config_data[comp_key]
                        if isinstance(comp_info, dict):
                            version = comp_info.get('version', 'unknown')
                            source = comp_info.get('source', '')
                            components[comp_name] = version
                            sources[comp_name] = source
                            status[comp_name] = self._determine_status_from_version(version)
                
                entries.append(MatrixEntry(
                    fork_id=str(fork_id),
                    consensus=consensus,
                    components=components,
                    sources=sources, 
                    status=status
                ))
        
        # Sort by fork ID
        return sorted(entries, key=lambda x: int(x.fork_id) if x.fork_id.isdigit() else 999)

    def _determine_status_from_version(self, version: str) -> str:
        """Determine status from version string."""
        version_lower = version.lower()
        
        if any(keyword in version_lower for keyword in ['alpha', 'beta', 'rc']):
            return "experimental"
        elif 'hotfix' in version_lower or 'patch' in version_lower:
            return "pinned"
        elif any(keyword in version_lower for keyword in ['deprecated', 'old']):
            return "deprecated"
        else:
            return "stable"

    def generate_test_scenarios_section(self, data: Dict) -> str:
        """Generate test scenarios section."""
        scenarios = data.get('test_scenarios', {})
        
        content = []
        content.append("## Test Scenarios\n")
        content.append("The following test scenarios are currently supported:\n")
        
        # Group scenarios by type
        scenario_groups = {}
        for name, scenario in scenarios.items():
            description = scenario.get('description', 'Unknown')
            consensus = scenario.get('consensus_type', 'unknown')
            
            # Group by major type
            if 'FEP' in description:
                group = "FEP (Full Execution Proofs)"
            elif 'PP' in description or 'pessimistic' in consensus.lower():
                group = "PP (Pessimistic Proofs)"
            elif 'CDK-Erigon' in description or scenario.get('sequencer_type') == 'erigon':
                group = "CDK-Erigon"
            elif 'OP' in description:
                group = "OP Stack"
            else:
                group = "Other"
            
            if group not in scenario_groups:
                scenario_groups[group] = []
            
            scenario_groups[group].append({
                'name': name,
                'description': description,
                'consensus': consensus,
                'fork_id': scenario.get('fork_id'),
                'components': scenario.get('components', {})
            })
        
        # Generate grouped tables
        for group_name, group_scenarios in scenario_groups.items():
            content.append(f"### {group_name}\n")
            
            # Create table
            content.append("| Scenario | Description | Consensus | Fork ID | Key Components |")
            content.append("|----------|-------------|-----------|---------|----------------|")
            
            for scenario in sorted(group_scenarios, key=lambda x: x['name']):
                key_components = []
                for comp_name, comp_info in scenario['components'].items():
                    if isinstance(comp_info, dict):
                        version = comp_info.get('version', 'unknown')
                        status = comp_info.get('status', 'stable')
                        icon = self.status_icons.get(status, '')
                        key_components.append(f"{comp_name}:{version}{icon}")
                
                components_str = ", ".join(key_components[:3])  # Limit to first 3
                if len(key_components) > 3:
                    components_str += f" (+{len(key_components)-3} more)"
                
                content.append(
                    f"| {scenario['name']} | {scenario['description']} | "
                    f"{scenario['consensus']} | {scenario['fork_id'] or 'N/A'} | "
                    f"{components_str} |"
                )
            
            content.append("")  # Empty line
        
        return "\n".join(content)

    def generate_component_details_section(self, data: Dict) -> str:
        """Generate detailed component information section."""
        content = []
        content.append("## Component Details\n")
        
        default_components = data.get('default_components', {})
        latest_releases = data.get('latest_releases', {})
        
        content.append("| Component | Current Version | Status | Latest Release | Source |")
        content.append("|-----------|----------------|--------|----------------|--------|")
        
        for comp_name in sorted(default_components.keys()):
            comp_info = default_components[comp_name]
            version = comp_info.get('version', 'unknown')
            status = comp_info.get('status', 'stable')
            source_url = comp_info.get('source_url', '')
            
            # Get latest release info
            latest_info = latest_releases.get(comp_name, {})
            latest_version = latest_info.get('latest_version', 'unknown')
            latest_url = latest_info.get('url', '')
            
            # Status with icon
            status_with_icon = f"{status} {self.status_icons.get(status, '')}"
            
            # Version with link
            version_link = f"[{version}]({source_url})" if source_url else version
            latest_link = f"[{latest_version}]({latest_url})" if latest_url else latest_version
            
            # Source repository link
            if source_url:
                repo_url = '/'.join(source_url.split('/')[:5])  # Get base repo URL
                source_link = f"[GitHub]({repo_url})"
            else:
                source_link = "N/A"
            
            content.append(
                f"| {comp_name} | {version_link} | {status_with_icon} | "
                f"{latest_link} | {source_link} |"
            )
        
        content.append("")
        content.append("### Status Legend\n")
        for status, icon in self.status_icons.items():
            content.append(f"- {icon} **{status.title()}**: {self._get_status_description(status)}")
        
        return "\n".join(content)

    def _get_status_description(self, status: str) -> str:
        """Get description for status type."""
        descriptions = {
            "stable": "Production-ready, recommended for use",
            "deprecated": "No longer recommended, will be removed in future versions",
            "experimental": "Under development, may have breaking changes",
            "pinned": "Specific version required due to compatibility or bug fixes"
        }
        return descriptions.get(status, "Unknown status")

    def generate_fork_compatibility_matrix(self, entries: List[MatrixEntry]) -> str:
        """Generate the main fork compatibility matrix."""
        content = []
        content.append("## Fork Compatibility Matrix\n")
        content.append("Which versions of the CDK stack are meant to work together?\n")
        
        if not entries:
            content.append("*No fork compatibility data available*\n")
            return "\n".join(content)
        
        # Create table header
        header = ["Fork ID", "Consensus"] + self.core_components
        content.append("| " + " | ".join(header) + " |")
        content.append("| " + " | ".join(["---"] * len(header)) + " |")
        
        # Create rows
        for entry in entries:
            row = [entry.fork_id, entry.consensus]
            
            for component in self.core_components:
                version = entry.components.get(component, 'N/A')
                source = entry.sources.get(component, '')
                status = entry.status.get(component, 'stable')
                icon = self.status_icons.get(status, '')
                
                if source and version != 'N/A':
                    cell = f"[{version}]({source}){icon}"
                else:
                    cell = f"{version}{icon}"
                
                row.append(cell)
            
            content.append("| " + " | ".join(row) + " |")
        
        return "\n".join(content)

    def generate_metadata_section(self, data: Dict) -> str:
        """Generate metadata and generation info."""
        content = []
        
        generated_at = data.get('generated_at', 'unknown')
        summary = data.get('summary', {})
        
        content.append(f"*Last updated: {generated_at}*")
        content.append(f"*Total components tracked: {summary.get('total_components', 0)}*")
        content.append(f"*Total test scenarios: {summary.get('total_scenarios', 0)}*")
        content.append("")
        content.append("---")
        content.append("")
        content.append("**Note**: This version matrix is automatically generated. ")
        content.append("For the most up-to-date information, check the individual component repositories.")
        
        return "\n".join(content)

    def generate_markdown(self, data: Dict) -> str:
        """Generate the complete Markdown content."""
        content = []
        
        # Header
        content.append("# Polygon CDK Version Matrix\n")
        content.append(self.generate_metadata_section(data))
        content.append("")
        
        # Fork compatibility matrix (main table)
        entries = self.extract_fork_matrix(data)
        content.append(self.generate_fork_compatibility_matrix(entries))
        content.append("")
        
        # Test scenarios
        content.append(self.generate_test_scenarios_section(data))
        content.append("")
        
        # Component details
        content.append(self.generate_component_details_section(data))
        
        return "\n".join(content)

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
    content = generator.generate_markdown(data)
    
    print("Saving updated matrix...")
    generator.save_markdown(content)
    
    print("Version matrix Markdown generated successfully!")


if __name__ == "__main__":
    main()