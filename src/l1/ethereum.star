ethereum_package = import_module(
    "github.com/ethpandaops/ethereum-package/main.star@eb8c590a3634188ecb29ae1319ee53bd356e16e7"
)  # 2026-02-27
constants = import_module("../package_io/constants.star")

only_smc_genesis = "../../static_files/contracts/genesis/only-smc-deployed-genesis.json"
op_rollup_created_genesis = "../../static_files/contracts/genesis/op-genesis.json"


def run(plan, args):
    # Custom genesis configuration.
    if args.get("l1_custom_genesis"):
        if args.get("consensus_contract_type") == constants.CONSENSUS_TYPE.pessimistic:
            plan.print(
                "Custom genesis is enabled with pessimistic consensus, using the forked ethereum package for pessimistic."
            )
            custom_genesis = read_file(src=op_rollup_created_genesis)
        elif (
            args.get("consensus_contract_type") == constants.CONSENSUS_TYPE.cdk_validium
            or args.get("consensus_contract_type") == constants.CONSENSUS_TYPE.rollup
        ):
            plan.print(
                "Custom genesis is enabled for rollup/validium consensus, using the forked ethereum package without any rollup deployed."
            )
            custom_genesis = read_file(src=only_smc_genesis)
        else:
            fail("Unknown consensus contract type")
    else:
        plan.print("Custom genesis is disabled, using the default ethereum package.")
        custom_genesis = ""

    # Log format configuration.
    log_format = args.get("log_format")
    el_type = args.get("l1_el_type")
    cl_type = args.get("l1_cl_type")

    # Resolve client images: look up "<type>_image" in args, falling back to
    # the ethereum-package default when the key does not exist.
    el_image = args.get(el_type + "_image")
    cl_image = args.get(cl_type + "_image")

    # Client-specific EL extra params.
    el_extra_params = {
        "reth": [
            "--rpc.eth-proof-window=1000000",
        ],
        "geth": [
            "--log.format={}".format(
                "json" if log_format == constants.LOG_FORMAT.json else "terminal"
            ),
            "--gcmode=archive",
            "--syncmode=full",
        ],
    }.get(el_type)

    # Client-specific CL extra params.
    cl_extra_params = {
        "lighthouse": [
            "--disable-optimistic-finalized-sync",
            "--disable-backfill-rate-limiting",
        ]
        + (["--log-format=JSON"] if log_format == constants.LOG_FORMAT.json else []),
    }.get(cl_type)

    # Client-specific VC extra params.
    vc_extra_params = {
        "lighthouse": ["--log-format=JSON"]
        if log_format == constants.LOG_FORMAT.json
        else [],
    }.get(cl_type)

    participant = {
        # General
        "count": 1,
        # Consensus client
        "cl_type": cl_type,
        "cl_extra_params": cl_extra_params,
        "cl_image": cl_image,
        # Execution client
        "el_type": el_type,
        "el_extra_params": el_extra_params,
        "el_image": el_image,
        # Validator client
        "use_separate_vc": True,
        "vc_type": cl_type,
        "vc_extra_params": vc_extra_params,
        "vc_image": cl_image,
        # Fulu hard fork config
        # In PeerDAS, a supernode is a node that custodies and samples all data columns (i.e. holds full awareness
        # of the erasure-coded blob data) and helps with distributed blob building — computing proofs and
        # broadcasting data on behalf of the proposer.
        # Since we don't enable perfect PeerDAS in the config, we need to have at least one supernode.
        "supernode": True,
    }

    l1_args = {
        "participants": [participant],
        "network_params": {
            "network_id": str(args["l1_chain_id"]),
            "additional_preloaded_contracts": custom_genesis,
            "preregistered_validator_keys_mnemonic": args["l1_preallocated_mnemonic"],
            "seconds_per_slot": args["l1_seconds_per_slot"],
            # The "minimal" preset is useful for rapid testing and development.
            # It takes 192 seconds to get to finalized epoch vs 1536 seconds with mainnet defaults.
            "preset": "minimal",
            # Ethereum hard fork configurations.
            # Supported fork epochs are documented in `static_files/genesis-generation-config/el-cl/values.env.tmpl`.
            # in the ethereum package repository.
            "altair_fork_epoch": 0,
            "bellatrix_fork_epoch": 0,
            "capella_fork_epoch": 0,
            "deneb_fork_epoch": 1,
            "electra_fork_epoch": 2,
            "fulu_fork_epoch": 3,  # Requires a supernode or perfect PeerDAS to be enabled.
        },
        "additional_services": args["l1_additional_services"],
    }
    result = ethereum_package.run(plan, l1_args)

    cl_rpc_url = result.all_participants[0].cl_context.beacon_http_url
    _wait_for_l1_startup(plan, cl_rpc_url)

    return result


def _wait_for_l1_startup(plan, cl_rpc_url):
    plan.run_sh(
        name="wait-for-l1-startup",
        description="Wait for L1 to start up - it can take up to 2 minutes",
        env_vars={
            "CL_RPC_URL": cl_rpc_url,
        },
        run="\n".join(
            [
                "while true; do",
                "  sleep 5;",
                '  slot=$(curl --silent $CL_RPC_URL/eth/v1/beacon/headers/ | jq --raw-output ".data[0].header.message.slot");',
                '  echo "L1 Chain is starting up... Current slot: $slot";',
                '  if [[ "$slot" =~ ^[0-9]+$ ]] && [[ "$slot" -gt "0" ]]; then',
                '    echo "✅ L1 Chain has started!";',
                "    break;",
                "  fi;",
                "done",
            ]
        ),
        wait="5m",
    )
