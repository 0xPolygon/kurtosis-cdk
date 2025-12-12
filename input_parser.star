constants = import_module("./src/package_io/constants.star")
dict = import_module("./src/package_io/dict.star")
op_input_parser = import_module("./src/package_io/op_input_parser.star")


# The deployment process is divided into various stages.
# You can deploy the whole stack and then only deploy a subset of the components to perform an
# an upgrade or to test a new version of a component.
DEFAULT_DEPLOYMENT_STAGES = {
    # Deploy a local L1 chain using the ethereum-package.
    # Set to false to use an external L1 like Sepolia.
    # Note that it will require a few additional parameters.
    "deploy_l1": True,
    # Deploy agglayer contracts on L1 (as well as fund accounts).
    # Set to false to use pre-deployed agglayer contracts.
    # Note that it will require a few additional parameters.
    "deploy_agglayer_contracts_on_l1": True,
    # Deploy databases.
    "deploy_databases": True,
    # Deploy CDK central/trusted environment.
    "deploy_cdk_central_environment": True,
    # Deploy CDK bridge infrastructure.
    "deploy_cdk_bridge_infra": True,
    # Deploy CDK bridge UI.
    "deploy_cdk_bridge_ui": False,
    # Deploy the agglayer.
    "deploy_agglayer": True,
    # After deploying OP Stack, upgrade it to OP Succinct.
    # Even mock-verifier deployments require an actual SPN network key.
    "deploy_op_succinct": False,
    # Deploy contracts on L2 (as well as fund accounts).
    "deploy_l2_contracts": False,
    # Deploy aggkit node in parallel to cdk node.
    "deploy_aggkit_node": False,
}

DEFAULT_PORTS = {
    # agglayer-node
    "agglayer_grpc_port": 4443,
    "agglayer_readrpc_port": 4444,
    "agglayer_admin_port": 4446,
    "agglayer_metrics_port": 9092,
    # agglayer-prover
    "agglayer_prover_port": 4445,
    "agglayer_prover_metrics_port": 9093,
    # aggkit-prover
    "aggkit_prover_grpc_port": 4446,
    "aggkit_prover_metrics_port": 9093,
    "aggkit_pprof_port": 6060,
    "prometheus_port": 9091,
    "zkevm_aggregator_port": 50081,
    "zkevm_bridge_grpc_port": 9090,
    "zkevm_bridge_rpc_port": 8080,
    "zkevm_bridge_ui_port": 80,
    "zkevm_bridge_metrics_port": 8090,
    "zkevm_dac_port": 8484,
    "zkevm_data_streamer_port": 6900,
    "zkevm_executor_port": 50071,
    "zkevm_hash_db_port": 50061,
    "zkevm_pool_manager_port": 8545,
    "zkevm_pprof_port": 6060,
    "zkevm_rpc_http_port": 8123,
    "zkevm_rpc_ws_port": 8133,
    "cdk_node_rpc_port": 5576,
    "aggkit_node_rest_api_port": 5577,
    "aggsender_validator_grpc_port": 5578,
    "blockscout_frontend_port": 3000,
    "anvil_port": 8545,
    "mitm_port": 8234,
    "op_succinct_proposer_metrics_port": 8080,
    "op_succinct_proposer_grpc_port": 50051,
    "op_proposer_port": 8560,
}

DEFAULT_STATIC_PORTS = {
    "static_ports": {
        ## L1 static ports (50000-50999).
        "l1_el_start_port": 50000,
        "l1_cl_start_port": 50010,
        "l1_vc_start_port": 50020,
        "l1_additional_services_start_port": 50100,
        ## L2 static ports (51000-51999).
        # Agglayer (51000-51099).
        "agglayer_start_port": 51000,
        "agglayer_prover_start_port": 51010,
        # CDK node (51100-51199).
        "cdk_node_start_port": 51100,
        # Bridge services (51200-51299).
        "zkevm_bridge_service_start_port": 51200,
        "zkevm_bridge_ui_start_port": 51210,
        "reverse_proxy_start_port": 51220,
        # Databases (51300-51399).
        "database_start_port": 51300,
        "pless_database_start_port": 51310,
        # Pool manager (51400-51499).
        "zkevm_pool_manager_start_port": 51400,
        # DAC (51500-51599).
        "zkevm_dac_start_port": 51500,
        # ZkEVM Provers (51600-51699).
        "zkevm_prover_start_port": 51600,
        "zkevm_executor_start_port": 51610,
        "zkevm_stateless_executor_start_port": 51620,
        # CDK erigon (51700-51799).
        "cdk_erigon_sequencer_start_port": 51700,
        "cdk_erigon_rpc_start_port": 51710,
        # L2 additional services (52000-52999).
        "arpeggio_start_port": 52000,
        "blutgang_start_port": 52010,
        "erpc_start_port": 52020,
        "panoptichain_start_port": 52030,
        "status_checker_start_port": 52040,
    }
}

# Addresses and private keys of the different components.
# They have been generated using the following command:
# polycli wallet inspect --mnemonic 'lab code glass agree maid neutral vessel horror deny frequent favorite soft gate galaxy proof vintage once figure diary virtual scissors marble shrug drop' --addresses 7 | tee keys.txt | jq -r '.Addresses[] | [.ETHAddress, .HexPrivateKey] | @tsv' | awk 'BEGIN{split("sequencer,aggregator,admin,dac,aggoracle,sovereignadmin,claimsponsor",roles,",")} {print "# " roles[NR] "\n\"l2_" roles[NR] "_address\": \"" $1 "\","; print "\"l2_" roles[NR] "_private_key\": \"0x" $2 "\",\n"}'
DEFAULT_ACCOUNTS = {
    # sequencer
    "l2_sequencer_address": "0x5b06837A43bdC3dD9F114558DAf4B26ed49842Ed",
    "l2_sequencer_private_key": "0x183c492d0ba156041a7f31a1b188958a7a22eebadca741a7fe64436092dc3181",
    # aggregator
    "l2_aggregator_address": "0xCae5b68Ff783594bDe1b93cdE627c741722c4D4d",
    "l2_aggregator_private_key": "0x2857ca0e7748448f3a50469f7ffe55cde7299d5696aedd72cfe18a06fb856970",
    # admin
    "l2_admin_address": "0xE34aaF64b29273B7D567FCFc40544c014EEe9970",
    "l2_admin_private_key": "0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625",
    # dac
    "l2_dac_address": "0x5951F5b2604c9B42E478d5e2B2437F44073eF9A6",
    "l2_dac_private_key": "0x85d836ee6ea6f48bae27b31535e6fc2eefe056f2276b9353aafb294277d8159b",
    # aggoracle
    "l2_aggoracle_address": "0x0b68058E5b2592b1f472AdFe106305295A332A7C",
    "l2_aggoracle_private_key": "0x6d1d3ef5765cf34176d42276edd7a479ed5dc8dbf35182dfdb12e8aafe0a4919",
    # sovereignadmin
    "l2_sovereignadmin_address": "0xc653eCD4AC5153a3700Fb13442Bcf00A691cca16",
    "l2_sovereignadmin_private_key": "0xa574853f4757bfdcbb59b03635324463750b27e16df897f3d00dc6bef2997ae0",
    # claimsponsor
    "l2_claimsponsor_address": "0x635243A11B41072264Df6c9186e3f473402F94e9",
    "l2_claimsponsor_private_key": "0x986b325f6f855236b0b04582a19fe0301eeecb343d0f660c61805299dbf250eb",
}

LEGACY_DEFAULT_ACCOUNTS = {"zkevm_{}".format(k): v for k, v in DEFAULT_ACCOUNTS.items()}

DEFAULT_L1_ARGS = {
    # The L1 engine to use, either "geth" or "anvil".
    "l1_engine": "geth",
    # The L1 network identifier.
    "l1_chain_id": 271828,
    # Custom L1 genesis
    "l1_custom_genesis": False,
    # This mnemonic will:
    # a) be used to create keystores for all the types of validators that we have, and
    # b) be used to generate a CL genesis.ssz that has the children validator keys already
    # preregistered as validators
    "l1_preallocated_mnemonic": "giant issue aisle success illegal bike spike question tent bar rely arctic volcano long crawl hungry vocal artwork sniff fantasy very lucky have athlete",
    # cast wallet private-key --mnemonic $l1_preallocated_mnemonic
    "l1_preallocated_private_key": "0xbcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31",
    # The L1 HTTP RPC endpoint.
    "l1_rpc_url": "http://el-1-geth-lighthouse:8545",
    # The L1 WS RPC endpoint.
    "l1_ws_url": "ws://el-1-geth-lighthouse:8546",
    # The L1 consensus layer RPC endpoint.
    "l1_beacon_url": "http://cl-1-lighthouse-geth:4000",
    # The additional services to spin up.
    # Default: []
    # Options:
    #   - assertoor
    #   - broadcaster
    #   - tx_spammer
    #   - bridge_spammer
    #   - blob_spammer
    #   - custom_flood
    #   - goomy_blob
    #   - el_forkmon
    #   - beacon_metrics_gazer
    #   - dora
    #   - full_beaconchain_explorer
    #   - prometheus_grafana
    #   - blobscan
    #   - dugtrio
    #   - blutgang
    #   - forky
    #   - apache
    #   - tracoor
    # Check the ethereum-package for more details: https://github.com/ethpandaops/ethereum-package
    "l1_additional_services": [],
    # Preset for the network.
    # Default: "mainnet"
    # Options:
    #   - mainnet
    #   - minimal
    # "minimal" preset will spin up a network with minimal preset. This is useful for rapid testing and development.
    # 192 seconds to get to finalized epoch vs 1536 seconds with mainnet defaults
    # Please note that minimal preset requires alternative client images.
    "l1_preset": "minimal",
    # Number of seconds per slot on the Beacon chain
    # Default: 12
    "l1_seconds_per_slot": 2,
    # The amount of ETH sent to the admin, sequence, aggregator, sequencer and other chosen addresses.
    "l1_funding_amount": "1000000ether",
    # Default: 2
    "l1_participants_count": 1,
    # Whether to deploy https://github.com/AggLayer/lxly-bridge-and-call
    "l1_deploy_lxly_bridge_and_call": True,
    # Anvil: l1_anvil_slots_in_epoch will set the gap of blocks finalized vs safe vs latest
    #   l1_anvil_block_time * l1_anvil_slots_in_epoch -> total seconds to transition a block from latest to safe
    # l1_anvil_block_time: seconds per block
    "l1_anvil_block_time": 1,
    # l1_anvil_slots_in_epoch: number of slots in an epoch
    "l1_anvil_slots_in_epoch": 1,
    # Set this to true if the L1 contracts for the rollup are already
    # deployed. This also means that you'll need some way to run
    # recovery from outside of kurtosis
    # TODO at some point it would be nice if erigon could recover itself, but this is not going to be easy if there's a DAC
    "use_previously_deployed_contracts": False,
    "erigon_datadir_archive": None,
    "anvil_state_file": None,
    "mitm_proxied_components": {
        "agglayer": False,
        "aggkit": False,
        "bridge": False,
        "dac": False,
        "erigon-sequencer": False,
        "erigon-rpc": False,
        "cdk-node": False,
    },
}

DEFAULT_L2_ARGS = {
    # The number of accounts to fund on L2. The accounts will be derived from:
    # polycli wallet inspect --mnemonic '{{.l1_preallocated_mnemonic}}'
    "l2_accounts_to_fund": 10,
    # The amount of ETH sent to each of the prefunded l2 accounts.
    "l2_funding_amount": "100ether",
    # Whether to deploy https://github.com/Arachnid/deterministic-deployment-proxy.
    # Not deploying this will may cause errors or short circuit other contract
    # deployments.
    "l2_deploy_deterministic_deployment_proxy": True,
    # Whether to deploy https://github.com/AggLayer/lxly-bridge-and-call
    "l2_deploy_lxly_bridge_and_call": True,
    # This is used by erigon for naming the config files
    "chain_name": "kurtosis",
    # Config name for OP stack rollup
    "sovereign_chain_name": "op-sovereign",
}

DEFAULT_ROLLUP_ARGS = {
    # The keystore password.
    "l2_keystore_password": "pSnv6Dh5s9ahuzGzH9RoCDrKAMddaX3m",
    # The rollup network identifier.
    "zkevm_rollup_chain_id": 2151908,
    # The unique identifier for the rollup within the RollupManager contract.
    # This setting sets the rollup as the first rollup.
    "zkevm_rollup_id": 1,
    # By default a mock verifier is deployed.
    # Change to true to deploy a real verifier which will require a real prover.
    # Note: This will require a lot of memory to run!
    "zkevm_use_real_verifier": False,
    # This flag will enable a stateless executor to verify the execution of the batches.
    # Set to true to run erigon as the sequencer.
    "erigon_strict_mode": True,
    # Set to true to use an L1 ERC20 contract as the gas token on the rollup.
    # The address of the gas token will be determined by the value of `gas_token_address`.
    "gas_token_enabled": False,
    # The address of the L1 ERC20 contract that will be used as the gas token on the rollup.
    # If the address is empty, a contract will be deployed automatically.
    "gas_token_address": constants.ZERO_ADDRESS,
    # The gas token origin network, to be used in BridgeL2SovereignChain.sol
    "gas_token_network": 0,
    # The sovereign WETH address, to be used in BridgeL2SovereignChain.sol
    "sovereign_weth_address": constants.ZERO_ADDRESS,
    # Flag to indicate if the wrapped ETH is not mintable, to be used in BridgeL2SovereignChain.sol
    "sovereign_weth_address_not_mintable": False,
    # Set to true to use Kurtosis dynamic ports (default) and set to false to use static ports.
    # You can either use the default static ports defined in this file or specify your custom static
    # ports.
    #
    # By default, Kurtosis binds the ports of enclave services to ephemeral or dynamic ports on the
    # host machine. To quote the Kurtosis documentation: "these ephemeral ports are called the
    # "public ports" of the container because they allow the container to be accessed outside the
    # Docker/Kubernetes cluster".
    # https://docs.kurtosis.com/advanced-concepts/public-and-private-ips-and-ports/
    "use_dynamic_ports": True,
    # Set this to true to disable all special logics in hermez and only enable bridge update in pre-block execution
    # https://hackmd.io/@4cbvqzFdRBSWMHNeI8Wbwg/r1hKHp_S0
    "enable_normalcy": False,
    # If the agglayer/aggkit-prover is going to use the network
    # prover, we'll need to provide an API Key Replace with a valid
    # SP1 key to use the SP1 Prover Network.
    "sp1_prover_key": "0xbcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31",
    # If we're setting an sp1 key, we might want to specify a specific RPC url as well
    "agglayer_prover_network_url": "https://rpc.production.succinct.xyz",
    # The type of primary prover to use in agglayer-prover. Note: if mock-prover is selected,
    # agglayer-node will also be configured with a mock verifier
    "agglayer_prover_primary_prover": "mock-prover",
    # The URL where the agglayer can be reached for gRPC
    "agglayer_grpc_url": "http://agglayer:"
    + str(DEFAULT_PORTS.get("agglayer_grpc_port")),
    # The URL where the agglayer can be reached for ReadRPC
    "agglayer_readrpc_url": "http://agglayer:"
    + str(DEFAULT_PORTS.get("agglayer_readrpc_port")),
    # The type of primary prover to use in aggkit-prover.
    "aggkit_prover_primary_prover": "mock-prover",
    # The URL where the aggkit-prover can be reached for gRPC
    "aggkit_prover_grpc_url_prefix": "aggkit-prover",
    # Enable aggkit pprof profiling
    "aggkit_pprof_enabled": True,
    # This is a path where the cdk-node will write data
    # https://github.com/0xPolygon/cdk/blob/d0e76a3d1361158aa24135f25d37ecc4af959755/config/default.go#L50
    "zkevm_path_rw_data": "/tmp",
    # OP Stack EL RPC URL. Will be dynamically updated by args_sanity_check() function.
    "op_el_rpc_url": "http://op-el-1-op-geth-op-node-001:8545",
    # OP Stack CL Node URL. Will be dynamically updated by args_sanity_check() function.
    "op_cl_rpc_url": "http://op-cl-1-op-node-op-geth-001:8547",
    # If the OP Succinct will use the Network Prover or CPU(Mock) Prover
    # true = mock
    # false = network
    "op_succinct_mock": False,
    "aggkit_components": "aggsender,aggoracle",
    # Toggle to enable the claimsponsor on the aggkit node.
    # Note: aggkit will only start the claimsponsor if the bridge is also enabled.
    "enable_aggkit_claim_sponsor": False,
    "use_agg_oracle_committee": False,
    "agg_oracle_committee_quorum": 0,
    # The below parameter will be automatically populated based on "agg_oracle_committee_total_members"
    # "aggOracleCommittee": ["{{ .l2_aggoracle_address }}", "{{ .l2_admin_address }}", "{{ .l2_sovereignadmin_address }}"],
    # By default, the L2 mnemonic 'lab code glass agree maid neutral vessel horror deny frequent favorite soft gate galaxy proof vintage once figure diary virtual scissors marble shrug drop'
    # which is being used to generate the accounts in DEFAULT_ACCOUNTS will also be used to generate the committee members.
    "agg_oracle_committee_total_members": 1,
    "use_agg_sender_validator": False,
    # The below parameter will be used for aggsender multisig to have "agg_sender_validator_total_number" aggsender validators.
    "agg_sender_validator_total_number": 0,
    "agg_sender_multisig_threshold": 1,
}

DEFAULT_ADDITIONAL_SERVICES_PARAMS = {
    "blockscout_params": {
        "blockscout_public_port": DEFAULT_PORTS.get("blockscout_frontend_port"),
    },
}

DEFAULT_ARGS = (
    {
        # Suffix appended to service names.
        # Note: It should be a string.
        "deployment_suffix": "-001",
        # The global log level that all components of the stack should log at.
        # Valid values are "error", "warn", "info", "debug", and "trace".
        "log_level": constants.LOG_LEVEL.info,
        # The log format that all components of the stack should use.
        # Valid values are "json" and "pretty".
        "log_format": constants.LOG_FORMAT.pretty,
        # The type of the sequencer to deploy.
        # Options:
        # - 'cdk-erigon': Use the cdk-erigon sequencer (https://github.com/0xPolygonHermez/cdk-erigon).
        # - 'op-geth': Use the OP stack sequencer (https://github.com/ethereum-optimism/op-geth).
        "sequencer_type": constants.SEQUENCER_TYPE.op_geth,
        # The type of consensus contract to use.
        # Consensus Options:
        # - 'rollup': Transaction data is stored on-chain on L1.
        # - 'cdk_validium': Transaction data is stored off-chain using the CDK DA layer and a DAC.
        # - 'pessimistic': deploy with pessimistic consensus
        # Aggchain Consensus Options:
        # - 'ecdsa_multisig': Aggchain using an ecdsa_multisig signature with CONSENSUS_TYPE = 1.
        # - 'fep': Generic aggchain using Full Execution Proofs that relies on op-succinct stack.
        "consensus_contract_type": constants.CONSENSUS_TYPE.ecdsa_multisig,
        # Additional services to run alongside the network.
        # Options:
        # - agglogger
        # - arpeggio
        # - assertoor
        # - blockscout
        # - blutgang
        # - bridge_spammer
        # - erpc
        # - observability
        # - rpc_fuzzer
        # - status_checker
        # - test_runner
        # - tx_spammer
        "additional_services": [
            constants.ADDITIONAL_SERVICES.agglogger,
            constants.ADDITIONAL_SERVICES.bridge_spammer,
            constants.ADDITIONAL_SERVICES.test_runner,
            constants.ADDITIONAL_SERVICES.agglayer_dashboard,
        ],
        # Only relevant when deploying to an external L1.
        "polygon_zkevm_explorer": "https://explorer.private/",
        "l1_explorer_url": "https://sepolia.etherscan.io/",
    }
    | constants.DEFAULT_IMAGES
    | DEFAULT_PORTS
    | DEFAULT_ACCOUNTS
    | LEGACY_DEFAULT_ACCOUNTS
    | DEFAULT_L1_ARGS
    | DEFAULT_ROLLUP_ARGS
    | DEFAULT_L2_ARGS
    | DEFAULT_ADDITIONAL_SERVICES_PARAMS
)

VALID_ADDITIONAL_SERVICES = [
    getattr(constants.ADDITIONAL_SERVICES, field)
    for field in dir(constants.ADDITIONAL_SERVICES)
]

VALID_CONSENSUS_TYPES = [
    constants.CONSENSUS_TYPE.rollup,
    constants.CONSENSUS_TYPE.cdk_validium,
    constants.CONSENSUS_TYPE.pessimistic,
    constants.CONSENSUS_TYPE.fep,
    constants.CONSENSUS_TYPE.ecdsa_multisig,
]


def parse_args(plan, user_args):
    # Merge the provided args with defaults.
    deployment_stages = DEFAULT_DEPLOYMENT_STAGES | user_args.get(
        "deployment_stages", {}
    )
    args = DEFAULT_ARGS | user_args.get("args", {})
    op_input_args = user_args.get("optimism_package", {})

    # Change some params if anvil set to make it work
    # As it changes L1 config it needs to be run before other functions/checks
    set_anvil_args(plan, args, user_args)

    # Sanity check step for incompatible parameters
    args_sanity_check(plan, deployment_stages, args, user_args)

    consensus_contract_type = args.get("consensus_contract_type")
    validate_consensus_type(consensus_contract_type)

    # Setting mitm for each element set to true on mitm dict
    mitm_rpc_url = (
        "http://mitm"
        + args["deployment_suffix"]
        + ":"
        + str(DEFAULT_PORTS.get("mitm_port"))
    )
    args["mitm_rpc_url"] = {
        k: mitm_rpc_url for k, v in args.get("mitm_proxied_components", {}).items() if v
    }

    # Validation step.
    log_level = args.get("log_level")
    validate_log_level(log_level)

    log_format = args.get("log_format")
    validate_log_format(log_format)
    environment = log_format_to_environment(log_format)
    args["environment"] = environment

    validate_additional_services(args.get("additional_services", []))

    # Determine fork id from the agglayer contracts image tag.
    sequencer_type = args.get("sequencer_type")
    zkevm_prover_image = args.get("zkevm_prover_image")
    (fork_id, fork_name) = get_fork_id(
        consensus_contract_type, sequencer_type, zkevm_prover_image
    )

    # Determine sequencer and l2 rpc names.
    if (
        sequencer_type not in constants.L2_SEQUENCER_MAPPING
        or sequencer_type not in constants.L2_RPC_MAPPING
    ):
        fail(
            "Unsupported sequencer type: '{}', please use one of: '{}'".format(
                sequencer_type, list(constants.L2_SEQUENCER_MAPPING.keys())
            )
        )
    sequencer_name = constants.L2_SEQUENCER_MAPPING[sequencer_type]
    l2_rpc_name = constants.L2_RPC_MAPPING[sequencer_type]

    # Determine static ports, if specified.
    if not args.get("use_dynamic_ports", True):
        plan.print("Using static ports.")
        args = DEFAULT_STATIC_PORTS | args

    # When using assertoor to test L1 scenarios, l1_preset should be mainnet for deposits and withdrawls to work.
    if "assertoor" in args["l1_additional_services"]:
        plan.print(
            "Assertoor is detected - changing l1_preset to mainnet and l1_participant_count to 2"
        )
        args["l1_preset"] = "mainnet"
        args["l1_participant_count"] = 2

    # Remove deployment stages from the args struct.
    # This prevents updating already deployed services when updating the deployment stages.
    if "deployment_stages" in args:
        args.pop("deployment_stages")

    # The private key for sp1 is expected to not have the 0x prefix
    if args.get("sp1_prover_key") and args["sp1_prover_key"].startswith("0x"):
        args["sp1_prover_key"] = args["sp1_prover_key"][2:]

    args = args | {
        "l2_rpc_name": l2_rpc_name,
        "sequencer_name": sequencer_name,
        "zkevm_rollup_fork_id": fork_id,
        "zkevm_rollup_fork_name": fork_name,
        "deploy_agglayer": deployment_stages.get(
            "deploy_agglayer", False
        ),  # hacky but works fine for now.
    }

    # Parse and sanity check op args
    op_args = op_input_parser.parse_args(plan, args, op_input_args)

    # Sort dictionaries for debug purposes.
    sorted_deployment_stages = dict.sort_dict_by_values(deployment_stages)
    sorted_args = dict.sort_dict_by_values(args)
    return (sorted_deployment_stages, sorted_args, op_args)


def validate_log_level(log_level):
    VALID_LOG_LEVELS = [
        constants.LOG_LEVEL.error,
        constants.LOG_LEVEL.warn,
        constants.LOG_LEVEL.info,
        constants.LOG_LEVEL.debug,
        constants.LOG_LEVEL.trace,
    ]
    if log_level not in VALID_LOG_LEVELS:
        fail(
            "Unsupported log level: '{}', please use one of: '{}'".format(
                log_level, VALID_LOG_LEVELS
            )
        )


def validate_log_format(log_format):
    VALID_LOG_FORMATS = [
        constants.LOG_FORMAT.json,
        constants.LOG_FORMAT.pretty,
    ]
    if log_format not in VALID_LOG_FORMATS:
        fail(
            "Unsupported log format: '{}', please use one of: '{}'".format(
                log_format, VALID_LOG_FORMATS
            )
        )


def log_format_to_environment(log_format):
    mapping = {
        constants.LOG_FORMAT.json: "production",
        constants.LOG_FORMAT.pretty: "development",
    }
    environment = mapping.get(log_format)
    if not environment:
        fail("Unknown log format: {}".format(log_format))
    return environment


def validate_additional_services(additional_services):
    for svc in additional_services:
        if svc not in VALID_ADDITIONAL_SERVICES:
            fail(
                "Unsupported additional service: '{}', please use one of: '{}'".format(
                    svc, VALID_ADDITIONAL_SERVICES
                )
            )


def get_fork_id(consensus_contract_type, sequencer_type, zkevm_prover_image):
    # If aggchain consensus is being used or optimism rollup is being deployed, return zero.
    if (
        consensus_contract_type
        in [
            constants.CONSENSUS_TYPE.ecdsa_multisig,
            constants.CONSENSUS_TYPE.fep,
        ]
        or sequencer_type == constants.SEQUENCER_TYPE.op_geth
    ):
        return (0, "aggchain")

    # Otherwise, parse the fork id from the zkevm-prover image tag.
    result = zkevm_prover_image.split("-fork.")
    if len(result) != 2:
        fail(
            "The zkevm prover image tag '{}' does not follow the standard v<SEMVER>-rc.<RC_NUMBER>-fork.<FORK_ID>".format(
                zkevm_prover_image
            )
        )

    fork_id = int(result[1])
    if fork_id not in constants.FORK_ID_TO_NAME:
        fail("The fork id '{}' is not supported by Kurtosis CDK".format(fork_id))

    fork_name = constants.FORK_ID_TO_NAME[fork_id]
    return (fork_id, fork_name)


def set_anvil_args(plan, args, user_args):
    if args["anvil_state_file"] != None:
        if user_args.get("args", {}).get("l1_engine") != "anvil":
            args["l1_engine"] = "anvil"
            plan.print("Anvil state file detected - changing l1_engine to anvil")

    if args["l1_engine"] == "anvil":
        # We override only is user did not provide explicit values
        if not user_args.get("args", {}).get("l1_rpc_url"):
            args["l1_rpc_url"] = (
                "http://anvil"
                + args["deployment_suffix"]
                + ":"
                + str(DEFAULT_PORTS.get("anvil_port"))
            )
        if not user_args.get("args", {}).get("l1_ws_url"):
            args["l1_ws_url"] = (
                "ws://anvil"
                + args["deployment_suffix"]
                + ":"
                + str(DEFAULT_PORTS.get("anvil_port"))
            )
        if not user_args.get("args", {}).get("l1_beacon_url"):
            args["l1_beacon_url"] = (
                "http://anvil"
                + args["deployment_suffix"]
                + ":"
                + str(DEFAULT_PORTS.get("anvil_port"))
            )


# Helper function to compact together checks for incompatible parameters in input_parser.star
def args_sanity_check(plan, deployment_stages, args, user_args):
    # Disable CDK-Erigon and AggOracle Committee combination deployments
    if (
        args["sequencer_type"] == constants.SEQUENCER_TYPE.cdk_erigon
        and args["use_agg_oracle_committee"] == True
    ):
        fail("AggOracle Committee unsupported for CDK-Erigon")

    # If AggOracle Committee is enabled, do sanity checks
    if args["use_agg_oracle_committee"] == True:
        # Check quorum is non-zero
        if args["agg_oracle_committee_quorum"] < 1:
            fail(
                "AggOracle Committee is enabled. Quorum ('{}') needs to be greater than 1.".format(
                    args["agg_oracle_committee_quorum"]
                )
            )
        # Check total committee members >= quorum
        if (
            args["agg_oracle_committee_quorum"]
            > args["agg_oracle_committee_total_members"]
        ):
            fail(
                "AggOracle Committee is enabled. Total committee members ('{}') needs to be greater than quorum ('{}').".format(
                    args["agg_oracle_committee_total_members"],
                    args["agg_oracle_committee_quorum"],
                )
            )

    # If AggOracle Committee is disabled, do sanity checks
    if args["use_agg_oracle_committee"] == False:
        if args["agg_oracle_committee_quorum"] != 0:
            fail(
                "AggOracle Committee is disabled. Quorum ('{}') needs to be 0.".format(
                    args["agg_oracle_committee_quorum"]
                )
            )
        if args["agg_oracle_committee_total_members"] != 1:
            fail(
                "AggOracle Committee is disabled. Total committee members ('{}') needs to be 1.".format(
                    args["agg_oracle_committee_total_members"]
                )
            )

    # If Aggsender Validator is disabled, do sanity checks
    if args["use_agg_sender_validator"] == False:
        if args["agg_sender_validator_total_number"] != 0:
            fail(
                "Aggsender Validator is disabled. agg_sender_validator_total_number ('{}') needs to be 0.".format(
                    args["agg_sender_validator_total_number"]
                )
            )

    # If Aggsender Validator is enabled, do sanity checks
    if args["use_agg_sender_validator"] == True:
        # Check agg_sender_validator_total_number >= 1
        if args["agg_sender_validator_total_number"] < 1:
            fail(
                "Aggsender Validator is enabled. agg_sender_validator_total_number ('{}') needs to be greater than 1.".format(
                    args["agg_sender_validator_total_number"]
                )
            )
        # Check agg_sender_multisig_threshold not greater than agg_sender_validator_total_number
        if (
            args["agg_sender_multisig_threshold"]
            > args["agg_sender_validator_total_number"]
        ):
            fail(
                "agg_sender_multisig_threshold ('{}') must be equal to or smaller than agg_sender_validator_total_number ('{}').".format(
                    args["agg_sender_multisig_threshold"],
                    args["agg_sender_validator_total_number"],
                )
            )

    # Check agg_sender_multisig_threshold is never below 1
    if args["agg_sender_multisig_threshold"] < 1:
        fail(
            "Aggsender multisig threshold ('{}') cannot be below 1.".format(
                args["agg_sender_multisig_threshold"]
            )
        )

    # Fix the op stack el rpc urls according to the deployment_suffix.
    if (
        args["op_el_rpc_url"]
        != "http://op-el-1-op-geth-op-node" + args["deployment_suffix"] + ":8545"
        and args["sequencer_type"] == constants.SEQUENCER_TYPE.op_geth
    ):
        plan.print(
            "op_el_rpc_url is set to '{}', changing to 'http://op-el-1-op-geth-op-node{}:8545'".format(
                args["op_el_rpc_url"], args["deployment_suffix"]
            )
        )
        args["op_el_rpc_url"] = (
            "http://op-el-1-op-geth-op-node" + args["deployment_suffix"] + ":8545"
        )
    # Fix the op stack cl rpc urls according to the deployment_suffix.
    if (
        args["op_cl_rpc_url"]
        != "http://op-cl-1-op-node-op-geth" + args["deployment_suffix"] + ":8547"
        and args["sequencer_type"] == constants.SEQUENCER_TYPE.op_geth
    ):
        plan.print(
            "op_cl_rpc_url is set to '{}', changing to 'http://op-cl-1-op-node-op-geth{}:8547'".format(
                args["op_cl_rpc_url"], args["deployment_suffix"]
            )
        )
        args["op_cl_rpc_url"] = (
            "http://op-cl-1-op-node-op-geth" + args["deployment_suffix"] + ":8547"
        )

    # Unsupported L1 engine check
    if args["l1_engine"] not in constants.L1_ENGINES:
        fail(
            "Unsupported L1 engine: '{}', please use one of {}".format(
                args["l1_engine"], constants.L1_ENGINES
            )
        )

    # CDK Erigon normalcy and strict mode check
    if args["enable_normalcy"] and args["erigon_strict_mode"]:
        fail("normalcy and strict mode cannot be enabled together")

    # OP rollup deploy_optimistic_rollup and consensus_contract_type check
    if args["sequencer_type"] == constants.SEQUENCER_TYPE.op_geth:
        if args["consensus_contract_type"] != constants.CONSENSUS_TYPE.pessimistic:
            if (
                args["consensus_contract_type"] != "fep"
                and args["consensus_contract_type"] != "ecdsa_multisig"
            ):
                plan.print(
                    "Current consensus_contract_type is '{}', changing to pessimistic for OP deployments.".format(
                        args["consensus_contract_type"]
                    )
                )
                # TODO: should this be AggchainFEP instead?
                args["consensus_contract_type"] = constants.CONSENSUS_TYPE.pessimistic

    # If OP-Succinct is enabled, OP-Rollup must be enabled
    if deployment_stages.get("deploy_op_succinct", False):
        if args["sequencer_type"] != constants.SEQUENCER_TYPE.op_geth:
            fail(
                "OP Succinct requires OP Rollup to be enabled. Change the sequencer_type parameter to 'op-geth'."
            )
        if args["sp1_prover_key"] == None or args["sp1_prover_key"] == "":
            fail("OP Succinct requires a valid SPN key. Change the sp1_prover_key")

    # FIXME - I've removed some code here that was doing some logic to
    # update the vkeys depending on the consensus. We either need to
    # have different vkeys depending on the context (e.g. if we're
    # deploying the rollpu manager it needs to be set
    # (VKeyCannotBeZero() 0x6745305e), but if we're creating an
    # aggchainFEP it must not be set) or we can hard code to be
    # 0x000...000 in the situations where we know it must be zero

    # Blockscout additional service is only supported on L2
    if constants.ADDITIONAL_SERVICES.blockscout in args.get(
        "l1_additional_services", []
    ):
        fail("Blockscout is only supported to target L2 network.")


def validate_consensus_type(consensus_type):
    if consensus_type not in VALID_CONSENSUS_TYPES:
        fail(
            'Invalid consensus type: "{}". Allowed value(s): {}.'.format(
                consensus_type, VALID_CONSENSUS_TYPES
            )
        )
