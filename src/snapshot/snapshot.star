"""
Main snapshot orchestration module.

This module coordinates the snapshot creation process:
1. Registers multiple networks
2. Extracts configuration artifacts
3. Prepares L1 for state extraction (waits for finalized state, stops services)
4. Generates docker-compose configuration (TODO: Step 8)
"""

network_registrar = import_module("./network_registrar.star")
config_extractor = import_module("./config_extractor.star")
state_extractor = import_module("./state_extractor.star")


def run(plan, args, deployment_stages, contract_setup_addresses, sovereign_contract_setup_addresses, l1_context, genesis_artifact, op_stack_args):
    """
    Main entry point for snapshot creation.
    
    Args:
        plan: Kurtosis plan object
        args: Parsed arguments dictionary
        deployment_stages: Deployment stages configuration
        contract_setup_addresses: Contract addresses from agglayer deployment
        sovereign_contract_setup_addresses: Contract addresses from sovereign deployment (unused for now)
        l1_context: L1 context from l1_launcher
        genesis_artifact: Genesis artifact for L2 networks (unused for now, generated per network)
        op_stack_args: OP Stack arguments for op-geth networks
    
    Returns:
        Snapshot metadata structure
    """
    # Input validation
    if plan == None:
        fail("plan is required")
    if args == None:
        fail("args is required")
    
    snapshot_networks = args.get("snapshot_networks", [])
    if not isinstance(snapshot_networks, list):
        fail("snapshot_networks must be a list")
    if len(snapshot_networks) == 0:
        fail("snapshot_networks cannot be empty")
    
    plan.print("Starting snapshot creation process...")
    
    # Step 3 - Register multiple networks
    snapshot_networks = args.get("snapshot_networks", [])
    networks_metadata = network_registrar.register_networks(
        plan,
        args,
        contract_setup_addresses,
        snapshot_networks,
        deployment_stages,
        op_stack_args,
    )
    
    # Step 4 - Extract config artifacts
    config_extraction_result = config_extractor.extract_config_artifacts(
        plan,
        args,
        networks_metadata,
        contract_setup_addresses,
        deployment_stages,
    )
    
    # Step 5 - Prepare L1 for state extraction
    l1_metadata = state_extractor.prepare_l1_snapshot(
        plan,
        args,
        l1_context,
    )
    
    # TODO: Step 8 - Generate docker-compose
    # compose_generator.generate_compose(...)
    
    plan.print("Snapshot creation process completed (networks registered, configs extracted, L1 prepared)")
    
    return struct(
        snapshot_mode=True,
        networks_metadata=networks_metadata,
        config_extraction_result=config_extraction_result,
        l1_context=l1_context,
        l1_metadata=l1_metadata,
    )
