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
        return None
    except Exception as e:
        print(f"Error reading log file: {e}", file=sys.stderr)
        return None

    # Pattern to match the timing line
    pattern = r'Starlark code successfully run\.\s*Total instruction execution time:\s*([0-9hms.]+)\.'
    matches = re.findall(pattern, content, re.IGNORECASE)
    if not matches:
        return None
    raw_time = matches[-1]  # Use the last match if multiple found

    try:
        parsed_time = parse_time_to_seconds(raw_time)
        return (raw_time, parsed_time)
    except Exception as e:
        print(f"Error parsing timing '{raw_time}': {e}", file=sys.stderr)
        return None


def main():
    parser = argparse.ArgumentParser(
        description='Parse deployment timing from Kurtosis log files')
    parser.add_argument('log_file', help='Path to the log file to parse')
    parser.add_argument('--threshold', type=float, default=200.0,
                        help='Maximum allowed execution time in seconds (default: 200)')
    args = parser.parse_args()

    (raw_time, parsed_time) = extract_timing_from_log(args.log_file)
    if (raw_time, parsed_time) is None:
        print(
            f"No timing information found in {args.log_file}", file=sys.stderr)
        sys.exit(1)

    print("Kurtosis execution times:")
    print(f"- raw: {raw_time}")
    print(f"- parsed: {parsed_time:.2f}s")
    print(f"- threshold: {args.threshold:.1f}s")

    if parsed_time > args.threshold:
        print(f"❌ Error: execution time exceeds the threshold")
        sys.exit(1)
    else:
        print(f"✅ Execution time is within the threshold")


if __name__ == '__main__':
    sys.exit(main())
