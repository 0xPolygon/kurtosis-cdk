AGGLAYER_DASHBOARD_IMAGE = "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/agglayer-dashboard:v4fixed"
CONFIG_PATH = "/etc/dasboard"
CONFIG_FILE = "config.json"
DASHBOARD_PORT = 8000
DASHBOARD_CONFIG_TEMPLATE = (
    "../../static_files/additional_services/agglayer-dashboard/config.json"
)


def run(plan, args, contract_setup_addresses):
    plan.add_service(
        name="agglayer-dashboard",
        config=ServiceConfig(
            image=AGGLAYER_DASHBOARD_IMAGE,
            ports={"dashboard": PortSpec(DASHBOARD_PORT, application_protocol="http")},
            files={
                CONFIG_PATH: get_dashboard_config(plan, args, contract_setup_addresses)
            },
            env_vars={"CONFIG_FILE": CONFIG_PATH + "/" + CONFIG_FILE},
        ),
    )


def get_dashboard_config(plan, args, contract_setup_addresses):
    agglayer_dashboard_config_template = read_file(src=DASHBOARD_CONFIG_TEMPLATE)

    template_data = {
        "l2_rollup_id": args["zkevm_rollup_id"],
        "l1_rpc_url": args["l1_rpc_url"],
        "l2_rpc_url": "http://{}{}:{}".format(
            args["l2_rpc_name"], args["deployment_suffix"], args["zkevm_rpc_http_port"]
        ),
        "agglayer_rpc_url": args.get("agglayer_readrpc_url"),
        "l2_sovereignadmin_private_key": args.get("l2_sovereignadmin_private_key"),
    } | contract_setup_addresses

    return Directory(
        artifact_names=[
            plan.render_templates(
                name="agglayer-dashboard-config",
                config={
                    CONFIG_FILE: struct(
                        template=agglayer_dashboard_config_template,
                        data=template_data,
                    )
                },
            ),
        ]
    )
