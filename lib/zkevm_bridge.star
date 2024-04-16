def create_bridge_service_config(args, config_artifact, claimtx_keystore_artifact):
    bridge_service_name = "zkevm-bridge-service" + args["deployment_suffix"]
    bridge_service_config = ServiceConfig(
        image=args["zkevm_bridge_service_image"],
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
                artifact_names=[config_artifact, claimtx_keystore_artifact]
            ),
        },
        entrypoint=[
            "/app/zkevm-bridge",
        ],
        cmd=["run", "--cfg", "/etc/zkevm/bridge-config.toml"],
    )
    return {bridge_service_name: bridge_service_config}


def start_bridge_ui(plan, args, config):
    # Start the bridge ui.
    bridge_ui_service = plan.add_service(
        name="zkevm-bridge-ui" + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["zkevm_bridge_ui_image"],
            ports={
                "bridge-ui": PortSpec(
                    args["zkevm_bridge_ui_port"], application_protocol="http"
                ),
            },
            env_vars={
                "ETHEREUM_RPC_URL": "/l1rpc",
                "POLYGON_ZK_EVM_RPC_URL": "/zkevmrpc",
                "BRIDGE_API_URL": "/bridgeapi",
                "ETHEREUM_BRIDGE_CONTRACT_ADDRESS": config.zkevm_bridge_address,
                "POLYGON_ZK_EVM_BRIDGE_CONTRACT_ADDRESS": config.zkevm_bridge_address,
                "ETHEREUM_FORCE_UPDATE_GLOBAL_EXIT_ROOT": "true",
                "ETHEREUM_PROOF_OF_EFFICIENCY_CONTRACT_ADDRESS": config.zkevm_rollup_address,
                "ETHEREUM_ROLLUP_MANAGER_ADDRESS": config.zkevm_rollup_manager_address,
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
    bridge_ui_url = "http://{}:{}".format(
        bridge_ui_service.ip_address, bridge_ui_service.ports["bridge-ui"].number
    )

    # Start the bridge ui gateway.
    nginx_config_template = read_file(src="../templates/bridge-infra/default.conf")
    nginx_config_artifact = plan.render_templates(
        name="nginx-config-artifact",
        config={
            "nginx.conf": struct(
                template=nginx_config_template,
                data={
                    "l1_rpc_url": config.l1_rpc_url,
                    "zkevm_rpc_url": config.zkevm_rpc_url,
                    "zkevm_bridge_api_url": config.bridge_api_url,
                    "zkevm_bridge_ui_url": bridge_ui_url,
                },
            )
        },
    )
    plan.add_service(
        name="zkevm-bridge-ui-gateway" + args["deployment_suffix"],
        config=ServiceConfig(
            image="nginx:latest",
            ports={
                "http": PortSpec(number=80),
            },
            files={
                "/etc/nginx/conf.d": nginx_config_artifact,
            },
        ),
    )
