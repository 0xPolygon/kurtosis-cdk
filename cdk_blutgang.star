def run(plan, args):
    blutgang_name = "blutgang" + args["deployment_suffix"]
    blutgang_config_template = read_file(
        src="./templates/blutgang/blutgang-config.toml"
    )

    zkevm_sequencer_service = plan.get_service(
        name=args["sequencer_name"] + args["deployment_suffix"]
    )
    zkevm_sequencer_http_url = "http://{}:{}".format(
        zkevm_sequencer_service.ip_address, zkevm_sequencer_service.ports["rpc"].number
    )

    zkevm_rpc_service = plan.get_service(
        name="zkevm-node-rpc" + args["deployment_suffix"]
    )
    zkevm_rpc_http_url = "http://{}:{}".format(
        zkevm_rpc_service.ip_address, zkevm_rpc_service.ports["http-rpc"].number
    )
    zkevm_rpc_ws_url = "ws://{}:{}".format(
        zkevm_rpc_service.ip_address, zkevm_rpc_service.ports["ws-rpc"].number
    )

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

    blutgang_config_artifact = plan.render_templates(
        name="blutgang-config-artifact",
        config={
            "blutgang-config.toml": struct(
                template=blutgang_config_template,
                data={
                    "l2_sequencer_url": zkevm_sequencer_http_url,
                    "l2_rpc_url": zkevm_rpc_http_url,
                    "l2_ws_url": zkevm_rpc_ws_url,
                    "l2_rpc_pless_url": zkevm_rpc_pless_http_url,
                    "l2_ws_pless_url": zkevm_rpc_pless_ws_url,
                }
                | args,
            )
        },
    )

    blutgang_service_config = ServiceConfig(
        image=args["blutgang_image"],
        ports={
            "http": PortSpec(args["blutgang_rpc_port"], application_protocol="http"),
            "admin": PortSpec(args["blutgang_admin_port"], application_protocol="http"),
        },
        files={
            "/etc/blutgang": Directory(
                artifact_names=[
                    blutgang_config_artifact,
                ]
            ),
        },
        cmd=["/app/blutgang", "-c", "/etc/blutgang/blutgang-config.toml"],
    )

    plan.add_service(
        name=blutgang_name,
        config=blutgang_service_config,
        description="Starting blutgang service",
    )
