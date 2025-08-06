#!/usr/bin/env python3
"""
Registry prefix addition tool for Kurtosis CDK.

This script adds a registry prefix to all Docker images in input_parser.star
to enable pulling images from a private registry (e.g., GCP) instead of Docker Hub,
avoiding rate limiting issues in CI.

Usage:
    python scripts/add-registry-prefix.py --registry-prefix "your-registry.pkg.dev/project/repo"
"""

import argparse
import re
import shutil
import sys
from pathlib import Path
from typing import List, Tuple


class RegistryPrefixAdder:
    """Adds registry prefixes to Docker images in input_parser.star."""

    def __init__(self, input_parser_path: Path, registry_prefix: str):
        self.input_parser_path = input_parser_path
        self.registry_prefix = registry_prefix.rstrip('/')
        self.skip_registries = [
            # polygon devtools artifacts registry
            'europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public',
            # oplabs tools artifacts registry
            'us-docker.pkg.dev/oplabs-tools-artifacts/images',
        ]

    def should_skip_image(self, image: str) -> bool:
        """Check if an image should be skipped (already has a private registry)."""
        return any(image.startswith(registry) for registry in self.skip_registries)

    def add_registry_prefix(self, image: str) -> str:
        """Add registry prefix to a Docker image if it doesn't have one."""
        # Skip images that already have a private registry prefix
        if self.should_skip_image(image):
            return image

        # Handle ghcr.io images specifically
        if image.startswith('ghcr.io/'):
            # Remove the ghcr.io/ prefix and add our registry prefix
            image_without_ghcr = image[8:]  # Remove 'ghcr.io/'
            return f"{self.registry_prefix}/{image_without_ghcr}"

        # If image doesn't contain a registry (no '/' before first ':' or no '/' at all)
        # then it's a Docker Hub image and needs prefixing
        if '/' not in image or (':' in image and image.find('/') > image.find(':')):
            return f"{self.registry_prefix}/{image}"

        # Check if it's a Docker Hub image with namespace (e.g., "hermeznetwork/cdk-erigon")
        parts = image.split('/')
        if len(parts) == 2 and '.' not in parts[0] and ':' not in parts[0]:
            # This is likely a Docker Hub image with namespace
            return f"{self.registry_prefix}/{image}"

        return image

    def process_file(self) -> Tuple[int, List[str]]:
        """Process the input_parser.star file and add registry prefixes."""
        if not self.input_parser_path.exists():
            raise FileNotFoundError(
                f"File not found: {self.input_parser_path}")

        # Read the file
        with open(self.input_parser_path, 'r') as f:
            content = f.read()

        # Find the DEFAULT_IMAGES dictionary
        default_images_pattern = r'(DEFAULT_IMAGES\s*=\s*\{)(.*?)(\n\})'
        match = re.search(default_images_pattern, content, re.DOTALL)

        if not match:
            raise ValueError(
                "DEFAULT_IMAGES dictionary not found in input_parser.star")

        before_dict = match.group(1)
        dict_content = match.group(2)
        after_dict = match.group(3)

        # Process each image line
        modified_lines = []
        modified_images = []

        for line in dict_content.split('\n'):
            original_line = line
            stripped_line = line.strip()

            # Skip empty lines and comments
            if not stripped_line or stripped_line.startswith('#'):
                modified_lines.append(line)
                continue

            # Match image definition lines: "key": "image:tag"
            image_pattern = r'(\s*"[^"]+"):\s*"([^"]+)"(.*)$'
            image_match = re.match(image_pattern, line)

            if image_match:
                key_part = image_match.group(1)
                original_image = image_match.group(2)
                rest_of_line = image_match.group(3)

                new_image = self.add_registry_prefix(original_image)

                if new_image != original_image:
                    modified_images.append(f"{original_image} -> {new_image}")
                    modified_line = f'{key_part}: "{new_image}"{rest_of_line}'
                    modified_lines.append(modified_line)
                else:
                    modified_lines.append(line)
            else:
                modified_lines.append(line)

        # Reconstruct the content
        new_dict_content = '\n'.join(modified_lines)
        new_content = content.replace(
            match.group(0),
            before_dict + new_dict_content + after_dict
        )

        # Write the modified content back
        with open(self.input_parser_path, 'w') as f:
            f.write(new_content)

        return len(modified_images), modified_images

    def validate_file(self) -> bool:
        """Basic validation to ensure the file is still valid after modification."""
        try:
            with open(self.input_parser_path, 'r') as f:
                content = f.read()

            # Check that DEFAULT_IMAGES dictionary is still present and well-formed
            default_images_pattern = r'DEFAULT_IMAGES\s*=\s*\{.*?\n\}'
            if not re.search(default_images_pattern, content, re.DOTALL):
                return False

            # Check for basic syntax issues
            if content.count('{') != content.count('}'):
                return False

            if content.count('"') % 2 != 0:
                return False

            return True
        except Exception as e:
            print(f"Validation error: {e}")
            return False


def main():
    """Main execution function."""
    parser = argparse.ArgumentParser(
        description="Add registry prefix to Docker images in input_parser.star"
    )
    parser.add_argument(
        "--registry-prefix",
        required=True,
        help="Registry prefix to add (e.g., 'your-registry.pkg.dev/project/repo')"
    )
    parser.add_argument(
        "--input-file",
        type=Path,
        help="Path to input_parser.star file (default: auto-detect)"
    )
    parser.add_argument(
        "--output-file",
        type=Path,
        help="Path to output file for modified images (default: modified-images.txt)"
    )

    args = parser.parse_args()

    # Auto-detect input_parser.star if not provided
    if args.input_file:
        input_parser_path = args.input_file
    else:
        # Try to find input_parser.star relative to script location
        script_dir = Path(__file__).parent
        repo_root = script_dir.parent
        input_parser_path = repo_root / "input_parser.star"

    if not input_parser_path.exists():
        print(f"Error: {input_parser_path} not found")
        sys.exit(1)
    
    # Set output file path
    output_file_path = args.output_file or Path("modified-images.txt")

    print(f"Processing: {input_parser_path}")
    print(f"Registry prefix: {args.registry_prefix}")
    print(f"Output file: {output_file_path}")

    # Perform actual modification
    try:
        prefix_adder = RegistryPrefixAdder(
            input_parser_path, args.registry_prefix)
        modified_count, modified_images = prefix_adder.process_file()
        if modified_count > 0:
            print(f"Successfully modified {modified_count} images:")

            # Extract just the new image names (after the arrow)
            new_image_names = []
            for change in modified_images:
                print(f"  {change}")

                # Extract the new image name from "original -> new" format
                new_image = change.split(" -> ")[1]
                new_image_names.append(new_image)

            # Write modified images to output file
            try:
                with open(output_file_path, 'w') as f:
                    for image in new_image_names:
                        f.write(f"{image}\n")
                print(f"Modified images written to: {output_file_path}")
            except Exception as e:
                print(f"Warning: Could not write to output file {output_file_path}: {e}")

            # Validate the modified file
            if prefix_adder.validate_file():
                print(f"File validation passed")
            else:
                print(
                    f"File validation failed - please check {input_parser_path}")
                sys.exit(1)
        else:
            print("No images were modified (all already have registry prefixes)")

            # Create empty output file
            try:
                with open(output_file_path, 'w') as f:
                    f.write("")
                print(f"Empty output file created: {output_file_path}")
            except Exception as e:
                print(f"Warning: Could not create output file {output_file_path}: {e}")

        print("Registry prefix addition completed successfully")

    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
