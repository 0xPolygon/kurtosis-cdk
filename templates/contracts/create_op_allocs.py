import json

genesis_polygon = "/opt/zkevm/sovereign-predeployed-genesis.json"
predeployed_allocs = "/opt/zkevm/predeployed_allocs.json"

# Load the genesis file
import json

with open(genesis_polygon, "r") as fg_polygon:
    genesis_polygon = json.load(fg_polygon)

allocs = {}

# Determine the correct part of the JSON to iterate over
if "genesis" in genesis_polygon:
    if isinstance(genesis_polygon["genesis"], list):
        items = genesis_polygon["genesis"]
    elif isinstance(genesis_polygon["genesis"], dict):
        items = genesis_polygon["genesis"].get("alloc", {})
    else:
        raise ValueError("Unexpected structure in 'genesis' field")
else:
    items = genesis_polygon

# Handle different possible structures
if isinstance(items, dict):
    for addr, data in items.items():
        addr = addr.lower()
        # Handle balance: ensure it's treated as a hex string
        balance = data.get("balance", "0x0")
        if isinstance(balance, str) and balance.startswith("0x"):
            balance_value = int(balance, 16)
        else:
            balance_value = int(balance)  # Assume decimal if not hex
        allocs[addr] = {"balance": hex(balance_value)}

        # Handle nonce: ensure it's treated as a hex string
        if "nonce" in data:
            nonce = data["nonce"]
            if isinstance(nonce, str) and nonce.startswith("0x"):
                nonce_value = int(nonce, 16)
            else:
                nonce_value = int(nonce)  # Assume decimal if not hex
            allocs[addr]["nonce"] = hex(nonce_value)

        if "bytecode" in data:
            allocs[addr]["code"] = data["bytecode"]
        if "code" in data:
            allocs[addr]["code"] = data["code"]
        if "storage" in data:
            allocs[addr]["storage"] = data["storage"]
elif isinstance(items, list):
    for item in items:
        if not isinstance(item, dict) or "address" not in item:
            continue
        addr = item["address"].lower()
        # Handle balance: ensure it's treated as a hex string
        balance = item.get("balance", "0x0")
        if isinstance(balance, str) and balance.startswith("0x"):
            balance_value = int(balance, 16)
        else:
            balance_value = int(balance)  # Assume decimal if not hex
        allocs[addr] = {"balance": hex(balance_value)}

        # Handle nonce: ensure it's treated as a hex string
        if "nonce" in item:
            nonce = item["nonce"]
            if isinstance(nonce, str) and nonce.startswith("0x"):
                nonce_value = int(nonce, 16)
            else:
                nonce_value = int(nonce)  # Assume decimal if not hex
            allocs[addr]["nonce"] = hex(nonce_value)

        if "bytecode" in item:
            allocs[addr]["code"] = item["bytecode"]
        if "code" in item:
            allocs[addr]["code"] = item["code"]
        if "storage" in item:
            allocs[addr]["storage"] = item["storage"]
else:
    raise ValueError("Unexpected JSON structure")

# Write the output file
with open(predeployed_allocs, "w") as fg_output:
    json.dump(allocs, fg_output, indent=4)
    print(f"Predeployed Allocs file saved: {predeployed_allocs}")
