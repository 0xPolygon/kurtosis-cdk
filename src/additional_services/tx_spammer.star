constants = import_module("../../src/package_io/constants.star")


def run(plan, args, contract_setup_addresses):
    tx_spammer_config_artifacts = get_tx_spammer_config(
        plan, args, contract_setup_addresses
    )
    plan.add_service(
        name="tx-spammer" + args["deployment_suffix"],
        config=ServiceConfig(
            image=constants.TOOLBOX_IMAGE,
            files={
                "/opt/scripts": Directory(artifact_names=[tx_spammer_config_artifacts]),
            },
            entrypoint=["bash", "-c"],
            cmd=["chmod +x /opt/scripts/*.sh && /opt/scripts/spam.sh"],
        ),
    )


def get_tx_spammer_config(plan, args, contract_setup_addresses):
    spam_script_template = read_file(
        src="../../static_files/additional_services/tx-spammer-config/spam.sh"
    )
    bridge_script_template = read_file(
        src="../../static_files/additional_services/tx-spammer-config/bridge.sh"
    )

    l2_rpc_service = plan.get_service(args["l2_rpc_name"] + args["deployment_suffix"])
    l2_rpc_url = "http://{}:{}".format(
        l2_rpc_service.ip_address, l2_rpc_service.ports["rpc"].number
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
                    "private_key": args["zkevm_l2_loadtest_private_key"],
                },
            ),
            "bridge.sh": struct(
                template=bridge_script_template,
                data={
                    "private_key": args["zkevm_l2_loadtest_private_key"],
                    "l1_rpc_url": args["l1_rpc_url"],
                    "l2_rpc_url": l2_rpc_url,
                    "zkevm_bridge_api_url": zkevm_bridge_api_url,
                }
                | contract_setup_addresses,
            ),
        },
    )
