constants = import_module("../../src/package_io/constants.star")


def run(plan, args, contract_setup_addresses):
    l2_rpc_service = plan.get_service(args["l2_rpc_name"] + args["deployment_suffix"])
    l2_rpc_url = "http://{}:{}".format(
        l2_rpc_service.ip_address, l2_rpc_service.ports["rpc"].number
    )
    bridge_spammer_config_artifact = plan.render_templates(
        name="bridge-spammer-script",
        config={
            "spam.sh": struct(
                template=read_file(
                    src="../../static_files/additional_services/bridge-spammer-config/spam.sh"
                ),
                data={
                    "l2_rpc_url": l2_rpc_url,
                    "zkevm_l2_admin_private_key": args["zkevm_l2_admin_private_key"],
                    "zkevm_l2_claimtxmanager_address": args[
                        "zkevm_l2_claimtxmanager_address"
                    ],
                    "l1_rpc_url": args["l1_rpc_url"],
                    "l1_chain_id": args["l1_chain_id"],
                    "zkevm_rollup_chain_id": args["zkevm_rollup_chain_id"],
                    "zkevm_bridge_address": contract_setup_addresses[
                        "zkevm_bridge_address"
                    ],
                },
            ),
        },
    )

    plan.add_service(
        name="bridge-spammer" + args["deployment_suffix"],
        config=ServiceConfig(
            image=constants.TOOLBOX_IMAGE,
            files={
                "/opt/scripts": Directory(
                    artifact_names=[bridge_spammer_config_artifact]
                ),
            },
            entrypoint=["bash", "-c"],
            cmd=["chmod +x /opt/scripts/spam.sh && /opt/scripts/spam.sh"],
        ),
    )
