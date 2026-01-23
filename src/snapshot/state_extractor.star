"""
L1 state extraction module for snapshot mode.

This module prepares L1 services for state extraction by:
1. Waiting for L1 to reach finalized state
2. Stopping L1 services (geth and lighthouse) gracefully
3. Storing metadata for post-processing extraction
"""

constants = import_module("../package_io/constants.star")


def prepare_l1_snapshot(plan, args, l1_context):
    """
    Prepare L1 services for snapshot extraction.
    
    This function:
    - Waits for L1 to reach finalized state
    - Stops geth and lighthouse services gracefully
    - Stores metadata for post-processing extraction
    
    Args:
        plan: Kurtosis plan object
        args: Parsed arguments dictionary
        l1_context: L1 context from l1_launcher (contains all_participants, chain_id, rpc_url)
    
    Returns:
        struct with L1 metadata for extraction
    """
    # Input validation
    if plan == None:
        fail("plan is required")
    if args == None:
        fail("args is required")
    
    plan.print("Preparing L1 for snapshot extraction...")
    
    # Check if L1 is deployed (not anvil or external L1)
    if l1_context == None or len(l1_context.get("all_participants", [])) == 0:
        plan.print("Warning: L1 not deployed in Kurtosis (using external L1 or anvil). Skipping L1 state extraction.")
        return struct(
            l1_deployed=False,
            geth_service_name="",
            lighthouse_service_name="",
            geth_datadir_path="",
            lighthouse_datadir_path="",
            finalized_block=0,
            finalized_slot=0,
            chain_id=args.get("l1_chain_id", 0),
            l1_rpc_url=args.get("l1_rpc_url", ""),
            l1_beacon_url=args.get("l1_beacon_url", ""),
        )
    
    # Get L1 RPC URLs
    l1_rpc_url = l1_context.get("rpc_url", args.get("l1_rpc_url", ""))
    l1_beacon_url = ""
    if len(l1_context.get("all_participants", [])) > 0:
        try:
            l1_beacon_url = l1_context.all_participants[0].cl_context.beacon_http_url
        except:
            l1_beacon_url = args.get("l1_beacon_url", "")
    
    if l1_beacon_url == "":
        l1_beacon_url = args.get("l1_beacon_url", "")
    
    # Get service names - try from context, otherwise use standard pattern
    geth_service_name = _get_geth_service_name(l1_context)
    lighthouse_service_name = _get_lighthouse_service_name(l1_context)
    
    plan.print("L1 service names - Geth: {}, Lighthouse: {}".format(geth_service_name, lighthouse_service_name))
    
    # Wait for finalized state
    plan.print("Waiting for L1 to reach finalized state...")
    finalized_info = _wait_for_finalized_state(plan, l1_rpc_url, l1_beacon_url, args)
    finalized_block = finalized_info.get("finalized_block", 0)
    finalized_slot = finalized_info.get("finalized_slot", 0)
    
    plan.print("L1 finalized state - Block: {}, Slot: {}".format(finalized_block, finalized_slot))
    
    # Stop services gracefully
    plan.print("Stopping L1 services gracefully...")
    _stop_geth_gracefully(plan, geth_service_name)
    _stop_lighthouse_gracefully(plan, lighthouse_service_name)
    
    # Standard datadir paths used by ethereum-package
    geth_datadir_path = "/root/.ethereum"
    lighthouse_datadir_path = "/root/.lighthouse"
    
    # Store metadata
    l1_metadata = struct(
        l1_deployed=True,
        geth_service_name=geth_service_name,
        lighthouse_service_name=lighthouse_service_name,
        geth_datadir_path=geth_datadir_path,
        lighthouse_datadir_path=lighthouse_datadir_path,
        finalized_block=finalized_block,
        finalized_slot=finalized_slot,
        chain_id=l1_context.get("chain_id", args.get("l1_chain_id", 0)),
        l1_rpc_url=l1_rpc_url,
        l1_beacon_url=l1_beacon_url,
    )
    
    plan.print("L1 snapshot preparation completed")
    return l1_metadata


def _get_geth_service_name(l1_context):
    """
    Get geth service name from l1_context or use standard pattern.
    
    Args:
        l1_context: L1 context from l1_launcher
    
    Returns:
        Service name string
    """
    # Try to get from context if available
    if l1_context != None and len(l1_context.get("all_participants", [])) > 0:
        try:
            # Check if service name is in el_context
            el_context = l1_context.all_participants[0].el_context
            if hasattr(el_context, "service_name"):
                return el_context.service_name
        except:
            pass
    
    # Use standard naming pattern from ethereum-package
    return "el-1-geth-lighthouse"


def _get_lighthouse_service_name(l1_context):
    """
    Get lighthouse service name from l1_context or use standard pattern.
    
    Args:
        l1_context: L1 context from l1_launcher
    
    Returns:
        Service name string
    """
    # Try to get from context if available
    if l1_context != None and len(l1_context.get("all_participants", [])) > 0:
        try:
            # Check if service name is in cl_context
            cl_context = l1_context.all_participants[0].cl_context
            if hasattr(cl_context, "service_name"):
                return cl_context.service_name
        except:
            pass
    
    # Use standard naming pattern from ethereum-package
    return "cl-1-lighthouse-geth"


def _wait_for_finalized_state(plan, l1_rpc_url, l1_beacon_url, args):
    """
    Wait for L1 to reach finalized state.
    
    Args:
        plan: Kurtosis plan object
        l1_rpc_url: L1 RPC URL
        l1_beacon_url: L1 beacon API URL
        args: Parsed arguments dictionary
    
    Returns:
        struct with finalized_block and finalized_slot
    """
    min_finalized_blocks = args.get("snapshot_l1_wait_blocks", 1)
    
    plan.print("Waiting for at least {} finalized blocks...".format(min_finalized_blocks))
    
    # Wait for finalized block
    finalized_block_result = plan.run_sh(
        name="wait-for-finalized-block",
        description="Wait for L1 finalized block",
        image=constants.TOOLBOX_IMAGE,
        env_vars={
            "L1_RPC_URL": l1_rpc_url,
            "MIN_BLOCKS": str(min_finalized_blocks),
        },
        run="\n".join([
            "while true; do",
            "  sleep 2;",
            "  FINALIZED_BLOCK=$(cast block-number --rpc-url \"$L1_RPC_URL\" finalized 2>/dev/null || echo \"0\");",
            "  LATEST_BLOCK=$(cast block-number --rpc-url \"$L1_RPC_URL\" latest 2>/dev/null || echo \"0\");",
            "  echo \"L1 blocks - Latest: $LATEST_BLOCK, Finalized: $FINALIZED_BLOCK\";",
            "  if [ \"$FINALIZED_BLOCK\" -ge \"$MIN_BLOCKS\" ]; then",
            "    echo \"$FINALIZED_BLOCK\";",
            "    break;",
            "  fi;",
            "done",
        ]),
        wait="10m",
    )
    
    finalized_block = 0
    try:
        # Get the last line of output (the finalized block number)
        output_lines = finalized_block_result.output.strip().split("\n")
        if len(output_lines) > 0:
            finalized_block = int(output_lines[-1])
    except:
        plan.print("Warning: Could not parse finalized block number, using 0")
    
    # Wait for finalized slot
    finalized_slot = 0
    if l1_beacon_url != "":
        plan.print("Waiting for finalized slot...")
        finalized_slot_result = plan.run_sh(
            name="wait-for-finalized-slot",
            description="Wait for L1 finalized slot",
            image=constants.TOOLBOX_IMAGE,
            env_vars={
                "BEACON_URL": l1_beacon_url,
            },
            run="\n".join([
                "while true; do",
                "  sleep 2;",
                "  RESPONSE=$(curl --silent \"$BEACON_URL/eth/v1/beacon/headers/finalized\" 2>/dev/null || echo '{}');",
                "  SLOT=$(echo \"$RESPONSE\" | jq --raw-output '.data.header.message.slot // 0' 2>/dev/null || echo \"0\");",
                "  echo \"L1 finalized slot: $SLOT\";",
                "  if [ \"$SLOT\" != \"0\" ] && [ \"$SLOT\" != \"null\" ]; then",
                "    echo \"$SLOT\";",
                "    break;",
                "  fi;",
                "done",
            ]),
            wait="10m",
        )
        
        try:
            # Get the last line of output (the finalized slot number)
            output_lines = finalized_slot_result.output.strip().split("\n")
            if len(output_lines) > 0:
                finalized_slot = int(output_lines[-1])
        except:
            plan.print("Warning: Could not parse finalized slot number, using 0")
    
    return struct(
        finalized_block=finalized_block,
        finalized_slot=finalized_slot,
    )


def _stop_geth_gracefully(plan, service_name):
    """
    Stop geth service gracefully by sending SIGTERM.
    
    Args:
        plan: Kurtosis plan object
        service_name: Geth service name
    """
    if service_name == "":
        plan.print("Warning: Geth service name is empty, skipping stop")
        return
    
    plan.print("Stopping geth service: {}".format(service_name))
    
    # Send SIGTERM to geth process
    plan.exec(
        description="Stopping geth gracefully",
        service_name=service_name,
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", "pkill -SIGTERM geth || true"],
        ),
    )
    
    # Wait a bit for graceful shutdown
    plan.print("Waiting for geth to stop...")
    plan.run_sh(
        name="wait-for-geth-stop",
        description="Wait for geth to stop",
        image=constants.TOOLBOX_IMAGE,
        run="sleep 5",
    )


def _stop_lighthouse_gracefully(plan, service_name):
    """
    Stop lighthouse service gracefully by sending SIGTERM.
    
    Args:
        plan: Kurtosis plan object
        service_name: Lighthouse service name
    """
    if service_name == "":
        plan.print("Warning: Lighthouse service name is empty, skipping stop")
        return
    
    plan.print("Stopping lighthouse service: {}".format(service_name))
    
    # Send SIGTERM to lighthouse process
    plan.exec(
        description="Stopping lighthouse gracefully",
        service_name=service_name,
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", "pkill -SIGTERM lighthouse || true"],
        ),
    )
    
    # Wait a bit for graceful shutdown
    plan.print("Waiting for lighthouse to stop...")
    plan.run_sh(
        name="wait-for-lighthouse-stop",
        description="Wait for lighthouse to stop",
        image=constants.TOOLBOX_IMAGE,
        run="sleep 5",
    )
