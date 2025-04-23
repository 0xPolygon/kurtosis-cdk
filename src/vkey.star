aggchain = import_module("./aggchain/aggchain.star")
agglayer = import_module("./agglayer/agglayer.star")
constants = import_module("./package_io/constants.star")


def new_vkeys(agglayer_vkey, aggchain_vkey=None):
    return struct(
        agglayer_vkey=agglayer_vkey,
        aggchain_vkey=aggchain_vkey,
    )


def new_vkey_and_selector(vkey, vkey_selector=None):
    return struct(
        vkey=vkey,
        vkey_selector=vkey_selector,
    )


def get_vkeys(plan, args, deploy_optimism_rollup):
    consensus_handlers = {
        constants.CONSENSUS_TYPE.rollup: lambda: new_vkeys(
            agglayer_vkey=_get_agglayer_zero_vkey()
        ),
        constants.CONSENSUS_TYPE.cdk_validium: lambda: new_vkeys(
            agglayer_vkey=_get_agglayer_zero_vkey()
        ),
        constants.CONSENSUS_TYPE.pessimistic: lambda: new_vkeys(
            agglayer_vkey=_get_agglayer_vkey(plan, args),
            aggchain_vkey=_get_aggchain_vkey(plan, args)
            if deploy_optimism_rollup
            else None,
        ),
        constants.CONSENSUS_TYPE.ecdsa: lambda: new_vkeys(
            agglayer_vkey=_get_agglayer_vkey(plan, args),
            aggchain_vkey=_get_aggchain_vkey(plan, args),
        ),
        constants.CONSENSUS_TYPE.fep: lambda: new_vkeys(
            agglayer_vkey=_get_agglayer_vkey(plan, args),
            aggchain_vkey=_get_aggchain_vkey(plan, args),
        ),
    }

    consensus_type = args.get("consensus_contract_type")
    handler = consensus_handlers.get(consensus_type)
    if not handler:
        fail("Unsupported consensus type: '{}'.".format(consensus_type))
    return handler()


def _get_agglayer_zero_vkey():
    return new_vkey_and_selector(
        vkey=constants.ZERO_HASH,
    )


def _get_agglayer_vkey(plan, args):
    agglayer_image = args.get("agglayer_image")
    agglayer_vkey = agglayer.get_vkey(plan, image=agglayer_image)
    agglayer_vkey_selector = agglayer.get_vkey_selector(plan, image=agglayer_image)
    return new_vkey_and_selector(
        vkey=agglayer_vkey,
        vkey_selector=agglayer_vkey_selector,
    )


def _get_aggchain_vkey(plan, args):
    aggchain_image = args.get("aggkit_prover_image")
    aggchain_vkey = aggchain.get_vkey(plan, image=aggchain_image)
    aggchain_vkey_selector = aggchain.get_vkey_selector(plan, image=aggchain_image)
    return new_vkey_and_selector(
        vkey=aggchain_vkey,
        vkey_selector=aggchain_vkey_selector,
    )
