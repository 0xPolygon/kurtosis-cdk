def get_vkey(plan, image):
    result = plan.run_sh(
        name="aggkit-prover-vkey-getter",
        description="Getting aggkit prover vkey",
        image=image,
        run="aggkit-prover vkey | tr -d '\n'",
    )
    # FIXME: The aggchain vkey may include a 0x prefix in the future and we'll need to fix this.
    return "0x{}".format(result.output)


def get_vkey_selector(plan, image):
    result = plan.run_sh(
        name="aggkit-prover-vkey-selector-getter",
        description="Getting aggkit prover vkey selector",
        image=image,
        run="aggkit-prover vkey-selector | tr -d '\n'",
    )
    # FIXME: The aggchain vkey selector may include a 0x prefix in the future and we'll need to fix thi
    return "0x{}".format(result.output)
