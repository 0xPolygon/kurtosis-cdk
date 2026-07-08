def get_hash(plan, image):
    result = plan.run_sh(
        name="paychain-vkey-hash-getter",
        description="Getting paychain program vkey hash",
        image=image,
        run="paychain-node vkey | tr -d '\n'",
    )
    return result.output
