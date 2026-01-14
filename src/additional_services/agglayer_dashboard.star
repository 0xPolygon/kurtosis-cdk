AGGLAYER_DASHBOARD_IMAGE = "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/agglayer-dashboard:v4fixed"
CONFIG_PATH = "/etc/dasboard"
CONFIG_FILE = "config.json"
DASHBOARD_PORT = 8000


def run(plan, args, contract_setup_addresses, l1_context, l2_context, agglayer_context):
    plan.add_service(
        name="agglayer-dashboard",
        config=ServiceConfig(
            image=AGGLAYER_DASHBOARD_IMAGE,
            ports={"dashboard": PortSpec(DASHBOARD_PORT, application_protocol="http")},
            files={
                CONFIG_PATH: get_dashboard_config(
                    plan,
                    args,
                    contract_setup_addresses,
                    l1_context,
                    l2_context,
                    agglayer_context,
                )
            },
            env_vars={"CONFIG_FILE": CONFIG_PATH + "/" + CONFIG_FILE},
        ),
    )


def get_dashboard_config(
    plan, args, contract_setup_addresses, l1_context, l2_context, agglayer_context
):
    return Directory(
        artifact_names=[
            plan.render_templates(
                name="agglayer-dashboard-config",
                config={
                    CONFIG_FILE: struct(
                        template=read_file(
                            src="../../static_files/additional_services/agglayer-dashboard/config.json"
                        ),
                        data={
                            "l1_rpc_url": l1_context.rpc_url,
                            "l2_network_id": l2_context.network_id,
                            "l2_rpc_url": l2_context.rpc_http_url,
                            "agglayer_rpc_url": agglayer_context.rpc_url,
                            "l2_sovereignadmin_private_key": args.get(
                                "l2_sovereignadmin_private_key"
                            ),
                        }
                        | contract_setup_addresses,
                    )
                },
            ),
        ]
    )
