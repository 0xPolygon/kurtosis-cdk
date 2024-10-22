ethereum_package = import_module(
    "github.com/ethpandaops/ethereum-package/main.star@4.3.0"
)


def run(plan, args):
    port_publisher = generate_port_publisher_config(args)
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
            "port_publisher": port_publisher,
        },
    )


# Generate ethereum package static ports configuration.
def generate_port_publisher_config(args):
    port_mappings = {
        "el": "l1_el_start_port",
        "cl": "l1_cl_start_port",
        "vc": "l1_vc_start_port",
        "additional_services": "l1_additional_services_start_port",
    }

    port_publisher_config = {}
    static_port_config = args.get("static_ports", {})
    for key, value in port_mappings.items():
        public_port_start = static_port_config.get(value, None)
        if public_port_start:
            port_publisher_config[key] = {
                "enabled": True,
                "public_port_start": public_port_start,
            }
    return port_publisher_config
