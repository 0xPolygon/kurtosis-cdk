ethereum_package = import_module(
    "github.com/ethpandaops/ethereum-package/main.star@4.3.0"
)


def run(plan, args):
    static_port_config = args.get("static_ports")
    l1_el_start_port = static_port_config.get("l1_el_start_port", None)
    l1_cl_start_port = static_port_config.get("l1_cl_start_port", None)
    l1_vc_start_port = static_port_config.get("l1_vc_start_port", None)
    l1_remote_signer_start_port = static_port_config.get(
        "l1_remote_signer_start_port", None
    )
    l1_additional_services_start_port = static_port_config.get(
        "l1_additional_services_start_port", None
    )

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
            # static ports
            "port_publisher": {
                "el": {
                    "enabled": True,
                    "public_port_start": l1_el_start_port,
                },
                "cl": {
                    "enabled": True,
                    "public_port_start": l1_cl_start_port,
                },
                "vc": {
                    "enabled": True,
                    "public_port_start": l1_vc_start_port,
                },
                "remote_signer": {
                    "enabled": True,
                    "public_port_start": l1_remote_signer_start_port,
                },
                "additional_services": {
                    "enabled": True,
                    "public_port_start": l1_additional_services_start_port,
                },
            },
        },
    )
