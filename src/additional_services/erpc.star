ports_package = import_module("../package_io/ports.star")
contracts_util = import_module("../contracts/util.star")

ERPC_IMAGE = "ghcr.io/erpc/erpc:0.0.24"

SERVICE_NAME = "erpc"
RPC_PORT = 8080
PROMETHEUS_PORT = 6060


def run(plan, args):
    config_artifact = get_erpc_config(plan, args)
    (ports, public_ports) = get_erpc_ports(args)
    plan.add_service(
        name=SERVICE_NAME + args["deployment_suffix"],
        config=ServiceConfig(
            image=ERPC_IMAGE,
            ports=ports,
            public_ports=public_ports,
            files={"/etc/erpc": config_artifact},
            cmd=["/root/erpc-server", "/etc/erpc/erpc.yaml"],
        ),
    )


def get_erpc_config(plan, args):
    config_template = read_file(
        src="../../static_files/additional_services/erpc/erpc.yaml"
    )
    l2_rpc_url = contracts_util.get_l2_rpc_url(plan, args)
    return plan.render_templates(
        name=SERVICE_NAME + "-config",
        config={
            "erpc.yaml": struct(
                template=config_template,
                data={
                    "erpc_rpc_port": RPC_PORT,
                    "erpc_metrics_port": PROMETHEUS_PORT,
                    "l2_chain_id": args["l2_chain_id"],
                    "l2_rpc_name": args["l2_rpc_name"],
                    "l2_rpc_url": l2_rpc_url.http,
                },
            )
        },
    )


def get_erpc_ports(args):
    ports = {
        "rpc": PortSpec(RPC_PORT, application_protocol="http"),
        "prometheus": PortSpec(PROMETHEUS_PORT, application_protocol="http"),
    }
    public_ports = ports_package.get_public_ports(ports, "erpc_start_port", args)
    return (ports, public_ports)
