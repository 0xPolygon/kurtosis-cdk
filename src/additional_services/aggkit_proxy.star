# Standalone aggkit-proxy service (additional service "aggkit_proxy").
#
# Runs the aggkit-proxy binary with --components=proxy,tracker:
# - proxy: a stateless REST reverse proxy in front of every network's aggkit
#   bridge REST service, routing /bridge/v1/* by the mandatory network_id query
#   parameter.
# - tracker: serves /tracker/v1 (bridge tracking), reading agglayer state through
#   [Tracker.AgglayerClient.GRPC] (see config.toml).
#
# Every network's bridge service and RPC URL is listed statically in
# aggkit_proxy_bridge_urls and aggkit_proxy_rpc_urls, since on-chain resolution
# does not apply here (network 0, L1, is never enumerated on-chain).

AGGKIT_PROXY_REST_PORT = 8080
AGGKIT_PROXY_CONFIG_TEMPLATE = (
    "../../static_files/additional_services/aggkit-proxy/config.toml"
)
AGGKIT_PROXY_SERVICE_NAME = "aggkit-proxy-001"


def run(plan, args, contract_setup_addresses):
    config_artifact = _render_config(plan, args, contract_setup_addresses)

    service_config = ServiceConfig(
        image=args["aggkit_image"],
        ports={
            "rest": PortSpec(
                AGGKIT_PROXY_REST_PORT,
                application_protocol="http",
                wait=None,
            ),
        },
        files={
            "/etc/aggkit-proxy": Directory(artifact_names=[config_artifact]),
        },
        # The image's entrypoint is aggkit; the proxy binary is in the same image.
        entrypoint=["/usr/local/bin/aggkit-proxy"],
        cmd=[
            "run",
            "--cfg=/etc/aggkit-proxy/config.toml",
            "--components=proxy,tracker",
        ],
    )

    plan.add_service(name=AGGKIT_PROXY_SERVICE_NAME, config=service_config)


def _render_config(plan, args, contract_setup_addresses):
    config_template = read_file(src=AGGKIT_PROXY_CONFIG_TEMPLATE)

    template_data = {
        "l1_rpc_url": args["l1_rpc_url"],
        "rollup_manager_address": contract_setup_addresses["rollup_manager_address"],
        "l1_global_exit_root_address": contract_setup_addresses["l1_ger_address"],
        "aggkit_proxy_bridge_urls": args.get("aggkit_proxy_bridge_urls", []),
        "aggkit_proxy_rpc_urls": args.get("aggkit_proxy_rpc_urls", []),
        "agglayer_grpc_url": args["agglayer_grpc_url"],
    }

    return plan.render_templates(
        name="aggkit-proxy-config",
        config={
            "config.toml": struct(
                template=config_template,
                data=template_data,
            )
        },
    )
