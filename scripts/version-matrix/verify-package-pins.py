#!/usr/bin/env python3
"""
Verify that external Kurtosis package versions live only in kurtosis.yml.

The `replace` block in `kurtosis.yml` is the single source of truth for every
external package version. Starlark files reference packages *without* an
`@<version>` suffix so that a bump only ever has to happen in one place.

An inline `@<version>` in a `.star` file is therefore a bug: `replace` still
wins at resolution time, so the inline version is silently ignored and becomes
misleading documentation of a version that isn't actually used.

This script fails if either invariant is broken:
  1. A `.star` file pins a version inline for a package listed in `replace`.
  2. A package referenced in Starlark is missing a `replace` entry, or has one
     with no `@<version>` (both resolve at upstream HEAD).

Runs offline: no GitHub token required.
"""

import re
import sys
import yaml
from pathlib import Path

# Directories scanned for package references.
STARLARK_ROOTS = ["main.star", "src"]

# Packages that live in this repo, and so are never pinned externally.
INTERNAL_PACKAGES = {"github.com/0xPolygon/kurtosis-cdk"}

PACKAGE_REFERENCE_PATTERN = re.compile(
    r'(github\.com/[\w.-]+/[\w.-]+)([^"\'\s]*)')


def load_replace_pins(repo_root: Path) -> dict:
    """Read the pins declared in the kurtosis.yml replace block."""
    kurtosis_yaml = yaml.safe_load((repo_root / "kurtosis.yml").read_text()) or {}
    pins = {}
    for locator, replacement in (kurtosis_yaml.get("replace") or {}).items():
        _, _, pin = replacement.partition("@")
        pins[locator] = pin or None
    return pins


def iter_starlark_files(repo_root: Path):
    for root in STARLARK_ROOTS:
        path = repo_root / root
        if path.is_file():
            yield path
        elif path.is_dir():
            yield from sorted(path.rglob("*.star"))


def find_package_references(repo_root: Path) -> dict:
    """Map each referenced external package to the inline pins found for it.

    Returns {locator: {inline_pin_or_None: [locations]}}.
    """
    references = {}

    for path in iter_starlark_files(repo_root):
        relative_path = path.relative_to(repo_root)
        for line_number, line in enumerate(path.read_text().splitlines(), start=1):
            # Skip comments: they legitimately mention versions and URLs.
            if line.lstrip().startswith("#"):
                continue

            for match in PACKAGE_REFERENCE_PATTERN.finditer(line):
                locator, remainder = match.group(1), match.group(2)
                if locator in INTERNAL_PACKAGES:
                    continue

                # Only consider references inside a string literal, so prose in
                # trailing comments doesn't count as a dependency reference.
                if not re.search(rf'["\']{re.escape(locator)}', line):
                    continue

                _, _, pin = remainder.partition("@")
                references.setdefault(locator, {}).setdefault(
                    pin or None, []).append(f"{relative_path}:{line_number}")

    return references


def main() -> int:
    repo_root = Path(__file__).parent.parent.parent
    replace_pins = load_replace_pins(repo_root)
    references = find_package_references(repo_root)
    errors = []

    for locator in sorted(references):
        inline_pins = references[locator]

        for pin, locations in sorted(
                (p, l) for p, l in inline_pins.items() if p is not None):
            errors.append(
                f"{locator}: pinned inline as '@{pin}' at {', '.join(locations)}\n"
                f"    Versions belong in the `replace` block of kurtosis.yml. "
                f"`replace` overrides this pin, so it is silently ignored.")

        if locator not in replace_pins:
            locations = sorted(
                loc for locs in inline_pins.values() for loc in locs)
            errors.append(
                f"{locator}: referenced at {', '.join(locations)} but missing "
                f"from the `replace` block in kurtosis.yml, so it resolves at "
                f"upstream HEAD")
        elif not replace_pins[locator]:
            errors.append(
                f"{locator}: `replace` entry has no @<version>, so it resolves "
                f"at upstream HEAD")

    # A replace entry for something no longer referenced is dead config.
    for locator in sorted(set(replace_pins) - set(references)):
        errors.append(
            f"{locator}: listed in the `replace` block but not referenced in "
            f"any Starlark file — remove the stale entry")

    if errors:
        print("Package pin verification failed:\n", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    print(f"All {len(references)} external package references resolve via the "
          f"`replace` block in kurtosis.yml, with no inline pins.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
