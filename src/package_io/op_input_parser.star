constants = import_module("./constants.star")
op_sanity_check = import_module("./op_sanity_check.star")


def _sort_dict_by_values(d):
    sorted_items = sorted(d.items(), key=lambda x: x[0])
    return {k: v for k, v in sorted_items}


DEFAULT_PARTICIPANT = _sort_dict_by_values(
    {
        "el": {
            "type": "op-geth",
            "image": constants.DEFAULT_IMAGES.get("op_geth_image"),
            "extra_params": ["--log.format=json"],
        },
        "cl": {
            "type": "op-node",
            "image": constants.DEFAULT_IMAGES.get("op_node_image"),
            "extra_params": ["--log.format=json"],
        },
    }
)

DEFAULT_CHAIN = _sort_dict_by_values(
    {
        "participants": {
            "node1": DEFAULT_PARTICIPANT,
        },
        "batcher_params": _sort_dict_by_values(
            {
                "image": constants.DEFAULT_IMAGES.get("op_batcher_image"),
                "extra_params": ["--log.format=json"],
            }
        ),
        "proposer_params": _sort_dict_by_values(
            {
                "image": constants.DEFAULT_IMAGES.get("op_proposer_image"),
                "extra_params": ["--log.format=json"],
            }
        ),
        "network_params": _sort_dict_by_values(
            {
                # The rollup chain ID
                "network_id": 2151908,
                # The rollup block time
                "seconds_per_slot": 1,
                # Hard fork activation times
                "isthmus_time_offset": 0,
            }
        ),
    }
)

DEFAULT_ARGS = _sort_dict_by_values(
    {
        "chains": {
            "001": DEFAULT_CHAIN,
        },
        "op_contract_deployer_params": _sort_dict_by_values(
            {
                "image": constants.DEFAULT_IMAGES.get("op_contract_deployer_image"),
                "l1_artifacts_locator": "tag://op-contracts/v4.0.0",
                "l2_artifacts_locator": "tag://op-contracts/v4.0.0",
            }
        ),
        "observability": _sort_dict_by_values(
            {
                "enabled": False,
            }
        ),
    }
)

DEFAULT_NON_NATIVE_ARGS = _sort_dict_by_values(
    {
        "source": "github.com/agglayer/optimism-package/main.star@cd42dfd8cc263202bd89c8a31882b42d004436d6",  # debug - 2025-10-02
        "predeployed_contracts": True,
    }
)


def parse_args(plan, args, op_args):
    # Get L1 network configuration
    external_l1_network_params = _get_l1_config(plan, args)

    # Process optimism args
    if op_args == {}:
        op_args = dict(DEFAULT_ARGS | DEFAULT_NON_NATIVE_ARGS)  # create a mutable copy
        op_args["chains"] = _parse_chains(op_args["chains"])
        source = op_args.pop("source")
        predeployed_contracts = op_args.pop("predeployed_contracts")
        return _sort_dict_by_values(
            {
                "source": source,
                "predeployed_contracts": predeployed_contracts,
                "optimism_package": op_args,
                "external_l1_network_params": external_l1_network_params,
            }
        )

    op_args = dict(op_args)  # create a mutable copy
    for k, v in (DEFAULT_ARGS | DEFAULT_NON_NATIVE_ARGS).items():
        if k in op_args:
            if k == "chains":
                op_args[k] = _parse_chains(op_args[k])
            elif type(v) == type({}):
                # Apply defaults
                for kk, vv in v.items():
                    op_args[k].setdefault(kk, vv)
                op_args[k] = _sort_dict_by_values(op_args[k])
        else:
            op_args[k] = v

    sorted_op_args = _sort_dict_by_values(op_args)

    # Extract meta fields
    source = sorted_op_args.pop("source")
    predeployed_contracts = sorted_op_args.pop("predeployed_contracts")

    # Sanity check
    op_sanity_check.sanity_check(plan, args, sorted_op_args, source)

    return _sort_dict_by_values(
        {
            "source": source,
            "predeployed_contracts": predeployed_contracts,
            "optimism_package": sorted_op_args,
            "external_l1_network_params": external_l1_network_params,
        }
    )


def _parse_chains(chains):
    if len(chains.keys()) == 0:
        return {"001": DEFAULT_CHAIN}

    chains_with_defaults = {}
    for k, v in chains.items():
        c = dict(v)  # create a mutable copy
        for kk, vv in DEFAULT_CHAIN.items():
            if kk in c:
                if kk == "participants":
                    c[kk] = _parse_participants(c[kk])
                else:
                    # Apply defaults
                    for kkk, vvv in DEFAULT_CHAIN[kk].items():
                        c[kk].setdefault(kkk, vvv)
                    c[kk] = _sort_dict_by_values(c[kk])
            else:
                c[kk] = vv
        chains_with_defaults[k] = c

    sorted_chains = {
        k: _sort_dict_by_values(v) for k, v in chains_with_defaults.items()
    }
    return sorted_chains


def _parse_participants(participants):
    if len(participants.keys()) == 0:
        return {"node1": DEFAULT_PARTICIPANT}

    participants_with_defaults = {}
    for k, v in participants.items():
        p = dict(v)  # create a mutable copy
        for kk, vv in DEFAULT_PARTICIPANT.items():
            p.setdefault(kk, vv)
        participants_with_defaults[k] = p

    sorted_participants = {
        k: _sort_dict_by_values(v) for k, v in participants_with_defaults.items()
    }
    return sorted_participants


def _get_l1_config(plan, args):
    l1_chain_id = str(args.get("l1_chain_id", ""))
    l1_rpc_url = args.get("l1_rpc_url", "")
    l1_ws_url = args.get("l1_ws_url", "")
    l1_beacon_url = args.get("l1_beacon_url", "")

    # Derive private key from mnemonic
    l1_preallocated_mnemonic = args.get("l1_preallocated_mnemonic", "")
    private_key_result = plan.run_sh(
        description="Deriving the private key from the mnemonic",
        image=constants.TOOLBOX_IMAGE,
        run="cast wallet private-key --mnemonic \"{}\" | tr -d '\n'".format(
            l1_preallocated_mnemonic
        ),
    )
    private_key = private_key_result.output

    return {
        "network_id": l1_chain_id,
        "rpc_kind": "standard",
        "el_rpc_url": l1_rpc_url,
        "el_ws_url": l1_ws_url,
        "cl_rpc_url": l1_beacon_url,
        "priv_key": private_key,
    }
