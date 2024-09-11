service_package = import_module("../../lib/service.star")

DOCKER_IMAGE = "christophercampbell/erpc:0.0.1-SNAPSHOT"

SERVICE_NAME = "erpc"
RPC_PORT = 8080
METRICS_PORT = 6060

CHAIN_ID = 10101


def run(plan, args):
    config_artifact = get_erpc_config(plan, args)
    plan.add_service(
        name=SERVICE_NAME + args["deployment_suffix"],
        config=ServiceConfig(
            image=DOCKER_IMAGE,
            ports={
                "rpc": PortSpec(RPC_PORT, application_protocol="rpc"),
                "metrics": PortSpec(METRICS_PORT, application_protocol="http"),
            },
            files={"/etc/erpc": config_artifact},
            cmd=["/root/erpc-server", "/etc/erpc/erpc.yaml"],
        ),
    )


def get_erpc_config(plan, args):
    config_template = read_file(
        src="../../static_files/additional_services/erpc-config/erpc.yaml"
    )
    l2_rpc_urls = service_package.get_l2_rpc_urls(plan, args)
    return plan.render_templates(
        name=SERVICE_NAME + "-config",
        config={
            "erpc.yaml": struct(
                template=config_template,
                data={
                    "erpc_rpc_port": RPC_PORT,
                    "erpc_metrics_port": METRICS_PORT,
                    "l2_chain_id": CHAIN_ID,
                    "l2_rpc_name": args["l2_rpc_name"],
                    "l2_rpc_url": l2_rpc_urls.http,
                },
            )
        },
    )
