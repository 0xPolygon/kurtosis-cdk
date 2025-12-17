constants = import_module("./src/package_io/constants.star")
databases = import_module("./src/chain/shared/databases.star")
zkevm_bridge_service = import_module("./src/chain/shared/zkevm-bridge/service.star")
zkevm_bridge_ui = import_module("./src/chain/shared/zkevm-bridge/ui.star")
zkevm_bridge_proxy = import_module("./src/chain/shared/zkevm-bridge/proxy.star")


def run(
    plan,
    args,
    contract_setup_addresses,
    deploy_bridge_ui=True,
):
    db_configs = databases.get_db_configs(
        args["deployment_suffix"], args["sequencer_type"]
    )

    # Start the bridge service.
    bridge_config_artifact = create_bridge_config_artifact(
        plan,
        args,
        contract_setup_addresses,
        db_configs,
    )
    claimsponsor_keystore_artifact = plan.store_service_files(
        name="claimsponsor-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src=constants.KEYSTORES_DIR + "/claimsponsor.keystore",
    )
    zkevm_bridge_service.run(
        plan, args, bridge_config_artifact, claimsponsor_keystore_artifact
    )

    if deploy_bridge_ui:
        zkevm_bridge_ui.run(plan, args, contract_setup_addresses)

        # Start the bridge UI reverse proxy. This is only relevant / needed if we have a fake l1
        if args["use_local_l1"]:
            zkevm_bridge_proxy.run(plan, args)


def create_bridge_config_artifact(plan, args, contract_setup_addresses, db_configs):
    bridge_config_template = read_file(
        src="./static_files/zkevm-bridge/service/config.toml"
    )
    l1_rpc_url = args["mitm_rpc_url"].get("bridge", args["l1_rpc_url"])
    l2_rpc_url = "http://{}{}:{}".format(
        args["l2_rpc_name"], args["deployment_suffix"], args["zkevm_rpc_http_port"]
    )

    consensus_contract_type = args["consensus_contract_type"]
    require_sovereign_chain_contract = (
        (
            consensus_contract_type == constants.CONSENSUS_TYPE.pessimistic
            and args["sequencer_type"] == constants.SEQUENCER_TYPE.op_geth
        )
        or consensus_contract_type == constants.CONSENSUS_TYPE.ecdsa_multisig
        or consensus_contract_type == constants.CONSENSUS_TYPE.fep
    )

    return plan.render_templates(
        name="bridge-config-artifact",
        config={
            "bridge-config.toml": struct(
                template=bridge_config_template,
                data={
                    "log_level": args.get("log_level"),
                    "environment": args.get("environment"),
                    "l2_keystore_password": args["l2_keystore_password"],
                    "db": db_configs.get("bridge_db"),
                    "require_sovereign_chain_contract": require_sovereign_chain_contract,
                    "sequencer_type": args["sequencer_type"],
                    # rpc urls
                    "l1_rpc_url": l1_rpc_url,
                    "l2_rpc_url": l2_rpc_url,
                    # ports
                    "grpc_port_number": args["zkevm_bridge_grpc_port"],
                    "rpc_port_number": args["zkevm_bridge_rpc_port"],
                    "metrics_port_number": args["zkevm_bridge_metrics_port"],
                }
                | contract_setup_addresses,
            )
        },
    )
