def get_vkey(plan, image):
    result = plan.run_sh(
        name="agglayer-vkey-getter",
        description="Getting agglayer vkey",
        image=image,
        run="agglayer vkey | tr -d '\n'",
    )
    return result.output


def get_vkey_selector(plan, image):
    result = plan.run_sh(
        name="agglayer-vkey-selector-getter",
        description="Getting agglayer vkey selector",
        image=image,
        run="agglayer vkey-selector | tr -d '\n'",
    )
    # FIXME: The agglayer vkey selector may include a 0x prefix in the future and we'll need to fix thi
    return "0x{}".format(result.output)
