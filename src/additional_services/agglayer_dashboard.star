AGGLAYER_DASHBOARD_IMAGE = "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/agglayer-dashboard:v4fixed"
CONFIG_PATH = "/etc/dasboard"
CONFIG_FILE = "config.json"

DASHBOARD_PORT_ID = "dashboard"
DASHBOARD_PORT_NUMBER = 8000


def run(plan, args, contract_setup_addresses, l1_context, l2_context, agglayer_context):
    agglayer_dashboard_config_artifact = (
        plan.render_templates(
            name="agglayer-dashboard-config" + l2_context.name,
            config={
                CONFIG_FILE: struct(
                    template=read_file(
                        src="../../static_files/additional_services/agglayer-dashboard/config.json"
                    ),
                    data={
                        # l1
                        "l1_rpc_url": l1_context.rpc_url,
                        # l2
                        "l2_network_id": src(l2_context.network_id),
                        "l2_rpc_url": l2_context.rpc_http_url,
                        "l2_sovereignadmin_private_key": args.get(
                            "l2_sovereignadmin_private_key"
                        ),
                        # agglayer
                        "agglayer_rpc_url": agglayer_context.rpc_url,
                    }
                    | contract_setup_addresses,
                )
            },
        ),
    )

    plan.add_service(
        name="agglayer-dashboard" + l2_context.name,
        config=ServiceConfig(
            image=AGGLAYER_DASHBOARD_IMAGE,
            ports={
                DASHBOARD_PORT_ID: PortSpec(
                    DASHBOARD_PORT_NUMBER, application_protocol="http"
                )
            },
            files={
                CONFIG_PATH: Directory(
                    artifact_names=[agglayer_dashboard_config_artifact]
                ),
            },
            env_vars={"CONFIG_FILE": CONFIG_PATH + "/" + CONFIG_FILE},
        ),
    )
