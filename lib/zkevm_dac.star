ports_package = import_module("../src/package_io/ports.star")


def create_dac_service_config(args, config_artifact, dac_keystore_artifact):
    dac_name = "zkevm-dac" + args["deployment_suffix"]
    (ports, public_ports) = get_dac_ports(args)
    dac_service_config = ServiceConfig(
        image=args["zkevm_da_image"],
        ports=ports,
        public_ports=public_ports,
        files={
            "/etc/zkevm": Directory(
                artifact_names=[config_artifact, dac_keystore_artifact]
            ),
        },
        entrypoint=[
            "/app/cdk-data-availability",
        ],
        cmd=["run", "--cfg", "/etc/zkevm/dac-config.toml"],
    )
    return {dac_name: dac_service_config}


def get_dac_ports(args):
    ports = {
        "dac": PortSpec(args["zkevm_dac_port"], application_protocol="http"),
    }
    public_ports = ports_package.get_public_ports(ports, "zkevm_dac_start_port", args)
    return (ports, public_ports)
