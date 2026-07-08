def get_hash(plan, image):
    result = plan.run_sh(
        name="paychain-vkey-hash-getter",
        description="Getting paychain program vkey hash",
        image=image,
        run="paychain-node vkey | tr -d '\n'",
    )
    return result.output


def get_genesis_root(plan, image, genesis_flags):
    """Compute paychain-node's deterministic height-0 (genesis) state root by
    running `paychain-node genesis-root` with the SAME genesis-determining flags
    (--ger-updater / --alloc) the node itself runs with. This value seeds the
    AggchainPayments contract's initial `lastStateRoot` so the first
    certificate's on-chain getAggchainHash matches the cert's aggchain_params.
    """
    result = plan.run_sh(
        name="paychain-genesis-root-getter",
        description="Computing paychain genesis state root",
        image=image,
        run="paychain-node genesis-root " + " ".join(genesis_flags) + " | tr -d '\n'",
    )
    return result.output
