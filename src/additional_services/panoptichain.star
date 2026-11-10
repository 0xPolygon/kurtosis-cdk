constants = import_module("../package_io/constants.star")
ports_package = import_module("../package_io/ports.star")
contracts_util = import_module("../contracts/util.star")
wallet_module = import_module("../wallet/wallet.star")

# https://github.com/0xPolygon/panoptichain/releases
PANOPTICHAIN_IMAGE = "ghcr.io/0xpolygon/panoptichain:v8.1.4"


def run(plan, args, contract_setup_addresses):
    panoptichain_config_artifact = get_panoptichain_config(
        plan, args, contract_setup_addresses
    )
    (ports, public_ports) = get_panoptichain_ports(args)
    plan.add_service(
        name="panoptichain" + args["deployment_suffix"],
        config=ServiceConfig(
            image=PANOPTICHAIN_IMAGE,
            ports=ports,
            public_ports=public_ports,
            files={"/etc/panoptichain": panoptichain_config_artifact},
        ),
    )


def get_panoptichain_config(plan, args, contract_setup_addresses):
    panoptichain_config_template = read_file(
        src="../../static_files/additional_services/panoptichain/config.yml"
    )
    l2_rpc_url = contracts_util.get_l2_rpc_url(plan, args)

    # cast wallet address --mnemonic "{{.l1_preallocated_mnemonic}}"
    sender_address = "0x8943545177806ED17B9F23F0a21ee5948eCaa776"

    # The L2 time to mine provider sends a transaction every interval. The sender is only
    # prefunded on L2 for cdk-erigon chains (see `l2_accounts_to_fund`).
    wallet_module.fund(
        plan,
        address=sender_address,
        rpc_url=l2_rpc_url.http,
        funder_private_key=args["l2_admin_private_key"],
        value="10ether",
    )

    panoptichain_data = {
        "l2_rpc_url": l2_rpc_url.http,
        "l1_sender_address": sender_address,
        "l2_sender_address": sender_address,
        # cast wallet private-key "{{.l1_preallocated_mnemonic}}" | cut -c3-
        "l1_sender_private_key": "bcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31",
        "l2_sender_private_key": "bcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31",
        # cast wallet address --mnemonic "code code code code code code code code code code code quality"
        "l1_receiver_address": "0x85dA99c8a7C2C95964c8EfD687E95E632Fc533D6",
        "l2_receiver_address": "0x85dA99c8a7C2C95964c8EfD687E95E632Fc533D6",
        # Only cdk-erigon serves the zkevm_* batch methods.
        "l2_polygon_zkevm": "true"
        if args["sequencer_type"] == constants.SEQUENCER_TYPE.cdk_erigon
        else "false",
    }

    return plan.render_templates(
        name="panoptichain-config",
        config={
            "config.yml": struct(
                template=panoptichain_config_template,
                data=panoptichain_data | args | contract_setup_addresses,
            )
        },
    )


def get_panoptichain_ports(args):
    ports = {
        "prometheus": PortSpec(9090, application_protocol="http"),
    }
    public_ports = ports_package.get_public_ports(
        ports, "panoptichain_start_port", args
    )
    return (ports, public_ports)
