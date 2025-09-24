constants = import_module("./src/package_io/constants.star")
input_parser = import_module("./input_parser.star")


def _sort_dict_by_values(d):
    sorted_items = sorted(d.items(), key=lambda x: x[0])
    return {k: v for k, v in sorted_items}


DEFAULT_PARTICIPANT = _sort_dict_by_values(
    {
        "count": 1,
        # Execution layer
        "el_type": "op-geth",
        "el_image": input_parser.DEFAULT_IMAGES.get("op_geth_image"),
        "el_extra_params": ["--log.format=json"],
        # Consensus layer
        "cl_type": "op-node",
        "cl_image": input_parser.DEFAULT_IMAGES.get("op_node_image"),
        "cl_extra_params": ["--log.format=json"],
    }
)

DEFAULT_CHAIN = _sort_dict_by_values(
    {
        "participants": [DEFAULT_PARTICIPANT],
        "batcher_params": _sort_dict_by_values(
            {
                "image": input_parser.DEFAULT_IMAGES.get("op_batcher_image"),
                "extra_params": ["--log.format=json"],
            }
        ),
        "proposer_params": _sort_dict_by_values(
            {
                "image": input_parser.DEFAULT_IMAGES.get("op_proposer_image"),
                "extra_params": ["--log.format=json"],
            }
        ),
        "network_params": _sort_dict_by_values(
            {
                # Name maps to l2_services_suffix in optimism-package.
                # The optimism-package appends a suffix with the following format: `-<name>`.
                # However, our deployment suffix already starts with a "-", so we remove it here.
                "name": input_parser.DEFAULT_ARGS.get("deployment_suffix")[1:],
                # The rollup chain ID
                "network_id": str(
                    input_parser.DEFAULT_ROLLUP_ARGS.get("zkevm_rollup_chain_id")
                ),
                # The rollup block time
                "seconds_per_slot": 1,
                # Hard fork activation times
                "isthmus_time_offset": 0,
            }
        ),
    }
)

ARTIFACTS_LOCATOR = "https://storage.googleapis.com/oplabs-contract-artifacts/artifacts-v1-02024c5a26c16fc1a5c716fff1c46b5bf7f23890d431bb554ddbad60971211d4.tar.gz"

DEFAULT_ARGS = _sort_dict_by_values(
    {
        # Meta configuration - non native to optimism-package
        "source": "github.com/agglayer/optimism-package/main.star@cc37713aff9c4955dd6975cdbc34072a1286754e",
        "predeployed_contracts": True,
        # Native optimism-package configuration
        "chains": [DEFAULT_CHAIN],
        "op_contract_deployer_params": _sort_dict_by_values(
            {
                "image": input_parser.DEFAULT_IMAGES.get("op_contract_deployer_image"),
                "l1_artifacts_locator": ARTIFACTS_LOCATOR,
                "l2_artifacts_locator": ARTIFACTS_LOCATOR,
            }
        ),
        "observability": _sort_dict_by_values(
            {
                "enabled": False,
            }
        ),
    }
)


def parse_optimism_args(plan, args, optimism_args):
    # Get L1 network configuration
    external_l1_network_params = _get_l1_config(plan, args)

    # Process optimism args
    if optimism_args == {}:
        optimism_args = dict(DEFAULT_ARGS)  # create a mutable copy
        optimism_args["chains"] = _parse_chains(optimism_args["chains"])
        source = optimism_args.pop("source")
        predeployed_contracts = optimism_args.pop("predeployed_contracts")
        return _sort_dict_by_values(
            {
                "source": source,
                "predeployed_contracts": predeployed_contracts,
                "optimism_package": optimism_args,
                "external_l1_network_params": external_l1_network_params,
            }
        )

    optimism_args = dict(optimism_args)  # create a mutable copy
    for k, v in DEFAULT_ARGS.items():
        if k in optimism_args:
            if k == "chains":
                optimism_args[k] = _parse_chains(optimism_args[k])
            elif type(v) == type(True):
                continue
            else:
                # Apply defaults
                for kk, vv in v.items():
                    optimism_args[k].setdefault(kk, vv)
                optimism_args[k] = _sort_dict_by_values(optimism_args[k])
        else:
            optimism_args[k] = v

    sorted_optimism_args = _sort_dict_by_values(optimism_args)

    # Extract meta fields
    source = sorted_optimism_args.pop("source")
    predeployed_contracts = sorted_optimism_args.pop("predeployed_contracts")

    # Run the optimism-package sanity check
    optimism_package_sanity_check_module = import_module(
        source.replace("main", "src/package_io/sanity_check")
    )
    optimism_package_sanity_check_module.sanity_check(plan, sorted_optimism_args)

    return _sort_dict_by_values(
        {
            "source": source,
            "predeployed_contracts": predeployed_contracts,
            "optimism_package": sorted_optimism_args,
            "external_l1_network_params": external_l1_network_params,
        }
    )


def _parse_chains(chains):
    if len(chains) == 0:
        return [DEFAULT_CHAIN]

    chains_with_defaults = []
    for c in chains:
        c = dict(c)  # create a mutable copy
        for k, v in DEFAULT_CHAIN.items():
            if k in c:
                if k == "participants":
                    c[k] = _parse_participants(c[k])
                else:
                    # Apply defaults
                    for kk, vv in DEFAULT_CHAIN[k].items():
                        c[k].setdefault(kk, vv)
                    c[k] = _sort_dict_by_values(c[k])
            else:
                c[k] = v
        chains_with_defaults.append(c)

    sorted_chains = [_sort_dict_by_values(c) for c in chains_with_defaults]
    return sorted_chains


def _parse_participants(participants):
    if len(participants) == 0:
        return [DEFAULT_PARTICIPANT]

    participants_with_defaults = []
    for p in participants:
        p = dict(p)  # create a mutable copy
        for k, v in DEFAULT_PARTICIPANT.items():
            p.setdefault(k, v)
        participants_with_defaults.append(p)

    sorted_participants = [_sort_dict_by_values(p) for p in participants_with_defaults]
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
