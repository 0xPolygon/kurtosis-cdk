#!/usr/bin/env python3
"""
MITM addon to capture all eth_sendRawTransaction calls to a JSONL file.

This addon logs every raw transaction sent through the proxy, allowing us to
replay them later for snapshot functionality.
"""

import json
import logging
from pathlib import Path
from mitmproxy import ctx, http
from eth_account import Account
from eth_utils import to_checksum_address

# Output file for captured transactions
TRANSACTIONS_FILE = Path("/data/transactions.jsonl")

# Counter for transaction IDs
tx_counter = 0


def extract_sender_address(raw_tx_hex: str) -> str:
    """
    Extract the sender address from a raw transaction.

    Args:
        raw_tx_hex: Raw transaction as hex string (with or without 0x prefix)

    Returns:
        Checksummed sender address, or "unknown" if extraction fails
    """
    try:
        # Remove 0x prefix if present
        if raw_tx_hex.startswith('0x'):
            raw_tx_hex = raw_tx_hex[2:]

        # Decode the transaction to get the sender
        raw_tx_bytes = bytes.fromhex(raw_tx_hex)
        tx = Account.recover_transaction(raw_tx_bytes)

        return to_checksum_address(tx)
    except Exception as e:
        ctx.log.warn(f"Failed to extract sender address: {e}")
        return "unknown"


def load(loader):
    """Initialize the addon."""
    # Ensure the data directory exists
    TRANSACTIONS_FILE.parent.mkdir(parents=True, exist_ok=True)

    # Clear/create the file
    with open(TRANSACTIONS_FILE, 'w') as f:
        pass

    ctx.log.info(f"Transaction capture initialized: {TRANSACTIONS_FILE}")


def request(flow: http.HTTPFlow) -> None:
    """Intercept requests and capture eth_sendRawTransaction calls."""
    global tx_counter

    # Only process POST requests
    if flow.request.method != "POST":
        return

    try:
        # Parse the JSON-RPC request
        request_data = json.loads(flow.request.content.decode('utf-8'))

        # Check if it's an eth_sendRawTransaction call
        if isinstance(request_data, dict):
            method = request_data.get("method")
            if method == "eth_sendRawTransaction":
                params = request_data.get("params", [])
                if params and len(params) > 0:
                    raw_tx = params[0]

                    # Increment counter
                    tx_counter += 1

                    # Extract sender address
                    sender_address = extract_sender_address(raw_tx)

                    # Create transaction record
                    tx_record = {
                        "id": tx_counter,
                        "method": method,
                        "raw_tx": raw_tx,
                        "from": sender_address,
                        "timestamp": flow.request.timestamp_start,
                    }

                    # Append to JSONL file
                    with open(TRANSACTIONS_FILE, 'a') as f:
                        f.write(json.dumps(tx_record) + '\n')

                    ctx.log.info(f"[TX {tx_counter}] Captured eth_sendRawTransaction from {sender_address}")

        # Handle batch requests
        elif isinstance(request_data, list):
            for item in request_data:
                if isinstance(item, dict) and item.get("method") == "eth_sendRawTransaction":
                    params = item.get("params", [])
                    if params and len(params) > 0:
                        raw_tx = params[0]

                        # Increment counter
                        tx_counter += 1

                        # Extract sender address
                        sender_address = extract_sender_address(raw_tx)

                        # Create transaction record
                        tx_record = {
                            "id": tx_counter,
                            "method": "eth_sendRawTransaction",
                            "raw_tx": raw_tx,
                            "from": sender_address,
                            "timestamp": flow.request.timestamp_start,
                        }

                        # Append to JSONL file
                        with open(TRANSACTIONS_FILE, 'a') as f:
                            f.write(json.dumps(tx_record) + '\n')

                        ctx.log.info(f"[TX {tx_counter}] Captured eth_sendRawTransaction from {sender_address} (batch)")

    except (json.JSONDecodeError, KeyError, TypeError) as e:
        # Not a valid JSON-RPC request or doesn't have the expected structure
        pass
    except Exception as e:
        ctx.log.error(f"Error capturing transaction: {e}")
