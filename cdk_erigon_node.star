def run(plan, args):
    config_template = read_file("./templates/cdk-erigon-node.yaml")
    config_data = {
        "l1_network_id": args["l1_network_id"],
        "l1_rpc_url": args["l1_rpc_url"],
        "l1_rollup_address": args["l1_rollup_address"],
        "l1_polygon_rollup_manager_address": args["l1_polygon_rollup_manager_address"],
        "l1_matic_contract_address": args["l1_matic_contract_address"],
        "l1_ger_manager_contract_address": args["l1_ger_manager_contract_address"],
        "l2_chain_id": args["zkevm_l2_chain_id"],
        "l2_sequencer_rpc_url": args["l2_sequencer_rpc_url"],
        "l2_datastreamer_url": args["l2_datastreamer_url"],
    }
    config = plan.render_templates(
        config={"config.yaml": struct(template=config_template, data=config_data)},
        name="cdk-erigon-config",
    )

    plan.add_service(
        name="cdk-erigon-node",
        config=ServiceConfig(
            # TODO: Use the cdk-erigon docker image once released by the team instead of building it.
            image=ImageBuildSpec(
                image_name="cdk-erigon",
                build_context_dir=".",
                build_file="cdk-erigon-debug.Dockerfile",
            ),
            files={
                "/etc/cdk-erigon": config,
            },
            ports={"http_rpc": PortSpec(8545, application_protocol="http", wait="4s")},
            cmd=["--config=/etc/cdk-erigon/config.yaml", "--maxpeers=0"],
        ),
    )
