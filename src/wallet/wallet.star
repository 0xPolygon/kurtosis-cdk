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
    # Extract numeric value from the value parameter
    target_value = value.replace("ether", "")

    # Use a bash script file approach to avoid runtime value issues
    plan.run_sh(
        name="conditional-address-funder",
        description="Checking balance and conditionally funding address {} on network {}".format(
            address, rpc_url
        ),
        image=constants.TOOLBOX_IMAGE,
        run='bash -c \'CURRENT_BALANCE=$(cast balance --ether --rpc-url "$RPC_URL" "$ADDRESS"); if (( $(echo "$CURRENT_BALANCE < $TARGET_VALUE" | bc -l) )); then echo "Current balance: $CURRENT_BALANCE ether, target: $TARGET_VALUE ether. Funding..."; cast send --legacy --confirmations 5 --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --value "$VALUE" "$ADDRESS"; echo "Transaction sent, waiting for confirmation..."; echo "Funding completed for $ADDRESS"; else echo "Address $ADDRESS already has sufficient balance: $CURRENT_BALANCE >= $TARGET_VALUE ether"; fi\'',
        env_vars={
            "ADDRESS": address,
            "PRIVATE_KEY": funder_private_key,
            "RPC_URL": rpc_url,
            "VALUE": value,
            "TARGET_VALUE": target_value,
        },
    )
