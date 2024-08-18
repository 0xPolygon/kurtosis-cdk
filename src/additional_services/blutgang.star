service_package = import_module("../../lib/service.star")

BLUTGANG_IMAGE = "makemake1337/blutgang:0.3.6"

RPC_PORT_NUMBER = 8555
ADMIN_PORT_NUMBER = 8556


def run(plan, args):
    blutgang_config_artifact = get_blutgang_config(plan, args)
    plan.add_service(
        name="blutgang" + args["deployment_suffix"],
        config=ServiceConfig(
            image=BLUTGANG_IMAGE,
            ports={
                "http": PortSpec(RPC_PORT_NUMBER),
                "admin": PortSpec(ADMIN_PORT_NUMBER),
            },
            files={
                "/etc/blutgang": Directory(
                    artifact_names=[
                        blutgang_config_artifact,
                    ]
                ),
            },
            cmd=["/app/blutgang", "-c", "/etc/blutgang/config.toml"],
        ),
        description="Starting blutgang service",
    )


def get_blutgang_config(plan, args):
    blutgang_config_template = read_file(
        src="../../static_files/additional_services/blutgang-config/config.toml"
    )

    zkevm_sequencer_service = plan.get_service(
        name=args["sequencer_name"] + args["deployment_suffix"]
    )
    zkevm_sequencer_http_url = "http://{}:{}".format(
        zkevm_sequencer_service.ip_address, zkevm_sequencer_service.ports["rpc"].number
    )

    l2_rpc_urls = service_package.get_l2_rpc_urls(plan, args)

    zkevm_rpc_pless_service = plan.get_service(
        name="zkevm-node-rpc-pless" + args["deployment_suffix"]
    )
    zkevm_rpc_pless_http_url = "http://{}:{}".format(
        zkevm_rpc_pless_service.ip_address,
        zkevm_rpc_pless_service.ports["http-rpc"].number,
    )
    zkevm_rpc_pless_ws_url = "ws://{}:{}".format(
        zkevm_rpc_pless_service.ip_address,
        zkevm_rpc_pless_service.ports["ws-rpc"].number,
    )

    return plan.render_templates(
        name="blutgang-config",
        config={
            "config.toml": struct(
                template=blutgang_config_template,
                data={
                    "blutgang_rpc_port": RPC_PORT_NUMBER,
                    "blutgang_admin_port": ADMIN_PORT_NUMBER,
                    "l2_sequencer_url": zkevm_sequencer_http_url,
                    "l2_rpc_url": l2_rpc_urls.http,
                    "l2_ws_url": l2_rpc_urls.ws,
                    "zkevm_rpc_pless_http_url": zkevm_rpc_pless_http_url,
                    "zkevm_rpc_pless_ws_url": zkevm_rpc_pless_ws_url,
                }
                | args,
            )
        },
    )
