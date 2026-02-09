#!/usr/bin/env python3
"""
Convert debug_dumpBlock output to genesis alloc format.

Usage:
    python dump_to_alloc.py <state_dump.json> <alloc.json>
"""

import json
import sys


def normalize_address(addr):
    """Normalize address to lowercase with 0x prefix."""
    if not addr:
        return None
    addr = addr.lower()
    if not addr.startswith('0x'):
        addr = '0x' + addr
    return addr


def to_hex(value):
    """Convert integer to hex string with 0x prefix."""
    if isinstance(value, str):
        # Already hex
        if value.startswith('0x'):
            return value
        return '0x' + value
    if isinstance(value, int):
        return hex(value)
    return value


def convert_account(account_data):
    """Convert account from debug_dumpBlock format to genesis alloc format."""
    result = {}

    # Balance (required)
    if 'balance' in account_data:
        balance = account_data['balance']
        if isinstance(balance, int):
            result['balance'] = hex(balance)
        else:
            result['balance'] = balance

    # Nonce (optional, only if > 0)
    if 'nonce' in account_data:
        nonce = account_data['nonce']
        if isinstance(nonce, str):
            nonce = int(nonce, 16) if nonce.startswith('0x') else int(nonce)
        if nonce > 0:
            result['nonce'] = hex(nonce)

    # Code (optional, only if not empty)
    if 'code' in account_data:
        code = account_data['code']
        if code and code != '0x' and code != '0x0':
            result['code'] = code

    # Storage (optional, only if not empty)
    if 'storage' in account_data:
        storage = account_data['storage']
        if storage and isinstance(storage, dict) and len(storage) > 0:
            result['storage'] = storage

    return result


def dump_to_alloc(dump_path, alloc_path):
    """Convert debug_dumpBlock output to genesis alloc format."""
    with open(dump_path, 'r') as f:
        dump = json.load(f)

    # Extract accounts from dump
    accounts = dump.get('accounts', {})

    alloc = {}
    for addr, account_data in accounts.items():
        normalized_addr = normalize_address(addr)
        if not normalized_addr:
            continue

        converted = convert_account(account_data)

        # Only include accounts with actual data
        if converted:
            alloc[normalized_addr] = converted

    # Write alloc
    with open(alloc_path, 'w') as f:
        json.dump(alloc, f, indent=2)

    print(f"Converted {len(alloc)} accounts to alloc format")


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: dump_to_alloc.py <state_dump.json> <alloc.json>")
        sys.exit(1)

    dump_to_alloc(sys.argv[1], sys.argv[2])
