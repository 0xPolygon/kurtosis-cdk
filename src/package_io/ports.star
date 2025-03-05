dict = import_module("./dict.star")


def get_public_ports(port_config, start_port_name, args):
    public_port_config = args.get("static_ports", {})
    if not public_port_config:
        return {}

    start_port = public_port_config.get(start_port_name, None)
    if not start_port:
        return {}

    public_ports = {}
    sorted_port_config = dict.sort_dict_by_values(port_config)
    for index, (key, port) in enumerate(sorted_port_config.items()):
        new_port = PortSpec(
            number=start_port + index,
            # Some ports don't define a transport protocol which makes this specific instruction fail.
            # Solutions:
            #   1. We don't care about transport protocol in the case of public ports.
            #   2. We make it mandatory to define transport protocols in PortSpec.
            # transport_protocol=port.get("transport_protocol"),
            application_protocol=port.application_protocol,
        )
        public_ports[key] = new_port
    return public_ports
