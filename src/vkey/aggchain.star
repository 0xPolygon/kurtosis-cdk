# `binary` is the aggchain prover CLI of the image: aggkit-prover (FEP) or aggkit-prover-qbft
# (AggchainQBFT). Both print the on-chain hash_bytes form of the vkey and the 4-byte selector.
def get_hash(plan, image, binary="aggkit-prover"):
    result = plan.run_sh(
        name="aggchain-vkey-hash-getter",
        description="Getting aggchain vkey hash",
        image=image,
        run="{} vkey | tr -d '\n'".format(binary),
    )
    return result.output


def get_selector(plan, image, binary="aggkit-prover"):
    result = plan.run_sh(
        name="aggchain-vkey-selector-getter",
        description="Getting aggchain vkey selector",
        image=image,
        run="{} vkey-selector | tr -d '\n'".format(binary),
    )
    return result.output
