constants = import_module("../../src/package_io/constants.star")


def run(plan, args):
    l2_rpc_service = plan.get_service(args["l2_rpc_name"] + args["deployment_suffix"])
    l2_rpc_url = "http://{}:{}".format(
        l2_rpc_service.ip_address, l2_rpc_service.ports["rpc"].number
    )
    check_script_artifact = plan.render_templates(
        name="status-checker-script",
        config={
            "check.sh": struct(
                template=read_file(
                    src="../../static_files/additional_services/status-checker-config/check.sh",
                ),
                data={
                    "rpc_url": l2_rpc_url,
                },
            )
        },
    )

    plan.add_service(
        name="status-checker" + args["deployment_suffix"],
        config=ServiceConfig(
            image=constants.TOOLBOX_IMAGE,
            files={"/opt/scripts": Directory(artifact_names=[check_script_artifact])},
            entrypoint=["bash", "-c"],
            cmd=["chmod +x /opt/scripts/check.sh && /opt/scripts/check.sh"],
        ),
    )
