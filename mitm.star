def run(plan, args):
    plan.add_service(
        name="mitm" + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["mitm_image"],
            ports={
                "rpc": PortSpec(args["mitm_port"], application_protocol="http"),
            },
            cmd=[
                "sh",
                "-c",
                "mitmdump --mode reverse:"
                + args["l1_rpc_url"]
                + " -p "
                + str(args["mitm_port"])
            ],
        ),
    )
