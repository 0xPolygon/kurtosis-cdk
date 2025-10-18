constants = import_module("./constants.star")
op_sanity_check = import_module("./op_sanity_check.star")


def _sort_dict_by_values(d):
    sorted_items = sorted(d.items(), key=lambda x: x[0])
    return {k: v for k, v in sorted_items}


def _default_participant(log_format=constants.LOG_FORMAT.json):
    return _sort_dict_by_values(
        {
            "el": {
                "type": "op-geth",
                "image": constants.DEFAULT_IMAGES.get("op_geth_image"),
                "extra_params": (
                    ["--log.format=json"]
                    if log_format == constants.LOG_FORMAT.json
                    else []
                ),
            },
            "cl": {
                "type": "op-node",
                "image": constants.DEFAULT_IMAGES.get("op_node_image"),
                "extra_params": [
                    "--rollup.l1-chain-config=/l1/genesis.json",  # required by op-node:v1.14.1
                ]
                + (
                    ["--log.format=json"]
                    if log_format == constants.LOG_FORMAT.json
                    else []
                ),
            },
        }
    )


def _default_chain(log_format=constants.LOG_FORMAT.json):
    return _sort_dict_by_values(
        {
            "participants": {
                "node1": _default_participant(log_format),
            },
            "batcher_params": _sort_dict_by_values(
                {
                    "image": constants.DEFAULT_IMAGES.get("op_batcher_image"),
                    "extra_params": [
                        "--txmgr.enable-cell-proofs",  # required for the fusaka hf
                    ]
                    + (
                        ["--log.format=json"]
                        if log_format == constants.LOG_FORMAT.json
                        else []
                    ),
                }
            ),
            "proposer_params": _sort_dict_by_values(
                {
                    "image": constants.DEFAULT_IMAGES.get("op_proposer_image"),
                    "extra_params": (
                        ["--log.format=json"]
                        if log_format == constants.LOG_FORMAT.json
                        else []
                    ),
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


def _default_args(log_format=constants.LOG_FORMAT.json):
    return _sort_dict_by_values(
        {
            "chains": {
                "001": _default_chain(log_format),
            },
            "op_contract_deployer_params": _sort_dict_by_values(
                {
                    "image": constants.DEFAULT_IMAGES.get("op_contract_deployer_image"),
                    "l1_artifacts_locator": "embedded",
                    "l2_artifacts_locator": "embedded",
                },
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
        "source": "github.com/agglayer/optimism-package/main.star@2769472af9802d5e0f460ce27ebba32de1d21005",  # overlay/main - 2025-10-18
        "predeployed_contracts": True,
    }
)


def parse_args(plan, args, op_args):
    log_format = args.get("log_format")
    default_op_args = _default_args(log_format)

    # Get L1 network configuration
    external_l1_network_params = _get_l1_config(plan, args)

    # Process optimism args
    if op_args == {}:
        op_args = dict(
            default_op_args | DEFAULT_NON_NATIVE_ARGS
        )  # create a mutable copy
        op_args["chains"] = _parse_chains(op_args["chains"], log_format)
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
    for k, v in (default_op_args | DEFAULT_NON_NATIVE_ARGS).items():
        if k in op_args:
            if k == "chains":
                op_args[k] = _parse_chains(op_args[k], log_format)
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


def _parse_chains(chains, log_format=constants.LOG_FORMAT.json):
    default_op_chain = _default_chain(log_format)

    if len(chains.keys()) == 0:
        return {"001": default_op_chain}

    chains_with_defaults = {}
    for k, v in chains.items():
        c = dict(v)  # create a mutable copy
        for kk, vv in default_op_chain.items():
            if kk in c:
                if kk == "participants":
                    c[kk] = _parse_participants(c[kk], log_format)
                else:
                    # Apply defaults
                    for kkk, vvv in default_op_chain[kk].items():
                        c[kk].setdefault(kkk, vvv)
                    c[kk] = _sort_dict_by_values(c[kk])
            else:
                c[kk] = vv
        chains_with_defaults[k] = c

    sorted_chains = {
        k: _sort_dict_by_values(v) for k, v in chains_with_defaults.items()
    }
    return sorted_chains


def _parse_participants(participants, log_format=constants.LOG_FORMAT.json):
    default_participant = _default_participant(log_format)

    if len(participants.keys()) == 0:
        return {"node1": default_participant}

    participants_with_defaults = {}
    for k, v in participants.items():
        p = dict(v)  # create a mutable copy
        for kk, vv in default_participant.items():
            if kk in p:
                # Deep merge for el/cl configs
                for kkk, vvv in default_participant[kk].items():
                    p[kk].setdefault(kkk, vvv)
                p[kk] = _sort_dict_by_values(p[kk])
            else:
                p[kk] = vv
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
