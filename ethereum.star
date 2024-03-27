ethereum_package = import_module(
    "github.com/kurtosis-tech/ethereum-package/main.star@2.0.0"
)


def run(plan, args):
    ethereum_package.run(
        plan,
        {
            "network_params": {
                # The ethereum package requires the network id to be a string.
                "network_id": str(args["l1_chain_id"]),
                "preregistered_validator_keys_mnemonic": args[
                    "l1_preallocated_mnemonic"
                ],
            },
            "additional_services": [],
        },
    )
