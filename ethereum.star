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
                    "el_extra_params": ["--gcmode archive"],
                }
            ],
            "network_params": {
                "network_id": str(args["l1_chain_id"]),
                "preregistered_validator_keys_mnemonic": args[
                    "l1_preallocated_mnemonic"
                ],
                "preset": args["l1_preset"],
                "seconds_per_slot": args["l1_seconds_per_slot"],
            },
            "additional_services": args["l1_additional_services"],
        },
    )
