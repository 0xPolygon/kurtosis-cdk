vkey_module = import_module("../src/vkey.star")


def get_vkey_and_selector(plan, image):
    vkey = _get_vkey(plan, image)
    vkey_selector = _get_vkey_selector(plan, image)
    return vkey_module.new_vkey_and_selector(
        vkey=vkey,
        vkey_selector=vkey_selector,
    )


def _get_vkey(plan, image):
    result = plan.run_sh(
        name="agglayer-vkey-getter",
        description="Getting agglayer vkey",
        image=image,
        run="agglayer vkey | tr -d '\n'",
    )
    return result.output


def _get_vkey_selector(plan, image):
    result = plan.run_sh(
        name="agglayer-vkey-selector-getter",
        description="Getting agglayer vkey selector",
        image=image,
        run="agglayer vkey-selector | tr -d '\n'",
    )
    # FIXME: At some point in the future, the agglayer vkey selector will probably come prefixed with 0x and we'll need to fix this.
    return "0x{}".format(result.output)
