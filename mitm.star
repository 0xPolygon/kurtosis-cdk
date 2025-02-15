SRC_MITM_SCRIPT_PATH = "./scripts/mitm"
DST_MITM_SCRIPT_PATH = "/scripts"
DEFAULT_SCRIPT = "empty.py"


def run(plan, args):
    mitm_script = plan.upload_files(
        name="mitm-script",
        src=SRC_MITM_SCRIPT_PATH + "/" + DEFAULT_SCRIPT,
        description="Uploading MITM script",
    )
    service_files = {
        DST_MITM_SCRIPT_PATH: mitm_script,
    }

    plan.add_service(
        name="mitm" + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["mitm_image"],
            ports={
                "rpc": PortSpec(args["mitm_port"], application_protocol="http"),
            },
            files=service_files,
            cmd=[
                "sh",
                "-c",
                "mitmdump --mode reverse:"
                + args["l1_rpc_url"]
                + " -p "
                + str(args["mitm_port"])
                + " -s "
                + DST_MITM_SCRIPT_PATH
                + "/"
                + DEFAULT_SCRIPT,
            ],
        ),
    )
