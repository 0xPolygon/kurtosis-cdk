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

# Output file for captured transactions
TRANSACTIONS_FILE = Path("/data/transactions.jsonl")

# Counter for transaction IDs
tx_counter = 0

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

                    # Create transaction record
                    tx_record = {
                        "id": tx_counter,
                        "method": method,
                        "raw_tx": raw_tx,
                        "timestamp": flow.request.timestamp_start,
                    }

                    # Append to JSONL file
                    with open(TRANSACTIONS_FILE, 'a') as f:
                        f.write(json.dumps(tx_record) + '\n')

                    ctx.log.info(f"[TX {tx_counter}] Captured eth_sendRawTransaction")

        # Handle batch requests
        elif isinstance(request_data, list):
            for item in request_data:
                if isinstance(item, dict) and item.get("method") == "eth_sendRawTransaction":
                    params = item.get("params", [])
                    if params and len(params) > 0:
                        raw_tx = params[0]

                        # Increment counter
                        tx_counter += 1

                        # Create transaction record
                        tx_record = {
                            "id": tx_counter,
                            "method": "eth_sendRawTransaction",
                            "raw_tx": raw_tx,
                            "timestamp": flow.request.timestamp_start,
                        }

                        # Append to JSONL file
                        with open(TRANSACTIONS_FILE, 'a') as f:
                            f.write(json.dumps(tx_record) + '\n')

                        ctx.log.info(f"[TX {tx_counter}] Captured eth_sendRawTransaction (batch)")

    except (json.JSONDecodeError, KeyError, TypeError) as e:
        # Not a valid JSON-RPC request or doesn't have the expected structure
        pass
    except Exception as e:
        ctx.log.error(f"Error capturing transaction: {e}")
