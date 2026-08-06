# The three plan-time values HyperPay owns and this fork only forwards
# (S11b T4/T3; ADR-010's ownership boundary, ADR-011).
#
# Every function here runs ONE `hp-stack` subcommand inside
# `hyperpay_node_image` and captures its stdout. None of them computes,
# defaults, or reformats anything: if a value is wrong, it is wrong in the
# hyperpay repo where it is tested, not silently different here.
#
# `2>/dev/null` IS LOAD-BEARING, and this cost a bring-up to learn.
# `plan.run_sh(...).output` is the command's COMBINED stdout+stderr, not its
# stdout. Every `hp-stack` plan-time subcommand deliberately prints the bare
# value on stdout and its derivation note on stderr (so a human sees WHY a
# value is what it is), and without the redirect that whole multi-line note
# lands in the value. The first live T5 bring-up died at
# `render_templates(create_new_rollup.json)` with
#   Caused by: invalid character '\n' in string literal
# and an `aggchain_vkey_hash` whose value was the vkey essay. A dry-run cannot
# see this: it never executes `run_sh`.
#
# `tail -n1` on top of that is belt and braces: the contract is one line of
# stdout, and if a subcommand ever prints a second, the LAST line is still the
# value rather than a silently concatenated pair.


def get_hash(plan, image):
    """The owned aggchain vkey hash registered under selector 0x10000001.

    `hp-stack vkey` prints what `hyperpay-aggregator`'s
    `AggchainProofService` actually puts in `Sp1StarkProof.vkey`, from the
    shared `hyperpay_aggregator::vkey` module — so the AggLayerGateway
    registration and the prover agree by construction, not by review.
    """
    result = plan.run_sh(
        name="hyperpay-vkey-hash-getter",
        description="Getting the HyperPay aggchain vkey hash",
        image=image,
        run="hp-stack vkey 2>/dev/null | tail -n1 | tr -d '\n'",
    )
    return result.output


def get_genesis_root(plan, image, profile):
    """The height-0 protocol state root, for `aggchainParams.startingStateRoot`.

    S11b trap T-a: the L1 contract's initial `lastStateRoot` must equal the
    first certificate's `prev_state_root`, or agglayer rejects EVERY
    certificate with "Aggchain hash mismatch". `hp-stack genesis-root` reads
    that value from `hyperpay_aggregator::genesis::genesis_state()` — the same
    function the aggregator daemon starts a fresh chain from (one function,
    two callers, per the trap's own prescription).

    Unlike the paychain precedent there is no `genesis_alloc_flags()` to keep
    in sync here: HyperPay's genesis is a committed preset selected by
    profile, so `--profile` IS the complete set of genesis-determining inputs,
    and it is the same flag the launcher and the materialize step pass.
    """
    result = plan.run_sh(
        name="hyperpay-genesis-root-getter",
        description="Computing the HyperPay genesis (height-0) protocol state root",
        image=image,
        run="hp-stack genesis-root --profile {} 2>/dev/null | tail -n1 | tr -d '\n'".format(
            profile
        ),
    )
    return result.output


def get_facade_address(plan, image, profile, field):
    """One of the bridge shard's facade addresses (`bridge`, `ger-manager`).

    HyperPay's facades live at ITS OWN genesis addresses, not at the sovereign
    deploy's L2 predeploys — so aggkit's `BridgeAddr`/`GlobalExitRootAddr`/
    `GlobalExitRootL2` and the aggoracle's injection target have to be told
    what they are. `hp-stack facades --field <f>` reads them from the same
    `Genesis` every HyperPay service loads.
    """
    result = plan.run_sh(
        name="hyperpay-facade-{}-getter".format(field),
        description="Reading the HyperPay {} facade address".format(field),
        image=image,
        run="hp-stack facades --profile {} --field {} 2>/dev/null | tail -n1 | tr -d '\n'".format(
            profile, field
        ),
    )
    return result.output
