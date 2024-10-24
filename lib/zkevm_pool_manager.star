ports_package = import_module("../src/package_io/ports.star")


def create_zkevm_pool_manager_service_config(args, config_artifact):
    zkevm_pool_manager_service_name = "zkevm-pool-manager" + args["deployment_suffix"]
    (ports, public_ports) = get_zkevm_pool_manager_ports(args)
    zkevm_pool_manager_service_config = ServiceConfig(
        image=args["zkevm_pool_manager_image"],
        ports=ports,
        public_ports=public_ports,
        files={
            "/etc/pool-manager": Directory(artifact_names=[config_artifact]),
        },
        entrypoint=["/bin/sh", "-c"],
        cmd=[
            "/app/zkevm-pool-manager run --cfg /etc/pool-manager/pool-manager-config.toml",
        ],
    )
    return {zkevm_pool_manager_service_name: zkevm_pool_manager_service_config}


def get_zkevm_pool_manager_ports(args):
    ports = {
        "http": PortSpec(args["zkevm_pool_manager_port"], application_protocol="http"),
    }
    public_ports = ports_package.get_public_ports(
        ports, "zkevm_pool_manager_start_port", args
    )
    return (ports, public_ports)
