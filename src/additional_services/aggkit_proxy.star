# Standalone aggkit-proxy service (additional service "aggkit_proxy").
#
# Runs the `aggkit-proxy` binary (bundled in the same image as `aggkit`,
# entrypoint overridden explicitly since the image's own ENTRYPOINT is
# `aggkit`) in --components=proxy mode: a single stateless REST reverse
# proxy in front of every participating network's aggkit bridge REST
# service, routing ANY /bridge/v1/*any by the mandatory `network_id` query
# param. It has no health endpoint of its own in proxy-only mode.
#
# On-chain resolution isn't usable in this package (no BRIDGE_SERVICE_URL
# aggchain metadata registered, and network 0/L1 is never enumerated
# on-chain regardless), so every participating network's bridge service and
# RPC URL must be listed statically via aggkit_proxy_bridge_urls /
# aggkit_proxy_rpc_urls (see input_parser.star) -- same deterministic
# ahead-of-time pattern used for agglayer_extra_rollups and
# aggkit_autoclaim_bridge_urls.

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
        # The image's ENTRYPOINT is `aggkit`, not `aggkit-proxy` -- it must be
        # overridden explicitly to run the proxy binary, which lives in the
        # same image at /usr/local/bin/aggkit-proxy.
        entrypoint=["/usr/local/bin/aggkit-proxy"],
        cmd=[
            "run",
            "--cfg=/etc/aggkit-proxy/config.toml",
            "--components=proxy",
        ],
    )

    plan.add_service(name=AGGKIT_PROXY_SERVICE_NAME, config=service_config)


def _render_config(plan, args, contract_setup_addresses):
    config_template = read_file(src=AGGKIT_PROXY_CONFIG_TEMPLATE)

    template_data = {
        "l1_rpc_url": args["l1_rpc_url"],
        "rollup_manager_address": contract_setup_addresses["rollup_manager_address"],
        "aggkit_proxy_bridge_urls": args.get("aggkit_proxy_bridge_urls", []),
        "aggkit_proxy_rpc_urls": args.get("aggkit_proxy_rpc_urls", []),
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
