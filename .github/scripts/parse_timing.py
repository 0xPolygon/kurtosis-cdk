#!/usr/bin/env python3
"""
Parse Kurtosis timing information from run logs.

This script extracts the "Starlark code successfully run. Total instruction execution time"
from Kurtosis logs and converts the time to seconds for analysis.
"""

import re
import json
import sys
import argparse
import os
from typing import Optional, Dict, Any


def parse_time_to_seconds(time_str: str) -> float:
    """
    Convert time string to seconds.

    Supports formats like:
    - "2m57.885776139s"
    - "177.885776139s"
    - "30000ms"
    - "1h2m30s"
    """
    # Remove any whitespace
    time_str = time_str.strip()

    total_seconds = 0.0

    # Handle hours (h)
    hours_match = re.search(r'(\d+(?:\.\d+)?)h', time_str)
    if hours_match:
        total_seconds += float(hours_match.group(1)) * 3600

    # Handle minutes (m) - but not 'ms'
    minutes_match = re.search(r'(\d+(?:\.\d+)?)m(?!s)', time_str)
    if minutes_match:
        total_seconds += float(minutes_match.group(1)) * 60

    # Handle seconds (s) - but not part of 'ms'
    seconds_match = re.search(r'(\d+(?:\.\d+)?)s(?!\w)', time_str)
    if seconds_match:
        total_seconds += float(seconds_match.group(1))

    # Handle milliseconds (ms)
    ms_match = re.search(r'(\d+(?:\.\d+)?)ms', time_str)
    if ms_match:
        total_seconds += float(ms_match.group(1)) / 1000

    # If no units found, assume it's already in seconds
    if total_seconds == 0.0 and re.match(r'^\d+(?:\.\d+)?$', time_str):
        total_seconds = float(time_str)

    return total_seconds


def extract_timing_from_log(log_file_path: str) -> Optional[Dict[str, Any]]:
    """
    Extract timing information from Kurtosis log file.

    Returns dictionary with timing data or None if not found.
    """
    try:
        with open(log_file_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except FileNotFoundError:
        print(f"Error: log file not found: {log_file_path}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"Error: reading log file: {e}", file=sys.stderr)
        return None

    # Pattern to match the timing line
    pattern = r'Starlark code successfully run\.\s*Total instruction execution time:\s*([0-9hms.]+)\.'
    matches = re.findall(pattern, content, re.IGNORECASE)
    if not matches:
        print(f"Error: no timing information found in log file", file=sys.stderr)
        return None
    raw_time = matches[-1]  # Use the last match if multiple found

    try:
        parsed_time = parse_time_to_seconds(raw_time)
        return (raw_time, parsed_time)
    except Exception as e:
        print(f"Error parsing timing '{raw_time}': {e}", file=sys.stderr)
        return None


def load_thresholds(threshold_file_path: str) -> Dict[str, float]:
    """
    Load timing thresholds from configuration file.

    Format: <config-name>: <threshold_seconds>
    Lines starting with # are comments.
    """
    thresholds = {}

    if not os.path.exists(threshold_file_path):
        print(
            f"Error: threshold file not found: {threshold_file_path}", file=sys.stderr)
        return None

    try:
        with open(threshold_file_path, 'r', encoding='utf-8') as f:
            for line_num, line in enumerate(f, 1):
                line = line.strip()

                # Skip empty lines and comments
                if not line or line.startswith('#'):
                    continue

                # Parse config_name: threshold format
                if ':' not in line:
                    print(
                        f"Warning: Invalid format on line {line_num}: {line}", file=sys.stderr)
                    continue

                config_name, threshold_str = line.split(':', 1)
                config_name = config_name.strip()
                threshold_str = threshold_str.strip()

                try:
                    threshold = float(threshold_str)
                    thresholds[config_name] = threshold
                except ValueError:
                    print(
                        f"Warning: Invalid threshold value on line {line_num}: {threshold_str}", file=sys.stderr)
                    continue

    except Exception as e:
        print(
            f"Error reading threshold file {threshold_file_path}: {e}", file=sys.stderr)

    return thresholds


def get_config_name_from_path(config_path: str) -> str:
    """Extract config name from file path for threshold lookup."""
    if not config_path:
        return "default"

    # Extract filename without extension
    filename = os.path.basename(config_path)
    config_name = os.path.splitext(filename)[0]

    return config_name


def main():
    parser = argparse.ArgumentParser(
        description='Parse deployment timing from Kurtosis log files')
    parser.add_argument('log_file', help='Path to the log file to parse')
    parser.add_argument('--threshold', type=float,
                        help='Maximum allowed execution time in seconds (overrides config file)')
    parser.add_argument('--config-file',
                        help='Path to the args file used for this deployment (for threshold lookup)')
    parser.add_argument('--threshold-file', default='.github/scripts/timing-thresholds.txt',
                        help='Path to threshold configuration file')
    args = parser.parse_args()

    result = extract_timing_from_log(args.log_file)
    if result is None:
        sys.exit(1)

    raw_time, parsed_time = result

    # Determine threshold to use
    if args.threshold:
        # Use explicit threshold from command line
        threshold = args.threshold
        threshold_source = "command line"
    else:
        # Load thresholds from config file
        thresholds = load_thresholds(args.threshold_file)
        if thresholds is None:
            sys.exit(1)

        config_name = get_config_name_from_path(args.config_file)

        # Look up threshold by config name, fall back to default
        if config_name in thresholds:
            threshold = thresholds[config_name]
            threshold_source = f"config '{config_name}'"
        elif 'default' in thresholds:
            threshold = thresholds['default']
            threshold_source = "default config"
        else:
            threshold = 200.0  # Fallback default
            threshold_source = "fallback default"

    print("Kurtosis execution times:")
    print(f"- raw: {raw_time}")
    print(f"- parsed: {parsed_time:.2f}s")
    print(f"- threshold: {threshold:.1f}s (from {threshold_source})")

    if parsed_time > threshold:
        print(f"❌ Error: execution time exceeds the threshold")
        sys.exit(1)
    else:
        print(f"✅ Execution time is within the threshold")


if __name__ == '__main__':
    sys.exit(main())
