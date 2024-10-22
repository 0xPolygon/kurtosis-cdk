service_package = import_module("./lib/service.star")

ARTIFACTS = [
    {
        "name": "run-l2-contract-setup.sh",
        "file": "./templates/contract-deploy/run-l2-contract-setup.sh",
    },
]


def run(plan, args):
    artifact_paths = list(ARTIFACTS)

    l2_rpc_service = plan.get_service(
        name="cdk-erigon-sequencer" + args["deployment_suffix"]
    )
    l2_rpc_url = "http://{}:{}".format(
        l2_rpc_service.ip_address, l2_rpc_service.ports["rpc"].number
    )

    artifacts = []
    for artifact_cfg in artifact_paths:
        template = read_file(src=artifact_cfg["file"])
        artifact = plan.render_templates(
            name=artifact_cfg["name"],
            config={
                artifact_cfg["name"]: struct(
                    template=template,
                    data=args
                    | {
                        "l2_rpc_url": l2_rpc_url,
                        "deterministic_deployment_proxy_branch": "master",
                    },
                )
            },
        )
        artifacts.append(artifact)

    # Create helper service to deploy contracts
    contracts_service_name = "contracts-l2" + args["deployment_suffix"]
    plan.add_service(
        name=contracts_service_name,
        config=ServiceConfig(
            image=args["l2_contracts_image"],
            files={
                "/opt/zkevm": Directory(persistent_key="zkevm-l2-artifacts"),
                "/opt/contract-deploy/": Directory(artifact_names=artifacts),
            },
            # These two lines are only necessary to deploy to any Kubernetes environment (e.g. GKE).
            entrypoint=["bash", "-c"],
            cmd=["sleep infinity"],
            user=User(uid=0, gid=0),  # Run the container as root user.
        ),
    )

    # Deploy contracts.
    plan.exec(
        description="Deploying contracts on L2",
        service_name=contracts_service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                "chmod +x {0} && {0}".format(
                    "/opt/contract-deploy/run-l2-contract-setup.sh"
                ),
            ]
        ),
    )
