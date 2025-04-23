vkey_module = import_module("../vkey.star")


def get_vkey_and_selector(plan, image):
    vkey = _get_vkey(plan, image)
    vkey_selector = _get_vkey_selector(plan, image)
    return vkey_module.new_vkey_and_selector(
        vkey=vkey,
        vkey_selector=vkey_selector,
    )


def _get_vkey(plan, image):
    result = plan.run_sh(
        name="aggkit-prover-vkey-getter",
        description="Getting aggkit prover vkey",
        image=image,
        run="aggkit-prover vkey | tr -d '\n'",
    )
    #  FIXME: At some point in the future, the aggchain vkey hash will probably come prefixed with 0x and we'll need to fix this.
    return "0x{}".format(result.output)


def _get_vkey_selector(plan, image):
    result = plan.run_sh(
        name="aggkit-prover-vkey-selector-getter",
        description="Getting aggkit prover vkey selector",
        image=image,
        run="aggkit-prover vkey-selector | tr -d '\n'",
    )
    # FIXME: At some point in the future, the aggchain vkey selector will probably come prefixed with 0x and we'll need to fix this.
    return "0x{}".format(result.output)
