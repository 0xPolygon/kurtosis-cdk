constants = import_module("../../package_io/constants.star")


# Port identifiers and numbers.
SERVER_PORT_ID = "http"
SERVER_PORT_NUMBER = 80


def run(plan, args, contract_setup_addresses, l1_context, l2_context, api_url):
    bridge_ui_backend = args.get(
        "bridge_ui_backend", constants.BRIDGE_UI_BACKEND.bridge_hub
    )

    if bridge_ui_backend == constants.BRIDGE_UI_BACKEND.aggkit:
        # aggkit-backed mode: no bridge-hub api and no prebuilt UI container,
        # just the haproxy proxy with a CORS-safe route straight to the
        # aggkit bridge REST API. If aggkit_proxy_url is set (S5: multi-L2
        # enclaves point this at the standalone aggkit_proxy additional
        # service), use that single multi-network backend instead of this
        # run's own l2_context.aggkit_bridge_url (which only fronts one
        # chain's bridge REST API).
        aggkit_bridge_url = args.get("aggkit_proxy_url") or l2_context.aggkit_bridge_url
        run_proxy(
            plan,
            args,
            l1_context.rpc_url,
            l2_context.rpc_url,
            bridge_hub_api_url=None,
            agglayer_dev_ui_url=None,
            aggkit_bridge_url=aggkit_bridge_url,
        )
        return

    l1_bridge_address = contract_setup_addresses.get("l1_bridge_address")
    web_ui_url = run_server(plan, args, contract_setup_addresses)
    run_proxy(
        plan,
        args,
        l1_context.rpc_url,
        l2_context.rpc_url,
        bridge_hub_api_url=api_url,
        agglayer_dev_ui_url=web_ui_url,
    )


def run_server(plan, args, contract_setup_addresses):
    l1_bridge_address = contract_setup_addresses.get("l1_bridge_address")
    config_artifact = plan.render_templates(
        name="agglayer-dev-ui-config",
        config={
            "config.ts": struct(
                template=read_file(
                    src="../../../static_files/additional_services/bridge-ui/config.ts.tmpl",
                ),
                data={
                    # l1
                    "l1_chain_id": args.get("l1_chain_id"),
                    "l1_bridge_address": l1_bridge_address,
                    # l2
                    "l2_chain_id": args.get("l2_chain_id"),
                    "l2_network_id": args.get("l2_network_id"),
                },
            ),
        },
    )

    result = plan.add_service(
        name="agglayer-dev-ui",
        config=ServiceConfig(
            image=constants.DEFAULT_IMAGES.get("agglayer_dev_ui_image"),
            files={
                "/etc/agglayer-dev-ui": Directory(artifact_names=[config_artifact]),
            },
            env_vars={
                "BRIDGE_HUB_API_URL": "/bridgehubapi",
            },
            ports={
                SERVER_PORT_ID: PortSpec(
                    number=SERVER_PORT_NUMBER, application_protocol="http"
                )
            },
        ),
    )
    server_url = result.ports[SERVER_PORT_ID].url
    return server_url


def run_proxy(
    plan,
    args,
    l1_rpc_url,
    l2_rpc_url,
    bridge_hub_api_url,
    agglayer_dev_ui_url,
    aggkit_bridge_url=None,
):
    # Shaped as a list so that a future multi-L2 enclave can add one entry
    # per L2 (e.g. distinct path_suffix values like "/1", "/2" keyed off
    # network_id). In practice a single multi-network backend (the
    # standalone "aggkit_proxy" additional service, routed here via
    # aggkit_proxy_url -- see run() above) already fronts every L2's bridge
    # REST API, so this list collapses back down to exactly one entry (empty
    # suffix, routes land on the bare "/aggkitapi" prefix) even in a 2-L2
    # enclave -- haproxy never needs to fan out to per-chain bridge REST
    # services itself.
    aggkit_backends = []
    if aggkit_bridge_url:
        aggkit_backends = [
            {
                "path_suffix": "",
                "url": aggkit_bridge_url.removeprefix("http://"),
            },
        ]

    # Per-chain L2 JSON-RPC routes (S5: /l2rpc-001, /l2rpc-002, ...),
    # args-driven so a single-L2 deployment (the default, empty list) renders
    # none of these extra routes and behaves exactly as before.
    raw_l2_rpc_backends = args.get("bridge_ui_l2_rpc_urls", [])
    l2_rpc_backends = [
        {
            "path_suffix": entry["path_suffix"],
            "url": entry["url"].removeprefix("http://"),
        }
        for entry in raw_l2_rpc_backends
    ]

    # Back-compat: the bare /l2rpc route (consumed by the existing dev-ui
    # script) stays aliased to chain 1 -- see the "HAProxy Route Map" section
    # of docs/docs/advanced/aggkit-2l2-with-bridge-ui.md. If
    # bridge_ui_l2_rpc_urls declares a "-001" entry,
    # prefer it over l2_rpc_url (which is this run's OWN l2_context.rpc_url,
    # i.e. chain 2 when bridge_ui is deployed alongside run2's rollup); a
    # single-L2 deployment has no such entry and l2_rpc_url is used exactly
    # as before.
    default_l2_rpc_url = l2_rpc_url
    for entry in raw_l2_rpc_backends:
        if entry["path_suffix"] == "-001":
            default_l2_rpc_url = entry["url"]
            break

    config_artifact = plan.render_templates(
        name="agglayer-dev-ui-proxy-config{}".format(args.get("deployment_suffix")),
        config={
            "haproxy.cfg": struct(
                template=read_file(
                    src="../../../static_files/additional_services/bridge-ui/haproxy.cfg"
                ),
                data={
                    "l1_rpc_url": l1_rpc_url.removeprefix("http://"),
                    "l2_rpc_url": default_l2_rpc_url.removeprefix("http://"),
                    "bridge_hub_api_url": bridge_hub_api_url.removeprefix("http://")
                    if bridge_hub_api_url
                    else "",
                    "agglayer_dev_ui_url": agglayer_dev_ui_url.removeprefix("http://")
                    if agglayer_dev_ui_url
                    else "",
                    "aggkit_backends": aggkit_backends,
                    "l2_rpc_backends": l2_rpc_backends,
                },
            )
        },
    )

    plan.add_service(
        name="agglayer-dev-ui-proxy{}".format(args.get("deployment_suffix")),
        config=ServiceConfig(
            image=args.get("zkevm_bridge_proxy_image"),
            files={
                "/usr/local/etc/haproxy/": Directory(artifact_names=[config_artifact]),
            },
            ports={
                SERVER_PORT_ID: PortSpec(
                    SERVER_PORT_NUMBER, application_protocol="http"
                )
            },
        ),
    )
