ports_package = import_module("../package_io/ports.star")
service_package = import_module("../../lib/service.star")


def run(plan, args):
    l2_rpc_url = service_package.get_l2_rpc_url(plan, args).http
    sequencer_rpc_url = service_package.get_sequencer_rpc_url(plan, args)

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
                # Mount this directory to have have access to contract addresses.
                "/opt/output": Directory(persistent_key="output-artifact"),
                "/opt/aggkit": Directory(persistent_key="aggkit-tmp"),
            },
            ports=ports,
            public_ports=public_ports,
            env_vars={
                "L1_RPC_URL": args.get("l1_rpc_url"),
                "L2_RPC_URL": l2_rpc_url,
                "SEQUENCER_RPC_URL": sequencer_rpc_url,
                "CONSENSUS_CONTRACT_TYPE": args.get("consensus_contract_type"),
                "AGGLAYER_RPC_URL": args.get("agglayer_readrpc_url"),
            },
        ),
    )
