"""
Transaction Capture MITM Script
Logs all eth_sendRawTransaction calls for replay
"""
import json
from pathlib import Path
from mitmproxy import http

class TransactionCapture:
    def __init__(self):
        self.output_file = Path("/data/transactions.jsonl")
        self.tx_count = 0

    def request(self, flow: http.HTTPFlow):
        """Intercept and log eth_sendRawTransaction requests"""
        try:
            if flow.request.method == "POST":
                content = json.loads(flow.request.content)

                # Capture raw transaction submissions
                if content.get("method") == "eth_sendRawTransaction":
                    raw_tx = content.get("params", [])[0]

                    # Log transaction
                    log_entry = {
                        "tx_number": self.tx_count,
                        "method": "eth_sendRawTransaction",
                        "raw_tx": raw_tx,
                        "timestamp": flow.request.timestamp_start,
                    }

                    with open(self.output_file, "a") as f:
                        f.write(json.dumps(log_entry) + "\n")

                    self.tx_count += 1
        except Exception:
            pass  # Don't break proxy on errors

addons = [TransactionCapture()]
