ethereum_package = import_module(
    "github.com/ethpandaops/ethereum-package/main.star@4.3.0"
)


def run(plan, args):
    ethereum_package.run(
        plan,
        {
            "participants": [
                {
                    "el_type": "geth",
                    "cl_type": "lighthouse",
                    "el_extra_params": [
                        "--gcmode archive"
                    ]
                }
            ],
            "network_params": {
                "network_id": str(args["l1_chain_id"]),
                "preregistered_validator_keys_mnemonic": args[
                    "l1_preallocated_mnemonic"
                ],
                # This setting reduces the number of seconds per slot on the Beacon chain to,
                # allowing for faster progression through slots and epochs.
                "preset": args["l1_preset"],
                # The "minimal" preset will pin up a network with minimal preset. It will take
                # approximately 192 seconds to get to finalized epoch vs 1536 seconds with "mainnet"
                # preset (default).
                "seconds_per_slot": args["l1_seconds_per_slot"],
            },
            "additional_services": args["l1_additional_services"],
        },
    )
