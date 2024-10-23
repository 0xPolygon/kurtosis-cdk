def get_public_ports(port_config, start_port_name, args):
    static_port_config = args.get("static_ports", {})
    if not static_port_config:
        return {}

    start_port = static_port_config.get(start_port_name, None)
    if not start_port:
        return {}

    public_ports = {}
    for index, (key, port) in enumerate(port_config.items()):
        new_port = PortSpec(
            number=start_port + index,
            # Some ports don't define a transport protocol which makes this specific intruction fail.
            # Solutions:
            #   1. We don't care about transport protocol in the case of public ports.
            #   2. We make it mandatory to define transport protocols in PortSpec.
            # transport_protocol=port.get("transport_protocol"),
            application_protocol=port.application_protocol,
        )
        public_ports[key] = new_port
    return public_ports
