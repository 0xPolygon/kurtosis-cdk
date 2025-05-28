def get_hash(plan, image):
    result = plan.run_sh(
        name="agglayer-vkey-hash-getter",
        description="Getting agglayer vkey hash",
        image=image,
        run="agglayer vkey | tr -d '\n'",
    )
    return result.output


def get_selector(plan, image):
    result = plan.run_sh(
        name="agglayer-vkey-selector-getter",
        description="Getting agglayer vkey selector",
        image=image,
        run="agglayer vkey-selector | tr -d '\n'",
    )
    return result.output
