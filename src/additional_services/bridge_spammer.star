constants = import_module("../../src/package_io/constants.star")
wallet_module = import_module("../wallet/wallet.star")


def run(plan, args, contract_setup_addresses):
    l1_rpc_url = args.get("l1_rpc_url")
    l2_rpc_service = plan.get_service(
        args.get("l2_rpc_name") + args.get("deployment_suffix")
    )
    l2_rpc_url = "http://{}:{}".format(
        l2_rpc_service.ip_address, l2_rpc_service.ports["rpc"].number
    )

    # Generate a new wallet and fund it on L1 and L2.
    funder_private_key = args.get("zkevm_l2_admin_private_key")
    wallet = wallet_module.new(plan)
    wallet_module.fund(
        plan,
        address=wallet.address,
        rpc_url=l1_rpc_url,
        funder_private_key=funder_private_key,
    )
    wallet_module.fund(
        plan,
        address=wallet.address,
        rpc_url=l2_rpc_url,
        funder_private_key=funder_private_key,
    )

    bridge_spammer_config_artifact = plan.render_templates(
        name="bridge-spammer-script",
        config={
            "spam.sh": struct(
                template=read_file(
                    src="../../static_files/additional_services/bridge-spammer-config/spam.sh"
                ),
                data={
                    "private_key": wallet.private_key,
                    "address": wallet.address,
                    "l1_rpc_url": l1_rpc_url,
                    "l1_chain_id": args.get("l1_chain_id"),
                    "l2_rpc_url": l2_rpc_url,
                    "zkevm_l2_claimtxmanager_address": args.get(
                        "zkevm_l2_claimtxmanager_address"
                    ),
                    "zkevm_rollup_chain_id": args.get("zkevm_rollup_chain_id"),
                    "zkevm_bridge_address": contract_setup_addresses.get(
                        "zkevm_bridge_address"
                    ),
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
