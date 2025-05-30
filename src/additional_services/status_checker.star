ports_package = import_module("../package_io/ports.star")


def run(plan, args):
    l2_rpc_service = plan.get_service(args["l2_rpc_name"] + args["deployment_suffix"])
    l2_rpc_url = "http://{}:{}".format(
        l2_rpc_service.ip_address, l2_rpc_service.ports["rpc"].number
    )

    status_checker_config_artifact = plan.render_templates(
        name="status-checker-config",
        config={
            "config.yml": struct(
                template=read_file(
                    src="../../static_files/additional_services/status-checker-config/config.yml",
                ),
                data={},
            ),
        },
    )

    status_checker_checks_artifact = plan.upload_files(
        src="../../static_files/additional_services/status-checker-config/checks",
        name="status-checker-checks",
    )

    ports = {
        "prometheus": PortSpec(9090, application_protocol="http"),
    }
    public_ports = ports_package.get_public_ports(
        ports, "status_checker_start_port", args
    )

    plan.add_service(
        name="status-checker" + args["deployment_suffix"],
        config=ServiceConfig(
            image=args.get("status_checker_image"),
            files={
                "/etc/status-checker": Directory(
                    artifact_names=[status_checker_config_artifact]
                ),
                "/opt/status-checker/checks": Directory(
                    artifact_names=[status_checker_checks_artifact]
                ),
            },
            ports=ports,
            public_ports=public_ports,
            env_vars={"L2_RPC_URL": l2_rpc_url},
        ),
    )
