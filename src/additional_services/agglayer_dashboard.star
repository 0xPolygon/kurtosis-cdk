service_package = import_module("../../lib/service.star")

AGGLAYER_DASHBOARD_IMAGE = "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/agglayer-dashboard:v3.4.0"
DASHBOARD_PORT_NUMBER = 60444
CONFIG_PATH = "/kurtosis_config"
DASHBOARD_CONFIG_TEMPLATE = (
    "../../static_files/additional_services/agglayer-dashboard-config/config.json"
)
NGINX_CONFIG_FILE = (
    "../../static_files/additional_services/agglayer-dashboard-config/nginx.conf"
)


def run(plan, args, contract_setup_addresses):
    plan.add_service(
        name="agglayer-dashboard",
        config=ServiceConfig(
            image=AGGLAYER_DASHBOARD_IMAGE,
            ports={
                "dashboard": PortSpec(
                    DASHBOARD_PORT_NUMBER, application_protocol="http"
                )
            },
            public_ports={
                "dashboard": PortSpec(
                    DASHBOARD_PORT_NUMBER, application_protocol="http"
                )
            },
            files={
                CONFIG_PATH: get_dashboard_config_dir(
                    plan, args, contract_setup_addresses
                )
            },
        ),
    )


def get_dashboard_config_dir(plan, args, contract_setup_addresses):
    agglayer_dashboard_config_template = read_file(src=DASHBOARD_CONFIG_TEMPLATE)

    template_data = {
        "l2_chain_name": args["chain_name"],
        "l2_chain_id": args["zkevm_rollup_chain_id"],
        "l2_rollup_id": args["zkevm_rollup_id"],
    } | contract_setup_addresses

    return Directory(
        artifact_names=[
            plan.render_templates(
                name="agglayer-dashboard-config",
                config={
                    "config.json": struct(
                        template=agglayer_dashboard_config_template,
                        data=template_data,
                    )
                },
            ),
            plan.upload_files(
                name="agglayer-dashboard-nginx",
                src=NGINX_CONFIG_FILE,
                description="Uploading Aggl Dashboard nginx config",
            ),
        ]
    )
