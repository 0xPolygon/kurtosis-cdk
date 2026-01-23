"""
Config artifact extraction module for snapshot mode.

This module extracts all configuration artifacts that were generated during
network registration, including:
- Network-specific configs (cdk-node, aggkit, bridge)
- Keystores from contracts service
- Genesis and chain config artifacts from output-artifact
- Agglayer config (basic version, will be updated in post-processing)
"""

constants = import_module("../package_io/constants.star")
agglayer_package = import_module("../agglayer.star")


def extract_config_artifacts(plan, args, networks_metadata, contract_setup_addresses, deployment_stages=None):
    """
    Extract all configuration artifacts for snapshot mode.
    
    Args:
        plan: Kurtosis plan object
        args: Parsed arguments dictionary
        networks_metadata: List of network metadata structures from network_registrar
        contract_setup_addresses: Contract addresses from agglayer deployment
        deployment_stages: Deployment stages configuration (optional)
    
    Returns:
        struct with extracted artifact references and manifest
    """
    # Input validation
    if plan == None:
        fail("plan is required")
    if args == None:
        fail("args is required")
    if networks_metadata == None:
        fail("networks_metadata is required")
    if not isinstance(networks_metadata, list):
        fail("networks_metadata must be a list")
    if len(networks_metadata) == 0:
        fail("networks_metadata cannot be empty")
    
    plan.print("Extracting configuration artifacts for {} networks...".format(len(networks_metadata)))
    
    extracted_artifacts = []
    
    # Extract artifacts for each network
    for network_meta in networks_metadata:
        deployment_suffix = network_meta.get("deployment_suffix", "")
        sequencer_type = network_meta.get("sequencer_type", "")
        network_id = network_meta.get("network_id", 0)
        
        plan.print("Extracting artifacts for network {} (suffix: {})".format(network_id, deployment_suffix))
        
        # Extract keystores
        keystores = extract_keystores(plan, args, deployment_suffix)
        
        # Extract network-specific configs (already created in network_registrar)
        network_configs = struct(
            cdk_node_config=network_meta.config_artifacts.get("cdk_node_config", ""),
            aggkit_config=network_meta.config_artifacts.get("aggkit_config", ""),
            bridge_config=network_meta.config_artifacts.get("bridge_config", ""),
            genesis_artifact=network_meta.config_artifacts.get("genesis_artifact", ""),
        )
        
        # Extract chain configs for CDK-Erigon networks
        chain_configs = struct()
        if sequencer_type == constants.SEQUENCER_TYPE.cdk_erigon:
            # Get chain_name from network metadata or use default
            chain_name = network_meta.get("chain_name", args.get("chain_name", "kurtosis"))
            chain_configs = extract_chain_configs(plan, args, deployment_suffix, chain_name)
        
        # Store extracted artifacts for this network
        network_artifacts = struct(
            network_id=network_id,
            deployment_suffix=deployment_suffix,
            sequencer_type=sequencer_type,
            keystores=keystores,
            configs=network_configs,
            chain_configs=chain_configs,
        )
        extracted_artifacts.append(network_artifacts)
    
    # Create agglayer config artifact (basic version, will be updated in post-processing)
    plan.print("Creating agglayer config artifact...")
    if deployment_stages == None:
        deployment_stages = {"deploy_agglayer": True}
    agglayer_config_artifact = create_agglayer_config(plan, args, contract_setup_addresses, deployment_stages)
    
    # Create artifact manifest
    manifest = struct(
        networks=extracted_artifacts,
        agglayer_config=agglayer_config_artifact,
        total_networks=len(networks_metadata),
    )
    
    plan.print("Config artifact extraction completed: {} networks processed".format(len(networks_metadata)))
    
    return struct(
        manifest=manifest,
        extracted_artifacts=extracted_artifacts,
        agglayer_config_artifact=agglayer_config_artifact,
    )


def extract_keystores(plan, args, deployment_suffix):
    """
    Extract keystore artifacts from contracts service.
    
    Args:
        plan: Kurtosis plan object
        args: Parsed arguments dictionary
        deployment_suffix: Deployment suffix for the network
    
    Returns:
        struct with keystore artifact references
    """
    contracts_service_name = "contracts" + deployment_suffix
    
    plan.print("Extracting keystores from service: {}".format(contracts_service_name))
    
    # Extract sequencer keystore
    sequencer_keystore = plan.store_service_files(
        name="sequencer-keystore{}".format(deployment_suffix),
        service_name=contracts_service_name,
        src=constants.KEYSTORES_DIR + "/sequencer.keystore",
    )
    
    # Extract aggregator keystore
    aggregator_keystore = plan.store_service_files(
        name="aggregator-keystore{}".format(deployment_suffix),
        service_name=contracts_service_name,
        src=constants.KEYSTORES_DIR + "/aggregator.keystore",
    )
    
    # Extract claimsponsor keystore (if exists)
    claimsponsor_keystore = ""
    try:
        claimsponsor_keystore = plan.store_service_files(
            name="claimsponsor-keystore{}".format(deployment_suffix),
            service_name=contracts_service_name,
            src=constants.KEYSTORES_DIR + "/claimsponsor.keystore",
        )
    except:
        # Claimsponsor keystore may not exist for all networks
        plan.print("Claimsponsor keystore not found for network {}".format(deployment_suffix))
    
    return struct(
        sequencer=sequencer_keystore,
        aggregator=aggregator_keystore,
        claimsponsor=claimsponsor_keystore,
    )


def extract_chain_configs(plan, args, deployment_suffix, chain_name=None):
    """
    Extract chain config artifacts from output-artifact for CDK-Erigon networks.
    
    Args:
        plan: Kurtosis plan object
        args: Parsed arguments dictionary
        deployment_suffix: Deployment suffix for the network
        chain_name: Chain name for this network (defaults to args["chain_name"] or "kurtosis")
    
    Returns:
        struct with chain config artifact references
    """
    contracts_service_name = "contracts" + deployment_suffix
    if chain_name == None:
        chain_name = args.get("chain_name", "kurtosis")
    
    plan.print("Extracting chain configs from service: {} (chain: {})".format(contracts_service_name, chain_name))
    
    # Extract chain configs directly from the contracts service for this network
    # Use unique artifact names with deployment suffix to avoid conflicts
    chain_config_artifact = ""
    chain_allocs_artifact = ""
    chain_first_batch_artifact = ""
    
    try:
        chain_config_artifact = plan.store_service_files(
            name="cdk-erigon-chain-config{}".format(deployment_suffix),
            service_name=contracts_service_name,
            src=constants.OUTPUT_DIR + "/dynamic-" + chain_name + "-conf.json",
        )
    except:
        plan.print("Warning: Chain config not found for network {} (chain: {})".format(deployment_suffix, chain_name))
    
    try:
        chain_allocs_artifact = plan.store_service_files(
            name="cdk-erigon-chain-allocs{}".format(deployment_suffix),
            service_name=contracts_service_name,
            src=constants.OUTPUT_DIR + "/dynamic-" + chain_name + "-allocs.json",
        )
    except:
        plan.print("Warning: Chain allocs not found for network {} (chain: {})".format(deployment_suffix, chain_name))
    
    try:
        chain_first_batch_artifact = plan.store_service_files(
            name="cdk-erigon-chain-first-batch{}".format(deployment_suffix),
            service_name=contracts_service_name,
            src=constants.OUTPUT_DIR + "/first-batch-config.json",
        )
    except:
        plan.print("Warning: Chain first batch config not found for network {} (chain: {})".format(deployment_suffix, chain_name))
    
    return struct(
        chain_config=chain_config_artifact,
        chain_allocs=chain_allocs_artifact,
        chain_first_batch=chain_first_batch_artifact,
    )


def create_agglayer_config(plan, args, contract_setup_addresses, deployment_stages):
    """
    Create agglayer config artifact (basic version).
    
    Note: This creates a basic agglayer config with the first network.
    The config will be updated in post-processing (step 6) to include all networks.
    
    Args:
        plan: Kurtosis plan object
        args: Parsed arguments dictionary
        contract_setup_addresses: Contract addresses from agglayer deployment
        deployment_stages: Deployment stages configuration
    
    Returns:
        agglayer config artifact name
    """
    # Use the existing agglayer config creation function
    # This will create a basic config that can be updated later
    agglayer_config_artifact = agglayer_package.create_agglayer_config_artifact(
        plan, deployment_stages, args, contract_setup_addresses
    )
    
    return agglayer_config_artifact
