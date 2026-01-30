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
constants = import_module("../package_io/constants.star")


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
    if type(snapshot_networks) != "list":
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

    # Step 3.5 - Record latest L1 block after contract deployment
    # This ensures we wait for this specific block to be finalized before exporting L1 state
    plan.print("Recording latest L1 block after contract deployment...")
    l1_rpc_url = l1_context.rpc_url
    deployment_block_result = plan.run_sh(
        name="record-deployment-block",
        description="Record L1 block after contract deployment",
        image=constants.TOOLBOX_IMAGE,
        env_vars={
            "L1_RPC_URL": l1_rpc_url,
        },
        run="\n".join([
            "LATEST_BLOCK=$(cast block-number --rpc-url \"$L1_RPC_URL\" latest 2>/dev/null || echo \"0\")",
            "echo \"Latest L1 block after deployment: $LATEST_BLOCK\"",
            "mkdir -p /tmp/deployment-metadata",
            "cat > /tmp/deployment-metadata/deployment-block.json <<EOF",
            "{",
            "  \"deployment_block\": $LATEST_BLOCK",
            "}",
            "EOF",
            "cat /tmp/deployment-metadata/deployment-block.json",
        ]),
        store=[
            StoreSpec(
                src="/tmp/deployment-metadata",
                name="deployment-block-metadata",
            ),
        ],
    )
    plan.print("Recorded deployment block metadata")

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
