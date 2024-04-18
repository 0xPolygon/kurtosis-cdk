ethereum_package = import_module(
    "github.com/kurtosis-tech/ethereum-package/main.star@2.1.0"
)

def run(plan, l1_chain_id, l1_preallocated_mnemonic):
    ethereum_package.run(
        plan,
        {
            "network_params": {
                # The ethereum package requires the network id to be a string.
                "network_id": str(l1_chain_id),
                "preregistered_validator_keys_mnemonic": l1_preallocated_mnemonic,
            },
            "additional_services": [],
        },
    )
