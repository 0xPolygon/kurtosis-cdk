ports_package = import_module("../package_io/ports.star")

def run(plan, args):

    (ports, public_ports) = get_jaeger_ports(args)

    jaeger_env_vars = {
        "COLLECTOR_OTLP_ENABLED": "true",
    }

    plan.add_service(
        name="jaeger" + args.get("deployment_suffix"),
        config=ServiceConfig(
            image="jaegertracing/all-in-one:1.42",
            ports=ports,
            public_ports=public_ports,
            env_vars=jaeger_env_vars,
            cmd=["run", "--config-path", "/etc/aggkit/aggkit-prover-config.toml"],
        )
    )


def get_jaeger_ports(args):
    ports = {
        "udpreceiver": PortSpec(
            6831, application_protocol="udp"
        ),
        "otlpgrpc": PortSpec(
            4317, application_protocol="http"
        ),
        "otlphttp": PortSpec(
            4318, application_protocol="http"
        ),
        "pprofext": PortSpec(
            1888, application_protocol="tcp"
        ),
        "prometheus1": PortSpec(
            8888, application_protocol="tcp"
        ),
        "prometheus2": PortSpec(
            8889, application_protocol="tcp"
        ),   
        "dashboard": PortSpec(
            16686, application_protocol="http"
        ),     
    }
    exported_ports = {
        "dashboard": ports["dashboard"]
    }
    public_ports = ports_package.get_public_ports(
        exported_ports, "monitoring_port", args
    )
    return (ports, public_ports)