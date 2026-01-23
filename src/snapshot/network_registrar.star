"""
Network registration module for snapshot mode.

This module handles registration of multiple networks in a single Kurtosis run.
It reuses existing network registration logic from sovereign_contracts_package.
"""

constants = import_module("../package_io/constants.star")
sovereign_contracts_package = import_module("../contracts/sovereign.star")
agglayer_contracts_package = "./src/contracts/agglayer.star"
contracts_util = import_module("../contracts/util.star")
cdk_node = import_module("../chain/cdk-erigon/cdk_node.star")
aggkit_package = import_module("../chain/shared/aggkit.star")
zkevm_bridge_service = import_module("../chain/shared/zkevm_bridge_service.star")
databases = import_module("../chain/shared/databases.star")
ports_package = import_module("../chain/shared/ports.star")


def register_networks(plan, args, contract_setup_addresses, snapshot_networks, deployment_stages, op_stack_args):
    """
    Register multiple networks in a single Kurtosis run.
    
    Args:
        plan: Kurtosis plan object
        args: Base arguments dictionary
        contract_setup_addresses: Contract addresses from agglayer deployment
        snapshot_networks: List of network configurations to register
        deployment_stages: Deployment stages configuration
        op_stack_args: OP Stack arguments for op-geth networks
    
    Returns:
        List of network metadata structures
    """
    # Input validation
    if plan == None:
        fail("plan is required")
    if args == None:
        fail("args is required")
    if snapshot_networks == None:
        fail("snapshot_networks is required")
    if not isinstance(snapshot_networks, list):
        fail("snapshot_networks must be a list")
    if len(snapshot_networks) == 0:
        fail("snapshot_networks cannot be empty")
    
    plan.print("Registering {} networks for snapshot...".format(len(snapshot_networks)))
    
    # Track unique values for validation
    seen_deployment_suffixes = {}
    seen_chain_ids = {}
    seen_network_ids = {}
    
    networks_metadata = []
    
    for i, network_config in enumerate(snapshot_networks):
        plan.print("Registering network {} of {}: {}".format(
            i + 1, len(snapshot_networks), network_config.get("deployment_suffix", "")
        ))
        
        # Validate network config
        network_sequencer_type = network_config.get("sequencer_type")
        if not network_sequencer_type:
            fail("Network {}: sequencer_type is required".format(i + 1))
        if network_sequencer_type != constants.SEQUENCER_TYPE.op_geth and network_sequencer_type != constants.SEQUENCER_TYPE.cdk_erigon:
            fail("Network {}: Invalid sequencer_type '{}' (must be '{}' or '{}')".format(
                i + 1, network_sequencer_type, constants.SEQUENCER_TYPE.op_geth, constants.SEQUENCER_TYPE.cdk_erigon
            ))
        
        network_consensus_type = network_config.get("consensus_type")
        if not network_consensus_type:
            fail("Network {}: consensus_type is required".format(i + 1))
        
        # Validate sequencer/consensus combination
        valid_combinations = {
            constants.SEQUENCER_TYPE.cdk_erigon: ["rollup", "cdk-validium", "pessimistic", "ecdsa-multisig"],
            constants.SEQUENCER_TYPE.op_geth: ["rollup", "pessimistic", "ecdsa-multisig", "fep"],
        }
        if network_consensus_type not in valid_combinations.get(network_sequencer_type, []):
            fail("Network {}: Invalid consensus_type '{}' for sequencer_type '{}'".format(
                i + 1, network_consensus_type, network_sequencer_type
            ))
        
        # Validate required fields
        deployment_suffix = network_config.get("deployment_suffix", "")
        l2_chain_id = network_config.get("l2_chain_id", 0)
        network_id = network_config.get("network_id", 0)
        
        if l2_chain_id <= 0:
            fail("Network {}: l2_chain_id must be > 0".format(i + 1))
        if network_id <= 0:
            fail("Network {}: network_id must be > 0".format(i + 1))
        
        # Check for duplicates
        if deployment_suffix in seen_deployment_suffixes:
            fail("Network {}: Duplicate deployment_suffix '{}' (already used by network {})".format(
                i + 1, deployment_suffix, seen_deployment_suffixes[deployment_suffix]
            ))
        if l2_chain_id in seen_chain_ids:
            fail("Network {}: Duplicate l2_chain_id '{}' (already used by network {})".format(
                i + 1, l2_chain_id, seen_chain_ids[l2_chain_id]
            ))
        if network_id in seen_network_ids:
            fail("Network {}: Duplicate network_id '{}' (already used by network {})".format(
                i + 1, network_id, seen_network_ids[network_id]
            ))
        
        # Track seen values
        seen_deployment_suffixes[deployment_suffix] = i + 1
        seen_chain_ids[l2_chain_id] = i + 1
        seen_network_ids[network_id] = i + 1
        
        # Merge base args with network-specific config
        network_args = args | network_config
        
        # Update sequencer_type and consensus_type from network config
        network_args["sequencer_type"] = network_sequencer_type
        network_args["consensus_contract_type"] = network_consensus_type
        
        # Use op_stack_args for OP-Geth networks
        network_op_stack_args = op_stack_args
        
        # Register network based on sequencer type
        if network_sequencer_type == constants.SEQUENCER_TYPE.op_geth:
            network_metadata = _register_op_geth_network(
                plan, network_args, network_config, contract_setup_addresses,
                deployment_stages, network_op_stack_args
            )
            networks_metadata.append(network_metadata)
        elif network_sequencer_type == constants.SEQUENCER_TYPE.cdk_erigon:
            network_metadata = _register_cdk_erigon_network(
                plan, network_args, network_config, contract_setup_addresses,
                deployment_stages, network_op_stack_args
            )
            networks_metadata.append(network_metadata)
        else:
            fail("Unsupported sequencer type in snapshot_networks: {}".format(network_sequencer_type))
    
    plan.print("Network registration completed: {} networks registered".format(len(networks_metadata)))
    
    return networks_metadata


def _register_op_geth_network(plan, network_args, network_config, contract_setup_addresses, deployment_stages, op_stack_args):
    """Register an OP-Geth network and generate configs."""
    plan.print("Registering OP-Geth network: {}".format(network_config.get("deployment_suffix", "")))
    
    # Register sovereign contracts
    predeployed_contracts = False
    if isinstance(op_stack_args, dict) and "predeployed_contracts" in op_stack_args:
        predeployed_contracts = op_stack_args["predeployed_contracts"]
    
    sovereign_contracts_package.run(plan, network_args, predeployed_contracts)
    
    # Create sovereign predeployed genesis
    import_module(agglayer_contracts_package).create_sovereign_predeployed_genesis(plan, network_args)
    
    # Deploy OP Stack infrastructure (for config generation)
    # Note: This may start services, which is acceptable - we'll stop them later
    plan.print("Deploying OP Stack infrastructure for network: {}".format(network_config.get("deployment_suffix", "")))
    optimism_package = None
    if isinstance(op_stack_args, dict) and "source" in op_stack_args:
        optimism_package = op_stack_args["source"]
    if optimism_package:
        import_module(optimism_package).run(plan, op_stack_args)
    
    # Retrieve L1 OP contract addresses
    op_deployer_configs_artifact = plan.get_files_artifact(name="op-deployer-configs")
    
    # Fund OP Addresses on L1
    l1_op_contract_addresses = contracts_util.get_l1_op_contract_addresses(
        plan, network_args, op_deployer_configs_artifact
    )
    
    sovereign_contracts_package.fund_addresses(
        plan, network_args, l1_op_contract_addresses, network_args["l1_rpc_url"]
    )
    
    # Fund Kurtosis addresses on OP L2
    sovereign_contracts_package.fund_addresses(
        plan,
        network_args,
        contracts_util.get_l2_addresses_to_fund(network_args),
        network_args["op_el_rpc_url"],
    )
    
    # Initialize rollup
    plan.print("Initializing rollup for network: {}".format(network_config.get("deployment_suffix", "")))
    sovereign_contracts_package.init_rollup(plan, network_args, deployment_stages)
    
    # Extract Sovereign contract addresses for this network
    network_sovereign_contract_setup_addresses = (
        contracts_util.get_sovereign_contract_setup_addresses(plan, network_args)
    )
    
    # For OP-Geth, configs are generated by OP Stack package
    # We'll extract them in Step 4 (config extraction)
    return struct(
        deployment_suffix=network_config.get("deployment_suffix", ""),
        l2_chain_id=network_config.get("l2_chain_id", 0),
        network_id=network_config.get("network_id", 0),
        sequencer_type=network_args.get("sequencer_type", ""),
        consensus_type=network_config.get("consensus_type", ""),
        chain_name=network_args.get("chain_name", "kurtosis"),
        sovereign_contract_setup_addresses=network_sovereign_contract_setup_addresses,
        config_artifacts=struct(
            cdk_node_config="",
            aggkit_config="",
            bridge_config="",
            genesis_artifact="",
        ),
    )


def _register_cdk_erigon_network(plan, network_args, network_config, contract_setup_addresses, deployment_stages, op_stack_args):
    """Register a CDK-Erigon network and generate configs WITHOUT starting services."""
    plan.print("Registering CDK-Erigon network: {}".format(network_config.get("deployment_suffix", "")))
    
    # For CDK-Erigon, network registration happens during contract deployment
    # This will create genesis and chain configs for this network
    import_module(agglayer_contracts_package).run(
        plan, network_args, deployment_stages, op_stack_args
    )
    
    # Get genesis artifact for this network
    genesis_artifact = plan.store_service_files(
        name="genesis{}".format(network_args.get("deployment_suffix", "")),
        service_name="contracts" + network_args["deployment_suffix"],
        src=constants.OUTPUT_DIR + "/genesis.json",
    )
    
    # Generate config artifacts WITHOUT starting services
    config_artifacts = _generate_cdk_erigon_configs(
        plan, network_args, contract_setup_addresses, genesis_artifact
    )
    
    return struct(
        deployment_suffix=network_config.get("deployment_suffix", ""),
        l2_chain_id=network_config.get("l2_chain_id", 0),
        network_id=network_config.get("network_id", 0),
        sequencer_type=network_args.get("sequencer_type", ""),
        consensus_type=network_config.get("consensus_type", ""),
        chain_name=network_args.get("chain_name", "kurtosis"),
        sovereign_contract_setup_addresses={},
        config_artifacts=config_artifacts,
    )


def _generate_cdk_erigon_configs(plan, args, contract_setup_addresses, genesis_artifact):
    """
    Generate config artifacts for CDK-Erigon networks WITHOUT starting services.
    
    Returns:
        struct with config artifact names
    """
    config_artifacts = struct(
        cdk_node_config="",
        aggkit_config="",
        bridge_config="",
        genesis_artifact=genesis_artifact,
    )
    
    consensus_type = args.get("consensus_contract_type")
    
    # Generate CDK-Node config (for rollup and validium)
    if consensus_type in [
        constants.CONSENSUS_TYPE.rollup,
        constants.CONSENSUS_TYPE.cdk_validium,
        constants.CONSENSUS_TYPE.pessimistic,
    ]:
        config_artifacts = config_artifacts | struct(
            cdk_node_config=_generate_cdk_node_config(plan, args, contract_setup_addresses),
        )
    
    # Generate AggKit config (for pessimistic and ecdsa-multisig)
    if consensus_type in [
        constants.CONSENSUS_TYPE.pessimistic,
        constants.CONSENSUS_TYPE.ecdsa_multisig,
    ]:
        # Generate aggkit config artifact
        config_artifacts = config_artifacts | struct(
            aggkit_config=_generate_aggkit_config(plan, args, contract_setup_addresses, {}),
        )
    
    # Generate bridge config (for pessimistic and ecdsa-multisig with CDK-Erigon)
    if consensus_type in [
        constants.CONSENSUS_TYPE.pessimistic,
        constants.CONSENSUS_TYPE.ecdsa_multisig,
    ]:
        l2_rpc_url = "http://{}{}:{}".format(
            args.get("l2_rpc_name"),
            args.get("deployment_suffix"),
            ports_package.HTTP_RPC_PORT_NUMBER,
        )
        config_artifacts = config_artifacts | struct(
            bridge_config=_generate_bridge_config(plan, args, contract_setup_addresses, {}, l2_rpc_url),
        )
    
    return config_artifacts


def _generate_cdk_node_config(plan, args, contract_setup_addresses):
    """Generate CDK-Node config artifact without starting service."""
    db_configs = databases.get_db_configs(
        args.get("deployment_suffix"), args.get("sequencer_type")
    )
    agglayer_endpoint = cdk_node.get_agglayer_endpoint(plan, args)
    l2_rpc_url = "http://{}{}:{}".format(
        args.get("l2_rpc_name"),
        args.get("deployment_suffix"),
        ports_package.HTTP_RPC_PORT_NUMBER,
    )
    
    config_artifact = plan.render_templates(
        name="cdk-node-config{}".format(args.get("deployment_suffix")),
        config={
            "config.toml": struct(
                template=read_file(
                    src="../../../static_files/chain/cdk-erigon/cdk-node/config.toml"
                ),
                data=args
                | {
                    "is_validium_mode": args.get("consensus_contract_type")
                    == constants.CONSENSUS_TYPE.cdk_validium,
                    "l1_rpc_url": args["mitm_rpc_url"].get(
                        "cdk-node", args["l1_rpc_url"]
                    ),
                    "l2_rpc_url": l2_rpc_url,
                    "agglayer_endpoint": agglayer_endpoint,
                    "aggregator_port_number": cdk_node.AGGREGATOR_PORT_NUMBER,
                }
                | db_configs
                | contract_setup_addresses,
            )
        },
    )
    
    return config_artifact


def _generate_aggkit_config(plan, args, contract_setup_addresses, sovereign_contract_setup_addresses):
    """Generate AggKit config artifact without starting service."""
    db_configs = databases.get_db_configs(
        args["deployment_suffix"], args["sequencer_type"]
    )
    l2_rpc_url = "http://{}{}:{}".format(
        args.get("l2_rpc_name"),
        args.get("deployment_suffix"),
        ports_package.HTTP_RPC_PORT_NUMBER,
    )
    
    # Replicate aggkit config data building logic
    aggkit_image = args.get("aggkit_image", "")
    agglayer_endpoint = "readrpc"  # Default
    if "local" in aggkit_image:
        agglayer_endpoint = "grpc"
    else:
        # Extract version from image tag (simplified - assume >= 0.3 uses grpc)
        if ":" in aggkit_image:
            tag = aggkit_image.split(":")[-1]
            if tag != "local":
                # Try to extract version number
                tag_clean = tag.split("-")[0].replace("v", "")
                try:
                    version_parts = tag_clean.split(".")
                    if len(version_parts) >= 2:
                        major = float(version_parts[0])
                        minor = float(version_parts[1])
                        if major > 0 or (major == 0 and minor >= 3):
                            agglayer_endpoint = "grpc"
                except:
                    pass  # Default to readrpc if parsing fails
    
    aggkit_version = "0.3.0"  # Default version
    if ":" in aggkit_image:
        tag = aggkit_image.split(":")[-1]
        if tag != "local":
            aggkit_version = tag.split("-")[0].replace("v", "")
    
    config_data = (
        args
        | {
            "agglayer_endpoint": agglayer_endpoint,
            "aggkit_version": aggkit_version,
            "l2_rpc_url": l2_rpc_url,
            "aggkit_prover_grpc_port_number": 50082,  # Default aggkit prover port
        }
        | db_configs
        | contract_setup_addresses
        | sovereign_contract_setup_addresses
    )
    
    config_template = read_file(
        src="../../../static_files/chain/shared/aggkit/config.toml"
    )
    config_artifact = plan.render_templates(
        name="aggkit-config{}".format(args.get("deployment_suffix")),
        config={
            "config.toml": struct(
                template=config_template,
                data=config_data,
            )
        },
    )
    
    return config_artifact


def _generate_bridge_config(plan, args, contract_setup_addresses, sovereign_contract_setup_addresses, l2_rpc_url):
    """Generate bridge config artifact without starting service."""
    l1_rpc_url = args["mitm_rpc_url"].get("bridge", args["l1_rpc_url"])
    
    consensus_contract_type = args.get("consensus_contract_type")
    sequencer_type = args.get("sequencer_type")
    require_sovereign_chain_contract = (
        consensus_contract_type
        in [
            constants.CONSENSUS_TYPE.pessimistic,
            constants.CONSENSUS_TYPE.ecdsa_multisig,
        ]
        and sequencer_type == constants.SEQUENCER_TYPE.op_geth
    ) or consensus_contract_type == constants.CONSENSUS_TYPE.fep
    
    db_configs = databases.get_db_configs(args["deployment_suffix"], sequencer_type)
    
    config_artifact = plan.render_templates(
        name="bridge-config{}".format(args.get("deployment_suffix")),
        config={
            "bridge-config.toml": struct(
                template=read_file(
                    src="../../../static_files/chain/shared/zkevm-bridge-service/config.toml"
                ),
                data={
                    "log_level": args.get("log_level"),
                    "environment": args.get("environment"),
                    "l2_keystore_password": args["l2_keystore_password"],
                    "db": db_configs.get("bridge_db"),
                    "require_sovereign_chain_contract": require_sovereign_chain_contract,
                    "sequencer_type": sequencer_type,
                    # rpc urls
                    "l1_rpc_url": l1_rpc_url,
                    "l2_rpc_url": l2_rpc_url,
                    # ports
                    "grpc_port_number": args["zkevm_bridge_grpc_port"],
                    "rpc_port_number": args["zkevm_bridge_rpc_port"],
                    "metrics_port_number": args["zkevm_bridge_metrics_port"],
                }
                | contract_setup_addresses
                | sovereign_contract_setup_addresses,
            )
        },
    )
    
    return config_artifact
