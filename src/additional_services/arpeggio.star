ports_package = import_module("../package_io/ports.star")
contracts_util = import_module("../contracts/util.star")

ARPEGGIO_IMAGE = "christophercampbell/arpeggio:v0.0.1"
RPC_PROXY_PORT = 8545
WS_PROXY_PORT = 8546
# METRICS_PORT = 9105


def run(plan, args):
    arpeggio_config_artifact = get_arpeggio_config(plan, args)
    (ports, public_ports) = get_arpeggio_ports(args)
    plan.add_service(
        name="arpeggio" + args["deployment_suffix"],
        config=ServiceConfig(
            image=ARPEGGIO_IMAGE,
            ports=ports,
            public_ports=public_ports,
            files={"/etc/arpeggio": arpeggio_config_artifact},
        ),
    )


def get_arpeggio_config(plan, args):
    arpeggio_config_template = read_file(
        src="../../static_files/additional_services/arpeggio-config/config.yml"
    )
    l2_rpc_url = contracts_util.get_l2_rpc_url(plan, args)
    return plan.render_templates(
        name="arpeggio-config",
        config={
            "config.yml": struct(
                template=arpeggio_config_template,
                data={
                    "l2_rpc_name": args["l2_rpc_name"],
                    "l2_rpc_url": l2_rpc_url.http,
                    "l2_ws_url": l2_rpc_url.ws,
                },
            )
        },
    )


def get_arpeggio_ports(args):
    ports = {
        "rpc": PortSpec(RPC_PROXY_PORT, application_protocol="http"),
        "ws": PortSpec(WS_PROXY_PORT, application_protocol="ws"),
        # "prometheus": PortSpec(METRICS_PORT, application_protocol="http"),
    }
    public_ports = ports_package.get_public_ports(ports, "arpeggio_start_port", args)
    return (ports, public_ports)
