#!/usr/bin/env python3

import sqlite3
import json
import urllib.request
import os
import sys

consensus_type = os.getenv("CONSENSUS_CONTRACT_TYPE")
args = ["pessimistic", "fep"]
if consensus_type not in args:
    print(f"Skipping check, consensus must be one of: {', '.join(args)}")
    sys.exit(0)

CertificateStatus = {
    0: "Pending",
    1: "Proven",
    2: "Candidate",
    3: "InError",
    4: "Settled",
}

agglayer_rpc_url = os.getenv("AGGLAYER_RPC_URL")
if not agglayer_rpc_url:
    raise ValueError("ERROR: No AGGLAYER_RPC_URL is set")

request = urllib.request.Request(
    agglayer_rpc_url,
    method="POST",
    headers={"Content-Type": "application/json"},
    data=json.dumps(
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "interop_getLatestKnownCertificateHeader",
            "params": [1],
        }
    ).encode("utf-8"),
)

with urllib.request.urlopen(request) as response:
    response_text = response.read().decode("utf-8")

header = json.loads(response_text)["result"]
if header is None:
    sys.exit(0)

certificate_id = header["certificate_id"]

conn = sqlite3.connect("/opt/aggkit/aggsender.sqlite")
cursor = conn.cursor()

table_name = "certificate_info"
cursor.execute(f"PRAGMA table_info({table_name});")
columns = [col[1] for col in cursor.fetchall()]

cursor.execute(f"SELECT * FROM {table_name} WHERE certificate_id='{certificate_id}';")
row = cursor.fetchone()
row_dict = dict(zip(columns, row))

assert header["height"] == row_dict["height"], (
    f"ERROR: {header['height']} != {row_dict['height']}"
)

assert header["prev_local_exit_root"] == row_dict["previous_local_exit_root"], (
    f"ERROR: {header['prev_local_exit_root']} != {row_dict['previous_local_exit_root']}"
)

assert header["new_local_exit_root"] == row_dict["new_local_exit_root"], (
    f"ERROR: {header['new_local_exit_root']} != {row_dict['new_local_exit_root']}"
)

status = CertificateStatus[row_dict["status"]]
assert header["status"] == status, f"ERROR: {header['status']} != {status}"

signed_certificate = json.loads(row_dict["signed_certificate"])
assert header["metadata"] == signed_certificate["metadata"], (
    f"ERROR: {header['metadata']} != {signed_certificate['metadata']}"
)
