constants = import_module("../../src/package_io/constants.star")


def run(plan, args, contract_setup_addresses):
    l2_rpc_service = plan.get_service(args["l2_rpc_name"] + args["deployment_suffix"])
    l2_rpc_url = "http://{}:{}".format(
        l2_rpc_service.ip_address, l2_rpc_service.ports["rpc"].number
    )
    tx_spammer_config_artifact = plan.render_templates(
        name="tx-spammer-script",
        config={
            "spam.sh": struct(
                template=read_file(
                    src="../../static_files/additional_services/tx-spammer-config/spam.sh"
                ),
                data={
                    "rpc_url": l2_rpc_url,
                    "zkevm_l2_admin_private_key": args["zkevm_l2_admin_private_key"],
                },
            ),
        },
    )

    plan.add_service(
        name="tx-spammer" + args["deployment_suffix"],
        config=ServiceConfig(
            image=constants.TOOLBOX_IMAGE,
            files={
                "/opt/scripts": Directory(artifact_names=[tx_spammer_config_artifact]),
            },
            entrypoint=["bash", "-c"],
            cmd=["chmod +x /opt/scripts/spam.sh && /opt/scripts/spam.sh"],
        ),
    )
