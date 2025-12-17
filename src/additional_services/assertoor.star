HTTP_PORT_NUMBER = 8080

ASSERTOOR_IMAGE = "ethpandaops/assertoor:v0.0.11"

ASSERTOOR_CONFIG_MOUNT_DIRPATH_ON_SERVICE = "/config"

VALIDATOR_RANGES_MOUNT_DIRPATH_ON_SERVICE = "/validator-ranges"
VALIDATOR_RANGES_ARTIFACT_NAME = "validator-ranges"


def run(plan, args):
    assertoor_config_artifact = get_assertoor_config(plan, args)
    plan.add_service(
        name="assertoor" + args["deployment_suffix"],
        config=ServiceConfig(
            image=ASSERTOOR_IMAGE,
            ports={
                "http": PortSpec(
                    number=HTTP_PORT_NUMBER,
                    transport_protocol="TCP",
                    application_protocol="http",
                )
            },
            files={
                ASSERTOOR_CONFIG_MOUNT_DIRPATH_ON_SERVICE: assertoor_config_artifact,
                VALIDATOR_RANGES_MOUNT_DIRPATH_ON_SERVICE: VALIDATOR_RANGES_ARTIFACT_NAME,
            },
            cmd=["--config", "/config/config.yaml"],
        ),
    )


def get_assertoor_config(plan, args):
    assertoor_config_template = read_file(
        src="../../static_files/additional_services/assertoor/config.yaml"
    )

    assertoor_data = {
        "assertoor_endpoint_name": "assertoor_web_ui",
        "execution_client_url": args["l1_rpc_url"],
        "consensus_client_url": args["l1_conensus_rpc_url"],
        "http_port_number": HTTP_PORT_NUMBER,
    }

    return plan.render_templates(
        name="assertoor-config",
        config={
            "config.yaml": struct(
                template=assertoor_config_template,
                data=assertoor_data | args,
            )
        },
    )
