constants = import_module("../../package_io/constants.star")


# Port identifiers and numbers.
SERVER_PORT_ID = "http"
SERVER_PORT_NUMBER = 80


def run(plan, args, contract_setup_addresses, l1_context, l2_context, api_url):
    bridge_ui_backend = args.get(
        "bridge_ui_backend", constants.BRIDGE_UI_BACKEND.bridge_hub
    )

    if bridge_ui_backend == constants.BRIDGE_UI_BACKEND.aggkit:
        # aggkit-backed mode: by default no bridge-hub api and no prebuilt UI
        # container, just the haproxy proxy with a CORS-safe route straight
        # to the aggkit bridge REST API. If aggkit_proxy_url is set (S5:
        # multi-L2 enclaves point this at the standalone aggkit_proxy
        # additional service), use that single multi-network backend instead
        # of this run's own l2_context.aggkit_bridge_url (which only fronts
        # one chain's bridge REST API).
        aggkit_bridge_url = args.get("aggkit_proxy_url") or l2_context.aggkit_bridge_url

        # S5 (dev-ui-ci-snapshot plan): optionally also deploy the published
        # agglayer-dev-ui container, configured at runtime with a rendered
        # devnet config.json, and route it through this same haproxy proxy
        # (as the default backend -- identical wiring to the bridge_hub
        # backend's own agglayer_dev_ui_url below). Opt-in and False by
        # default so existing aggkit-mode deployments are unchanged.
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
    # S5 (dev-ui-ci-snapshot plan): aggkit-mode dev-ui deployment. Renders a
    # devnet config.json for the published agglayer-dev-ui GHCR image
    # (contract: dev-ui docs/docker.md -- mounted at
    # /etc/agglayer-dev-ui/config.json) and returns this service's
    # enclave-internal URL so run_proxy() can route it as haproxy's default
    # backend, exactly like the bridge_hub backend's own agglayer_dev_ui_url
    # wiring above.
    #
    # aggkitBridgeApis in the rendered config uses the relative path
    # "/aggkitapi" (allowed only for that field -- see dev-ui docs/config.md
    # "Relative aggkitBridgeApis URLs"): the dev-ui container is served
    # through this same haproxy origin (backend_default), so the browser
    # resolves it against the page's own origin with no CORS involved. Chain
    # rpcUrl values, by contrast, must be absolute (wallets need a concrete
    # URL) -- this function uses the enclave-internal DNS URLs
    # (l1_context.rpc_url / l2_context.rpc_url / bridge_ui_l2_rpc_urls[].url)
    # for those, which is everything Starlark has available at render time
    # (the haproxy service's host-published port is assigned by the
    # container runtime after this point, and is only discoverable
    # afterwards via `kurtosis port print` -- see S6/S7). Consequently these
    # rpcUrl values are schema-valid but not host-browser-reachable from a
    # plain `kurtosis run`; making them so requires pinning haproxy to a
    # static host port (src/package_io/ports.star's static_ports mechanism),
    # which is out of scope for this opt-in flag and left to the snapshot
    # flavor's fixed ${DEVNET_PROXY_PORT:-8555} (S7/S8).
    l1_bridge_address = contract_setup_addresses.get("l1_bridge_address")

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
    # The filter above is a silent drop: an entry without chain_id/network_id
    # simply vanishes from the dev-ui chain catalog. In a multi-L2 enclave where
    # only some entries carry the metadata that means a missing chain in the UI
    # with no error anywhere, so say so out loud.
    if len(l2_chains) != len(raw_l2_rpc_backends):
        plan.print(
            "WARNING: {} of {} bridge_ui_l2_rpc_urls entries lack chain_id/network_id and are omitted from the dev-ui chain catalog".format(
                len(raw_l2_rpc_backends) - len(l2_chains), len(raw_l2_rpc_backends)
            )
        )
    if not l2_chains:
        # Single-L2 fallback: no bridge_ui_l2_rpc_urls chain metadata
        # supplied, so catalog only this run's own L2 -- mirrors the
        # existing bridge_ui_l2_rpc_urls-empty fallback used for the
        # haproxy /l2rpc back-compat alias in run_proxy() below.
        l2_chains = [
            {
                "chain_key": "DEVNET_L2",
                "chain_id": args.get("l2_chain_id"),
                "network_id": args.get("l2_network_id"),
                "rpc_url": l2_context.rpc_url,
                "path_suffix": "",
            }
        ]

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
