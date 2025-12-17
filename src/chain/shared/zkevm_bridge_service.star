constants = import_module("../../package_io/constants.star")
databases = import_module("./databases.star")


# Port identifiers and numbers.
RPC_PORT_ID = "rpc"
RPC_PORT_NUMBER = 8080

GRPC_PORT_ID = "grpc"
GRPC_PORT_NUMBER = 9090

METRICS_PORT_ID = "prometheus"
METRICS_PORT_NUMBER = 8090


def run(plan, args, contract_setup_addresses):
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

    db_configs = databases.get_db_configs(
        args["deployment_suffix"], args["sequencer_type"]
    )

    config_artifact = plan.render_templates(
        name="bridge-config-artifact",
        config={
            "bridge-config.toml": struct(
                template=read_file(
                    src="../../../static_files/zkevm-bridge-service/config.toml"
                ),
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

    claimsponsor_keystore_artifact = plan.store_service_files(
        name="claimsponsor-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src=constants.KEYSTORES_DIR + "/claimsponsor.keystore",
    )

    plan.add_service(
        name="zkevm-bridge-service{}".format(args.get("deployment_suffix")),
        config=ServiceConfig(
            image=args.get("zkevm_bridge_service_image"),
            files={
                "/etc/zkevm": Directory(
                    artifact_names=[config_artifact, claimsponsor_keystore_artifact]
                ),
            },
            ports={
                RPC_PORT_ID: PortSpec(RPC_PORT_NUMBER, application_protocol="http"),
                GRPC_PORT_ID: PortSpec(GRPC_PORT_NUMBER, application_protocol="grpc"),
                METRICS_PORT_ID: PortSpec(
                    METRICS_PORT_NUMBER, application_protocol="http"
                ),
            },
            entrypoint=[
                "/app/zkevm-bridge",
            ],
            cmd=["run", "--cfg", "/etc/zkevm/bridge-config.toml"],
        ),
    )
