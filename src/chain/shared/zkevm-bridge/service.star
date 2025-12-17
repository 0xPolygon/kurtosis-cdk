# Port identifiers and numbers.
RPC_PORT_ID = "rpc"
RPC_PORT_NUMBER = 8080

GRPC_PORT_ID = "grpc"
GRPC_PORT_NUMBER = 9090

METRICS_PORT_ID = "prometheus"
METRICS_PORT_NUMBER = 8090


def run(plan, args, config_artifact, claimsponsor_keystore_artifact):
    plan.add_service(
        name="zkevm-bridge-service{}".format(args.get("deployment_suffix")),
        config=ServiceConfig(
            image=args.get("zkevm_bridge_service_image"),
            files={
                "/etc/zkevm": Directory(
                    artifact_names=[config_artifact, claimsponsor_keystore_artifact]
                ),
            },
            ports={
                RPC_PORT_ID: PortSpec(RPC_PORT_NUMBER, application_protocol="http"),
                GRPC_PORT_ID: PortSpec(GRPC_PORT_NUMBER, application_protocol="grpc"),
                METRICS_PORT_ID: PortSpec(
                    METRICS_PORT_NUMBER, application_protocol="http"
                ),
            },
            entrypoint=[
                "/app/zkevm-bridge",
            ],
            cmd=["run", "--cfg", "/etc/zkevm/bridge-config.toml"],
        ),
    )
