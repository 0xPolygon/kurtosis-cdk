constants = import_module("../../src/package_io/constants.star")
service_package = import_module("../../lib/service.star")


def run(plan, args):
    tx_spammer_config_artifacts = get_tx_spammer_config(plan, args)
    plan.add_service(
        name="tx-spammer" + args["deployment_suffix"],
        config=ServiceConfig(
            image=constants.TX_SPAMMER_IMG,
            files={
                "/opt/scripts": Directory(artifact_names=[tx_spammer_config_artifacts]),
            },
            entrypoint=["bash", "-c"],
            cmd=["chmod +x /opt/scripts/*.sh && /opt/scripts/spam.sh"],
        ),
    )


def get_tx_spammer_config(plan, args):
    spam_script_template = read_file(
        src="../../static_files/additional_services/tx-spammer-config/spam.sh"
    )
    bridge_script_template = read_file(
        src="../../static_files/additional_services/tx-spammer-config/bridge.sh"
    )

    contract_setup_addresses = service_package.get_contract_setup_addresses(plan, args)

    # TODO: Target the rpc service instead of the sequencer once the bug as been resolved.
    # https://github.com/0xPolygon/kurtosis-cdk/issues/307
    # l2_rpc_service = plan.get_service(args["l2_rpc_name"] + args["deployment_suffix"])
    # l2_rpc_url = "http://{}:{}".format(
    #     l2_rpc_service.ip_address, l2_rpc_service.ports["rpc"].number
    # )
    l2_sequencer_service = plan.get_service(args["l2_sequencer_name"] + args["deployment_suffix"])
    l2_rpc_url = "http://{}:{}".format(
        l2_sequencer_service.ip_address, l2_sequencer_service.ports["rpc"].number
    )

    zkevm_bridge_service = plan.get_service(
        "zkevm-bridge-service" + args["deployment_suffix"]
    )
    zkevm_bridge_api_url = "http://{}:{}".format(
        zkevm_bridge_service.ip_address, zkevm_bridge_service.ports["rpc"].number
    )

    return plan.render_templates(
        name="tx-spammer-scripts",
        config={
            "spam.sh": struct(
                template=spam_script_template,
                data={
                    "rpc_url": l2_rpc_url,
                    "private_key": args["zkevm_l2_admin_private_key"],
                },
            ),
            "bridge.sh": struct(
                template=bridge_script_template,
                data={
                    "zkevm_l2_admin_private_key": args["zkevm_l2_admin_private_key"],
                    "zkevm_l2_admin_address": args["zkevm_l2_admin_address"],
                    "l1_rpc_url": args["l1_rpc_url"],
                    "l2_rpc_url": l2_rpc_url,
                    "zkevm_bridge_api_url": zkevm_bridge_api_url,
                }
                | contract_setup_addresses,
            ),
        },
    )
