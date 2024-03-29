service_package = import_module("./lib/service.star")


def run(plan, args):
    zkevm_bridge_service = start_bridge_service(plan, args)
    start_bridge_ui(plan, args, zkevm_bridge_service)
    start_agglayer(plan, args)


def start_bridge_service(plan, args):
    # Create bridge config.
    bridge_config_template = read_file(src="./templates/bridge-config.toml")
    rollup_manager_block_number = get_key_from_config(
        plan, args, "deploymentRollupManagerBlockNumber"
    )
    zkevm_global_exit_root_address = get_key_from_config(
        plan, args, "polygonZkEVMGlobalExitRootAddress"
    )
    zkevm_bridge_address = get_key_from_config(plan, args, "polygonZkEVMBridgeAddress")
    zkevm_rollup_manager_address = get_key_from_config(
        plan, args, "polygonRollupManagerAddress"
    )
    claimtx_keystore_artifact = plan.store_service_files(
        name="claimtxmanager-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/claimtxmanager.keystore",
    )
    zkevm_rollup_address = get_key_from_config(plan, args, "rollupAddress")
    bridge_config_artifact = plan.render_templates(
        name="bridge-config-artifact",
        config={
            "bridge-config.toml": struct(
                template=bridge_config_template,
                data={
                    "deployment_suffix": args["deployment_suffix"],
                    "l1_rpc_url": args["l1_rpc_url"],
                    "zkevm_l2_keystore_password": args["zkevm_l2_keystore_password"],
                    # addresses
                    "rollup_manager_block_number": rollup_manager_block_number,
                    "zkevm_bridge_address": zkevm_bridge_address,
                    "zkevm_global_exit_root_address": zkevm_global_exit_root_address,
                    "zkevm_rollup_manager_address": zkevm_rollup_manager_address,
                    "zkevm_rollup_address": zkevm_rollup_address,
                    # bridge db
                    "zkevm_db_bridge_hostname": args["zkevm_db_bridge_hostname"],
                    "zkevm_db_bridge_name": args["zkevm_db_bridge_name"],
                    "zkevm_db_bridge_user": args["zkevm_db_bridge_user"],
                    "zkevm_db_bridge_password": args["zkevm_db_bridge_password"],
                    # ports
                    "zkevm_db_postgres_port": args["zkevm_db_postgres_port"],
                    "zkevm_bridge_grpc_port": args["zkevm_bridge_grpc_port"],
                    "zkevm_bridge_rpc_port": args["zkevm_bridge_rpc_port"],
                    "zkevm_rpc_http_port": args["zkevm_rpc_http_port"],
                },
            )
        },
    )

    # Start bridge service.
    return plan.add_service(
        name="zkevm-bridge-service" + args["deployment_suffix"],
        config=ServiceConfig(
            image="hermeznetwork/zkevm-bridge-service:v0.4.2",
            ports={
                "bridge-rpc": PortSpec(
                    args["zkevm_bridge_rpc_port"], application_protocol="http"
                ),
                "bridge-grpc": PortSpec(
                    args["zkevm_bridge_grpc_port"], application_protocol="grpc"
                ),
            },
            files={
                "/etc/zkevm": Directory(
                    artifact_names=[bridge_config_artifact, claimtx_keystore_artifact]
                ),
            },
            entrypoint=[
                "/app/zkevm-bridge",
            ],
            cmd=["run", "--cfg", "/etc/zkevm/bridge-config.toml"],
        ),
    )


def start_bridge_ui(plan, args, bridge_service):
    l1_eth_service = plan.get_service(name="el-1-geth-lighthouse")
    zkevm_node_rpc = plan.get_service(name="zkevm-node-rpc" + args["deployment_suffix"])
    zkevm_bridge_address = get_key_from_config(plan, args, "polygonZkEVMBridgeAddress")
    zkevm_rollup_manager_address = get_key_from_config(
        plan, args, "polygonRollupManagerAddress"
    )
    zkevm_rollup_address = get_key_from_config(plan, args, "rollupAddress")
    polygon_zkevm_rpc_http_port = zkevm_node_rpc.ports["http-rpc"]
    bridge_api_http_port = bridge_service.ports["bridge-rpc"]

    # Start bridge UI.
    plan.add_service(
        name="zkevm-bridge-ui" + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["zkevm_bridge_ui_image"],
            ports={
                "bridge-ui": PortSpec(
                    args["zkevm_bridge_ui_port"], application_protocol="http"
                ),
            },
            env_vars={
                "ETHEREUM_RPC_URL": "http://{}:{}".format(
                    l1_eth_service.ip_address, l1_eth_service.ports["rpc"].number
                ),
                "POLYGON_ZK_EVM_RPC_URL": "http://{}:{}".format(
                    zkevm_node_rpc.ip_address,
                    polygon_zkevm_rpc_http_port.number,
                ),
                "BRIDGE_API_URL": "http://{}:{}".format(
                    bridge_service.ip_address, bridge_api_http_port.number
                ),
                "ETHEREUM_BRIDGE_CONTRACT_ADDRESS": zkevm_bridge_address,
                "POLYGON_ZK_EVM_BRIDGE_CONTRACT_ADDRESS": zkevm_bridge_address,
                "ETHEREUM_FORCE_UPDATE_GLOBAL_EXIT_ROOT": "true",
                "ETHEREUM_PROOF_OF_EFFICIENCY_CONTRACT_ADDRESS": zkevm_rollup_address,
                "ETHEREUM_ROLLUP_MANAGER_ADDRESS": zkevm_rollup_manager_address,
                "ETHEREUM_EXPLORER_URL": args["l1_explorer_url"],
                "POLYGON_ZK_EVM_EXPLORER_URL": args["polygon_zkevm_explorer"],
                "POLYGON_ZK_EVM_NETWORK_ID": "1",
                "ENABLE_FIAT_EXCHANGE_RATES": "false",
                "ENABLE_OUTDATED_NETWORK_MODAL": "false",
                "ENABLE_DEPOSIT_WARNING": "true",
                "ENABLE_REPORT_FORM": "false",
            },
            cmd=["run"],
        ),
    )


def start_agglayer(plan, args):
    # Create agglayer config.
    agglayer_config_template = read_file(src="./templates/agglayer-config.toml")
    rollup_manager_address = get_key_from_config(
        plan, args, "polygonRollupManagerAddress"
    )
    agglayer_keystore_artifact = plan.store_service_files(
        name="agglayer-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/agglayer.keystore",
    )
    agglayer_config_artifact = plan.render_templates(
        name="agglayer-config-artifact",
        config={
            "agglayer-config.toml": struct(
                template=agglayer_config_template,
                # TODO: Organize those args.
                data={
                    "deployment_suffix": args["deployment_suffix"],
                    "l1_chain_id": args["l1_chain_id"],
                    "l1_rpc_url": args["l1_rpc_url"],
                    "zkevm_l2_keystore_password": args["zkevm_l2_keystore_password"],
                    # addresses
                    "rollup_manager_address": rollup_manager_address,
                    "zkevm_l2_proofsigner_address": args["zkevm_l2_proofsigner_address"],
                    # agglayer db
                    "zkevm_db_agglayer_hostname": args["zkevm_db_agglayer_hostname"],
                    "zkevm_db_agglayer_name": args["zkevm_db_agglayer_name"],
                    "zkevm_db_agglayer_user": args["zkevm_db_agglayer_user"],
                    "zkevm_db_agglayer_password": args["zkevm_db_agglayer_password"],
                    # ports
                    "zkevm_db_postgres_port": args["zkevm_db_postgres_port"],
                    "zkevm_rpc_http_port": args["zkevm_rpc_http_port"],
                    "zkevm_agglayer_port": args["zkevm_agglayer_port"],
                    "zkevm_prometheus_port": args["zkevm_prometheus_port"],
                },
            )
        },
    )

    # Start agglayer service.
    plan.add_service(
        name="zkevm-agglayer" + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["zkevm_agglayer_image"],
            ports={
                "agglayer": PortSpec(
                    args["zkevm_agglayer_port"], application_protocol="http"
                ),
                "prometheus": PortSpec(
                    args["zkevm_prometheus_port"], application_protocol="http"
                ),
            },
            files={
                "/etc/zkevm": Directory(
                    artifact_names=[
                        agglayer_config_artifact,
                        agglayer_keystore_artifact,
                    ]
                ),
            },
            entrypoint=[
                "/app/agglayer",
            ],
            cmd=["run", "--cfg", "/etc/zkevm/agglayer-config.toml"],
        ),
    )


def start_dac(plan, args):
    # Create DAC config.
    dac_config_template = read_file(src="./templates/dac-config.toml")
    rollup_address = get_key_from_config(plan, args, "rollupAddress")
    polygon_data_committee_address = get_key_from_config(
        plan, args, "polygonDataCommitteeAddress"
    )
    dac_keystore_artifact = plan.store_service_files(
        name="dac-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/dac.keystore",
    )

    dac_config_artifact = plan.render_templates(
        name="dac-config-artifact",
        config={
            "dac-config.toml": struct(
                template=dac_config_template,
                # TODO: Organize those args.
                data={
                    "deployment_suffix": args["deployment_suffix"],
                    "l1_rpc_url": args["l1_rpc_url"],
                    "l1_ws_url": args["l1_ws_url"],
                    "zkevm_l2_keystore_password": args["zkevm_l2_keystore_password"],
                    # addresses
                    "rollup_address": rollup_address,
                    "polygon_data_committee_address": polygon_data_committee_address,
                    # dac db
                    "zkevm_db_dac_hostname": args["zkevm_db_dac_hostname"],
                    "zkevm_db_dac_name": args["zkevm_db_dac_name"],
                    "zkevm_db_dac_user": args["zkevm_db_dac_user"],
                    "zkevm_db_dac_password": args["zkevm_db_dac_password"],
                    # ports
                    "zkevm_db_postgres_port": args["zkevm_db_postgres_port"],
                    "zkevm_dac_port": args["zkevm_dac_port"],
                },
            )
        },
    )

    # Start DAC service.
    plan.add_service(
        name="zkevm-dac" + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["zkevm_dac_image"],
            ports={
                "dac": PortSpec(args["zkevm_dac_port"], application_protocol="http"),
            },
            files={
                "/etc/zkevm": Directory(
                    artifact_names=[dac_config_artifact, dac_keystore_artifact]
                ),
            },
            entrypoint=[
                "/app/cdk-data-availability",
            ],
            cmd=["run", "--cfg", "/etc/zkevm/dac-config.toml"],
        ),
    )


def get_key_from_config(plan, args, key):
    return service_package.extract_json_key_from_service(
        plan,
        "contracts" + args["deployment_suffix"],
        "/opt/zkevm/combined.json",
        key,
    )
