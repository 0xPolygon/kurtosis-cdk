constants = import_module("../../package_io/constants.star")


# Port identifiers and numbers.
SERVER_PORT_ID = "http"
SERVER_PORT_NUMBER = 80


def run(plan, args, contract_setup_addresses, l1_context, l2_context, api_url):
    bridge_ui_backend = args.get(
        "bridge_ui_backend", constants.BRIDGE_UI_BACKEND.bridge_hub
    )

    if bridge_ui_backend == constants.BRIDGE_UI_BACKEND.aggkit:
        # aggkit-backed mode: no bridge-hub stack, haproxy forwards /aggkitapi to
        # the aggkit bridge REST API. aggkit_proxy_url, when set, replaces this
        # run's own bridge URL with the multi-network aggkit-proxy service.
        aggkit_bridge_url = args.get("aggkit_proxy_url") or l2_context.aggkit_bridge_url

        # Optionally also serve the published agglayer-dev-ui container through
        # the same haproxy, as its default backend.
        agglayer_dev_ui_url = None
        if args.get("aggkit_deploy_dev_ui", False):
            agglayer_dev_ui_url = run_dev_ui(
                plan, args, contract_setup_addresses, l1_context, l2_context
            )

        run_proxy(
            plan,
            args,
            l1_context.rpc_url,
            l2_context.rpc_url,
            bridge_hub_api_url=None,
            agglayer_dev_ui_url=agglayer_dev_ui_url,
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


def run_dev_ui(plan, args, contract_setup_addresses, l1_context, l2_context):
    # Renders the config.json read by the published agglayer-dev-ui image
    # (mounted at /etc/agglayer-dev-ui/config.json) and returns the service URL
    # that haproxy routes to as its default backend.
    #
    # aggkitProxy is the relative path "/aggkitapi", resolved by the browser
    # against the haproxy origin. Chain rpcUrl values must be absolute, and only
    # the enclave-internal URLs are known at render time, so they are not
    # reachable from a host browser; the devnet snapshot rewrites them to its
    # fixed proxy port.
    l1_bridge_address = contract_setup_addresses.get("l1_bridge_address")

    (l2_chains, omitted) = get_dev_ui_l2_chains(args, l2_context.rpc_url)
    if omitted > 0:
        plan.print(
            "WARNING: {} bridge_ui_l2_rpc_urls entries lack chain_id/network_id and are omitted from the dev-ui chain catalog".format(
                omitted
            )
        )

    config_artifact = plan.render_templates(
        name="agglayer-dev-ui-aggkit-config{}".format(args.get("deployment_suffix")),
        config={
            "config.json": struct(
                template=read_file(
                    src="../../../static_files/additional_services/bridge-ui/aggkit-dev-ui-config.json.tmpl",
                ),
                data={
                    "l1_chain_id": args.get("l1_chain_id"),
                    "l1_rpc_url": l1_context.rpc_url,
                    "l1_bridge_address": l1_bridge_address,
                    "l2_chains": l2_chains,
                },
            ),
        },
    )

    result = plan.add_service(
        name="agglayer-dev-ui" + args.get("deployment_suffix"),
        config=ServiceConfig(
            image=constants.DEFAULT_IMAGES.get("agglayer_dev_ui_aggkit_image"),
            files={
                "/etc/agglayer-dev-ui": Directory(artifact_names=[config_artifact]),
            },
            ports={
                SERVER_PORT_ID: PortSpec(
                    number=SERVER_PORT_NUMBER, application_protocol="http"
                )
            },
        ),
    )
    return result.ports[SERVER_PORT_ID].url


def get_dev_ui_l2_chains(args, l2_rpc_url):
    """The L2 chains listed in the dev-ui config, and how many
    bridge_ui_l2_rpc_urls entries were left out because they carry no chain_id and
    network_id. This run's own L2 is listed if no entry carries them."""
    raw_l2_rpc_backends = args.get("bridge_ui_l2_rpc_urls", [])
    l2_chains = [
        {
            "chain_key": "DEVNET_L2" + entry["path_suffix"].replace("-", "_"),
            "chain_id": entry["chain_id"],
            "network_id": entry["network_id"],
            "rpc_url": entry["url"],
            "path_suffix": entry["path_suffix"],
        }
        for entry in raw_l2_rpc_backends
        if "chain_id" in entry and "network_id" in entry
    ]
    omitted = len(raw_l2_rpc_backends) - len(l2_chains)
    if not l2_chains:
        l2_chains = [
            {
                "chain_key": "DEVNET_L2",
                "chain_id": args.get("l2_chain_id"),
                "network_id": args.get("l2_network_id"),
                "rpc_url": l2_rpc_url,
                "path_suffix": "",
            }
        ]
    return (l2_chains, omitted)


def get_proxy_template_data(
    args,
    l1_rpc_url,
    l2_rpc_url,
    bridge_hub_api_url,
    agglayer_dev_ui_url,
    aggkit_bridge_url=None,
):
    """The data rendered into haproxy.cfg."""
    # A single entry: the aggkit-proxy service (aggkit_proxy_url) already fronts
    # every L2's bridge REST API, so haproxy never fans out per chain.
    aggkit_backends = []
    if aggkit_bridge_url:
        aggkit_backends = [
            {
                "path_suffix": "",
                "url": aggkit_bridge_url.removeprefix("http://"),
            },
        ]

    # One /l2rpc<path_suffix> route per bridge_ui_l2_rpc_urls entry.
    raw_l2_rpc_backends = args.get("bridge_ui_l2_rpc_urls", [])
    l2_rpc_backends = [
        {
            "path_suffix": entry["path_suffix"],
            "url": entry["url"].removeprefix("http://"),
        }
        for entry in raw_l2_rpc_backends
    ]

    # The bare /l2rpc route is an alias of chain 1: the "-001" entry wins over
    # l2_rpc_url, which is this run's own L2 (chain 2 in the second run).
    default_l2_rpc_url = l2_rpc_url
    for entry in raw_l2_rpc_backends:
        if entry["path_suffix"] == "-001":
            default_l2_rpc_url = entry["url"]
            break

    return {
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
    }


def run_proxy(
    plan,
    args,
    l1_rpc_url,
    l2_rpc_url,
    bridge_hub_api_url,
    agglayer_dev_ui_url,
    aggkit_bridge_url=None,
):
    config_artifact = plan.render_templates(
        name="agglayer-dev-ui-proxy-config{}".format(args.get("deployment_suffix")),
        config={
            "haproxy.cfg": struct(
                template=read_file(
                    src="../../../static_files/additional_services/bridge-ui/haproxy.cfg"
                ),
                data=get_proxy_template_data(
                    args,
                    l1_rpc_url,
                    l2_rpc_url,
                    bridge_hub_api_url,
                    agglayer_dev_ui_url,
                    aggkit_bridge_url,
                ),
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
