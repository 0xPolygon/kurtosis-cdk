constants = import_module("../../src/package_io/constants.star")


def new(plan):
    result = plan.run_sh(
        name="private-key-generator",
        description="Generating a new private key",
        image=constants.TOOLBOX_IMAGE,
        run="cast wallet new --json | jq --raw-output '.[0].private_key' | tr -d '\n'",
    )
    private_key = result.output

    result = plan.run_sh(
        name="address-deriver",
        description="Deriving address from private key",
        image=constants.TOOLBOX_IMAGE,
        run="cast wallet address --private-key ${PRIVATE_KEY} | tr -d '\n'",
        env_vars={
            "PRIVATE_KEY": private_key,
        },
    )
    address = result.output

    return struct(
        address=address,
        private_key=private_key,
    )


def fund(plan, address, rpc_url, funder_private_key, value="1000ether"):
    plan.run_sh(
        name="address-funder",
        description="Funding address {} on network {}".format(address, rpc_url),
        image=constants.TOOLBOX_IMAGE,
        run="cast send --legacy --rpc-url ${RPC_URL} --private-key ${PRIVATE_KEY} --value ${VALUE} ${ADDRESS}",
        env_vars={
            "ADDRESS": address,
            "PRIVATE_KEY": funder_private_key,
            "RPC_URL": rpc_url,
            "VALUE": value,
        },
    )
