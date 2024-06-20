ethereum_package = import_module(
    "github.com/kurtosis-tech/ethereum-package/main.star@3.0.0"
)

GETH_IMAGE = "ethereum/client-go:v1.14.0"
LIGHTHOUSE_IMAGE = "sigp/lighthouse:v5.2.0"


def run(plan, args):
    ethereum_package.run(
        plan,
        {
            "participants": [
                {
                    # Execution layer (EL)
                    "el_type": "geth",
                    "el_image": GETH_IMAGE,
                    # Consensus layer (CL)
                    "cl_type": "lighthouse",
                    "cl_image": LIGHTHOUSE_IMAGE,
                    "count": 1,
                }
            ],
            "network_params": {
                # The ethereum package requires the network id to be a string.
                "network_id": str(args["l1_chain_id"]),
                "preregistered_validator_keys_mnemonic": args[
                    "l1_preallocated_mnemonic"
                ],
                "dencun_fork_epoch": 0,
                "electra_fork_epoch": 100000000,
                "prague_fork_epoch": 100000000,
                ## Use these parameters for rapid testing and development.
                # This setting reduces the number of seconds per slot on the Beacon chain to,
                # allowing for faster progression through slots and epochs.
                # "seconds_per_slot": 1,
                # The "minimal" preset will pin up a network with minimal preset. It will take
                # approximately 192 seconds to get to finalized epoch vs 1536 seconds with "mainnet"
                # preset (default).
                # Please note that minimal preset requires alternative client images.
                # "preset": "minimal",
                "preset": args["l1_preset"],
                "seconds_per_slot": args["l1_seconds_per_slot"],
            },
            "additional_services": args["l1_additional_services"],
        },
    )
