SRC_MITM_SCRIPT_PATH = "../scripts/mitm"
SRC_MITM_SCRIPTS = ["empty.py", "failures.py", "tx_capture.py"]
DEFAULT_SCRIPT = "empty.py"
DST_MITM_SCRIPT_PATH = "/scripts"


def run(plan, args):
    artifacts = []
    for script in SRC_MITM_SCRIPTS:
        mitm_script = plan.upload_files(
            name="mitm-script-" + script,
            src="{}/{}".format(SRC_MITM_SCRIPT_PATH, script),
            description="Uploading MITM script " + script,
        )
        artifacts.append(mitm_script)

    # Select script based on configuration
    selected_script = DEFAULT_SCRIPT
    if args.get("mitm_capture_transactions", False):
        selected_script = "tx_capture.py"

    plan.add_service(
        name="mitm" + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["mitm_image"],
            ports={
                "rpc": PortSpec(args["mitm_port"], application_protocol="http"),
            },
            files={
                DST_MITM_SCRIPT_PATH: Directory(artifact_names=artifacts),
            },
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
                + selected_script,
            ],
        ),
    )

    # Store transactions to artifact if capture is enabled
    if args.get("mitm_capture_transactions", False):
        plan.store_service_files(
            service_name="mitm" + args["deployment_suffix"],
            src="/data",
            name="transactions"
        )
