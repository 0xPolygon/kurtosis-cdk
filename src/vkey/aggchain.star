def get_hash(plan, image):
    result = plan.run_sh(
        name="aggchain-vkey-hash-getter",
        description="Getting aggchain vkey hash",
        image=image,
        run="aggkit-prover vkey | tr -d '\n'",
    )
    return result.output


def get_selector(plan, image):
    result = plan.run_sh(
        name="aggchain-vkey-selector-getter",
        description="Getting aggchain vkey selector",
        image=image,
        run="aggkit-prover vkey-selector | tr -d '\n'",
    )
    return result.output
