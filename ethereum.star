ethereum_package = import_module(
    "github.com/ethpandaops/ethereum-package/main.star@82e5a7178138d892c0c31c3839c89d53ffd42d9a"
)  # 2025-07-31
constants = import_module("./src/package_io/constants.star")

only_smc_genesis = "templates/genesis/only-smc-deployed-genesis.json"
op_rollup_created_genesis = "templates/genesis/op-genesis.json"


def run(plan, args):
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
    port_publisher = generate_port_publisher_config(args)
    l1_args = {
        "participants": [
            {
                "el_type": "geth",
                "el_image": args.get("geth_image"),
                "el_extra_params": [
                    "--log.format=json",
                    "--gcmode archive",
                ],
                "cl_type": "lighthouse",
                "cl_image": args.get("lighthouse_image"),
                "cl_extra_params": [
                    "--log-format=JSON",
                    # Disable optimistic finalized sync. This will force Lighthouse to
                    # verify every execution block hash with the execution client during
                    # finalized sync. By default block hashes will be checked in Lighthouse
                    # and only passed to the EL if initial verification fails.
                    "--disable-optimistic-finalized-sync",
                    # Disable the backfill sync rate-limiting. This allow users to just sync
                    # the entire chain as fast as possible, however it can result in
                    # resource contention which degrades staking performance. Stakers should
                    # generally choose to avoid this flag since backfill sync is not
                    # required for staking.
                    "--disable-backfill-rate-limiting",
                ],
                "vc_type": "lighthouse",
                "vc_image": LIGHTHOUSE_IMAGE,
                "vc_extra_params": [
                    "--log-format=JSON",
                ],
                "count": args["l1_participants_count"],
            }
        ],
        "network_params": {
            "additional_preloaded_contracts": custom_genesis,
            "network_id": str(args["l1_chain_id"]),
            "preregistered_validator_keys_mnemonic": args["l1_preallocated_mnemonic"],
            "preset": args["l1_preset"],
            "seconds_per_slot": args["l1_seconds_per_slot"],
            # ETH1_FOLLOW_DISTANCE, Default: 2048
            # This is used to calculate the minimum depth of block on the Ethereum 1 chain that can be considered by the Eth2 chain: it applies to the Genesis process and the processing of deposits by validators. The Eth1 chain depth is estimated by multiplying this value by the target average Eth1 block time, SECONDS_PER_ETH1_BLOCK.
            # The value of ETH1_FOLLOW_DISTANCE is not based on the expected depth of any reorgs of the Eth1 chain, which are rarely if ever more than 2-3 blocks deep. It is about providing time to respond to an incident on the Eth1 chain such as a consensus failure between clients.
            # This parameter was increased from 1024 to 2048 blocks for the beacon chain mainnet, to allow devs more time to respond if there were any trouble on the Eth1 chain.
            # The whole follow distance concept has been made redundant by the Merge and may be removed in a future upgrade, so that validators can make deposits and become active more-or-less instantly.
            "eth1_follow_distance": 2048,
            # MIN_VALIDATOR_WITHDRAWABILITY_DELAY, Default: 256
            # A validator can stop participating once it has made it through the exit queue. However, its stake remains locked for the duration of MIN_VALIDATOR_WITHDRAWABILITY_DELAY. This is to allow some time for any slashable behaviour to be detected and reported so that the validator can still be penalised (in which case the validator's withdrawable time is pushed EPOCHS_PER_SLASHINGS_VECTOR into the future).
            # Once the MIN_VALIDATOR_WITHDRAWABILITY_DELAY period has passed, the validator becomes eligible for a full withdrawal of its stake and rewards on the next withdrawals sweep, as long as it has ETH1_ADDRESS_WITHDRAWAL_PREFIX (0x01) withdrawal credentials set. In any case, being in a "withdrawable" state means that a validator has now fully exited from the protocol.
            "min_validator_withdrawability_delay": 256,
            # SHARD_COMMITTEE_PERIOD, Default: 256
            # This really anticipates the implementation of data shards, which is no longer planned, at least in its originally envisaged form. The idea is that it's bad for the stability of longer-lived committees if validators can appear and disappear very rapidly.
            # Therefore, a validator cannot initiate a voluntary exit until SHARD_COMMITTEE_PERIOD epochs after it has been activated. However, it could still be ejected by slashing before this time.
            "shard_committee_period": 256,
            # GENESIS_DELAY, Default: 12
            # This is a grace period to allow nodes and node operators time to prepare for the genesis event. The genesis event cannot occur before MIN_GENESIS_TIME. If MIN_GENESIS_ACTIVE_VALIDATOR_COUNT validators are not registered sufficiently in advance of MIN_GENESIS_TIME, then Genesis will occur GENESIS_DELAY seconds after enough validators have been registered.
            "genesis_delay": 12,
            # Enable the Electra hardfork.
            # Note: The electra fork epoch is set to 1 instead of 0 to avoid the following error in the CL node (lighthouse).
            #  Mar 11 11:56:46.595 CRIT Failed to start beacon node             reason: Built-in genesis state SSZ bytes are invalid: OffsetOutOfBounds(522733568)
            "electra_fork_epoch": derive_l1_preset(args),
        },
        "additional_services": args["l1_additional_services"],
        "port_publisher": port_publisher,
    }

    l1 = ethereum_package.run(plan, l1_args)
    cl_rpc_url = l1.all_participants[0].cl_context.beacon_http_url
    _wait_for_l1_startup(plan, cl_rpc_url)


# Generate ethereum package public ports configuration.
def generate_port_publisher_config(args):
    port_mappings = {
        "el": "l1_el_start_port",
        "cl": "l1_cl_start_port",
        "vc": "l1_vc_start_port",
        "additional_services": "l1_additional_services_start_port",
    }

    port_publisher_config = {}
    public_port_config = args.get("static_ports", {})
    for key, value in port_mappings.items():
        public_port_start = public_port_config.get(value, None)
        if public_port_start:
            port_publisher_config[key] = {
                "enabled": True,
                "public_port_start": public_port_start,
            }
    return port_publisher_config


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


def derive_l1_preset(args):
    if args["l1_preset"] == "mainnet":
        return 0
    else:
        return 1
