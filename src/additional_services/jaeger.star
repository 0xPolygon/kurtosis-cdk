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
        )
    )


def get_jaeger_ports(args):
    ports = {
        "dashboard": PortSpec(
            16686, application_protocol="http"
        )   
    }
    exported_ports = {
        "dashboard": ports["dashboard"]
    }
    public_ports = ports_package.get_public_ports(
        exported_ports, "dashboard", args
    )
    return (ports, public_ports)