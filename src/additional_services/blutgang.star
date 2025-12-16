ports_package = import_module("../package_io/ports.star")
contracts_util = import_module("./src/contracts/util.star")

BLUTGANG_IMAGE = "makemake1337/blutgang:0.3.6"

RPC_PORT_NUMBER = 8555
ADMIN_PORT_NUMBER = 8556


def run(plan, args):
    blutgang_config_artifact = get_blutgang_config(plan, args)
    (ports, public_ports) = get_blutgang_ports(args)
    plan.add_service(
        name="blutgang" + args["deployment_suffix"],
        config=ServiceConfig(
            image=BLUTGANG_IMAGE,
            ports=ports,
            public_ports=public_ports,
            files={
                "/etc/blutgang": Directory(
                    artifact_names=[
                        blutgang_config_artifact,
                    ]
                ),
            },
            cmd=["/app/blutgang", "-c", "/etc/blutgang/config.toml"],
        ),
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

    l2_rpc_url = contracts_util.get_l2_rpc_url(plan, args)

    blutgang_data = {
        "blutgang_rpc_port": RPC_PORT_NUMBER,
        "blutgang_admin_port": ADMIN_PORT_NUMBER,
        "l2_sequencer_url": zkevm_sequencer_http_url,
        "l2_rpc_url": l2_rpc_url.http,
        "l2_ws_url": l2_rpc_url.ws,
    }

    return plan.render_templates(
        name="blutgang-config",
        config={
            "config.toml": struct(
                template=blutgang_config_template,
                data=blutgang_data | args,
            )
        },
    )


def get_blutgang_ports(args):
    ports = {
        "http": PortSpec(RPC_PORT_NUMBER, application_protocol="http"),
        "admin": PortSpec(ADMIN_PORT_NUMBER, application_protocol="http"),
    }
    public_ports = ports_package.get_public_ports(ports, "blutgang_start_port", args)
    return (ports, public_ports)
