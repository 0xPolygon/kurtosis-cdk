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
    # l1_context is a struct with fields: chain_id, rpc_url, all_participants
    if l1_context == None or len(l1_context.all_participants) == 0:
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

    # Get L1 RPC URLs (l1_context is a struct, not a dict)
    l1_rpc_url = l1_context.rpc_url
    l1_beacon_url = ""
    if len(l1_context.all_participants) > 0:
        # Starlark doesn't support try/except, so we access directly
        # This will fail if the structure is different than expected
        l1_beacon_url = l1_context.all_participants[0].cl_context.beacon_http_url

    if l1_beacon_url == "":
        l1_beacon_url = args.get("l1_beacon_url", "")
    
    # Get service names - try from context, otherwise use standard pattern
    geth_service_name = _get_geth_service_name(l1_context)
    lighthouse_service_name = _get_lighthouse_service_name(l1_context)
    validator_service_name = _get_validator_service_name(l1_context)

    plan.print("L1 service names - Geth: {}, Lighthouse: {}, Validator: {}".format(geth_service_name, lighthouse_service_name, validator_service_name))
    
    # Wait for finalized state
    plan.print("Waiting for L1 to reach finalized state...")
    finalized_info = _wait_for_finalized_state(plan, l1_rpc_url, l1_beacon_url, args)
    # finalized_info is a struct with finalized_block and finalized_slot fields
    finalized_block = finalized_info.finalized_block
    finalized_slot = finalized_info.finalized_slot

    plan.print("L1 finalized state - Block: {}, Slot: {}".format(finalized_block, finalized_slot))

    # Datadir paths used by ethereum-package
    # Note: ethereum-package uses a nested structure:
    # - Geth actual datadir: /data/geth/execution-data/geth (contains chaindata, nodes, etc.)
    # - Lighthouse datadir: /data/lighthouse/beacon-data/beacon (contains beacon chain data)
    # - Lighthouse testnet config: /network-configs (contains genesis.ssz, config.yaml, etc.)
    # - Validator keys: /validator-keys (ethereum-package constant VALIDATOR_KEYS_DIRPATH_ON_SERVICE_CONTAINER)
    # We extract the actual datadirs, not the parent /data directory
    geth_datadir_path = "/data/geth/execution-data/geth"
    lighthouse_datadir_path = "/data/lighthouse/beacon-data/beacon"
    lighthouse_testnet_path = "/network-configs"
    validator_keys_path = "/validator-keys"

    # Stop services gracefully BEFORE extracting datadirs
    # This is critical: stopping geth triggers a flush of in-memory state to disk
    # Without this, we'll only capture genesis block even though we waited for finalized blocks
    plan.print("Stopping L1 services gracefully to flush state to disk...")
    _stop_geth_gracefully(plan, geth_service_name)
    _stop_lighthouse_gracefully(plan, lighthouse_service_name)

    # Extract datadirs AFTER stopping services
    # Kurtosis can extract files from stopped containers (they're stopped, not removed)
    plan.print("Extracting L1 state from stopped containers (this may take a while)...")

    # Extract geth datadir
    plan.print("Extracting geth datadir from {}...".format(geth_service_name))
    geth_datadir_artifact = plan.store_service_files(
        name="l1-geth-datadir",
        service_name=geth_service_name,
        src=geth_datadir_path,
    )
    plan.print("Geth datadir extracted to artifact: l1-geth-datadir")

    # Extract lighthouse datadir
    plan.print("Extracting lighthouse datadir from {}...".format(lighthouse_service_name))
    lighthouse_datadir_artifact = plan.store_service_files(
        name="l1-lighthouse-datadir",
        service_name=lighthouse_service_name,
        src=lighthouse_datadir_path,
    )
    plan.print("Lighthouse datadir extracted to artifact: l1-lighthouse-datadir")

    # Extract lighthouse testnet configuration (genesis.ssz, config.yaml, etc.)
    plan.print("Extracting lighthouse testnet config from {}...".format(lighthouse_service_name))
    lighthouse_testnet_artifact = plan.store_service_files(
        name="l1-lighthouse-testnet",
        service_name=lighthouse_service_name,
        src=lighthouse_testnet_path,
    )
    plan.print("Lighthouse testnet config extracted to artifact: l1-lighthouse-testnet")

    # Extract validator keystores from validator client
    # These are needed for the validator to continue proposing blocks
    plan.print("Extracting validator keystores from {}...".format(validator_service_name))
    validator_keys_artifact = plan.store_service_files(
        name="l1-validator-keys",
        service_name=validator_service_name,
        src=validator_keys_path,
    )
    plan.print("Validator keys extracted to artifact: l1-validator-keys")

    # Store metadata
    l1_metadata = struct(
        l1_deployed=True,
        geth_service_name=geth_service_name,
        lighthouse_service_name=lighthouse_service_name,
        validator_service_name=validator_service_name,
        geth_datadir_path=geth_datadir_path,
        lighthouse_datadir_path=lighthouse_datadir_path,
        lighthouse_testnet_path=lighthouse_testnet_path,
        validator_keys_path=validator_keys_path,
        geth_datadir_artifact=geth_datadir_artifact,
        lighthouse_datadir_artifact=lighthouse_datadir_artifact,
        lighthouse_testnet_artifact=lighthouse_testnet_artifact,
        validator_keys_artifact=validator_keys_artifact,
        finalized_block=finalized_block,
        finalized_slot=finalized_slot,
        chain_id=l1_context.chain_id,
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
    # Use standard naming pattern from ethereum-package
    # The ethereum-package uses a predictable naming pattern for services
    return "el-1-geth-lighthouse"


def _get_lighthouse_service_name(l1_context):
    """
    Get lighthouse service name from l1_context or use standard pattern.

    Args:
        l1_context: L1 context from l1_launcher

    Returns:
        Service name string
    """
    # Use standard naming pattern from ethereum-package
    # The ethereum-package uses a predictable naming pattern for services
    return "cl-1-lighthouse-geth"


def _get_validator_service_name(l1_context):
    """
    Get validator service name from l1_context or use standard pattern.

    Args:
        l1_context: L1 context from l1_launcher

    Returns:
        Service name string
    """
    # Use standard naming pattern from ethereum-package
    # Validator client follows pattern: vc-{index}-{el_type}-{cl_type}
    return "vc-1-geth-lighthouse"


def _wait_for_finalized_state(plan, l1_rpc_url, l1_beacon_url, args):
    """
    Wait for L1 to reach finalized state and store the finalized block/slot info.

    Args:
        plan: Kurtosis plan object
        l1_rpc_url: L1 RPC URL
        l1_beacon_url: L1 beacon API URL
        args: Parsed arguments dictionary

    Returns:
        struct with finalized_block and finalized_slot (placeholder values - actual values in artifact)
    """
    min_finalized_blocks = args.get("snapshot_l1_wait_blocks", 1)

    plan.print("Waiting for at least {} finalized blocks...".format(min_finalized_blocks))

    # Wait for finalized block and store the result to a file
    # We store it as an artifact so post-processing scripts can read the actual finalized block
    result = plan.run_sh(
        name="wait-for-finalized-state",
        description="Wait for L1 finalized state and store metadata",
        image=constants.TOOLBOX_IMAGE,
        env_vars={
            "L1_RPC_URL": l1_rpc_url,
            "L1_BEACON_URL": l1_beacon_url,
            "MIN_BLOCKS": str(min_finalized_blocks),
        },
        run="\n".join([
            "# Wait for finalized block",
            "while true; do",
            "  sleep 2;",
            "  FINALIZED_BLOCK=$(cast block-number --rpc-url \"$L1_RPC_URL\" finalized 2>/dev/null || echo \"0\");",
            "  LATEST_BLOCK=$(cast block-number --rpc-url \"$L1_RPC_URL\" latest 2>/dev/null || echo \"0\");",
            "  echo \"L1 blocks - Latest: $LATEST_BLOCK, Finalized: $FINALIZED_BLOCK\";",
            "  if [ \"$FINALIZED_BLOCK\" -ge \"$MIN_BLOCKS\" ]; then",
            "    echo \"✅ L1 reached finalized block: $FINALIZED_BLOCK\";",
            "    break;",
            "  fi;",
            "done",
            "",
            "# Wait for finalized slot (if beacon URL provided)",
            "FINALIZED_SLOT=0",
            "if [ -n \"$L1_BEACON_URL\" ]; then",
            "  while true; do",
            "    sleep 2;",
            "    RESPONSE=$(curl --silent \"$L1_BEACON_URL/eth/v1/beacon/headers/finalized\" 2>/dev/null || echo '{}');",
            "    SLOT=$(echo \"$RESPONSE\" | jq --raw-output '.data.header.message.slot // 0' 2>/dev/null || echo \"0\");",
            "    echo \"L1 finalized slot: $SLOT\";",
            "    if [ \"$SLOT\" != \"0\" ] && [ \"$SLOT\" != \"null\" ]; then",
            "      echo \"✅ L1 reached finalized slot: $SLOT\";",
            "      FINALIZED_SLOT=$SLOT",
            "      break;",
            "    fi;",
            "  done",
            "fi",
            "",
            "# Store metadata as JSON for post-processing scripts",
            "mkdir -p /tmp/l1-metadata",
            "cat > /tmp/l1-metadata/finalized-state.json <<EOF",
            "{",
            "  \"finalized_block\": $FINALIZED_BLOCK,",
            "  \"finalized_slot\": $FINALIZED_SLOT,",
            "  \"l1_rpc_url\": \"$L1_RPC_URL\",",
            "  \"l1_beacon_url\": \"$L1_BEACON_URL\",",
            "  \"timestamp\": \"$(date -u +\"%Y-%m-%dT%H:%M:%SZ\")\"",
            "}",
            "EOF",
            "",
            "echo \"Stored L1 metadata to /tmp/l1-metadata/finalized-state.json\"",
            "cat /tmp/l1-metadata/finalized-state.json",
        ]),
        store=[
            StoreSpec(
                src="/tmp/l1-metadata",
                name="l1-finalized-metadata",
            ),
        ],
        wait="10m",
    )

    # Return placeholder values - actual values are stored in the artifact
    # Post-processing scripts will read from the artifact
    return struct(
        finalized_block=0,
        finalized_slot=0,
        metadata_artifact="l1-finalized-metadata",
    )


def _stop_geth_gracefully(plan, service_name):
    """
    Stop geth service gracefully by sending SIGTERM.
    This triggers geth to flush all in-memory state to disk.

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

    # Wait for graceful shutdown and state flush
    # Geth needs time to flush in-memory state to disk (chaindata, state DB, etc.)
    plan.print("Waiting for geth to flush state and stop (this may take 15-30 seconds)...")
    plan.run_sh(
        name="wait-for-geth-stop",
        description="Wait for geth to flush state and stop",
        image=constants.TOOLBOX_IMAGE,
        run="sleep 20",
    )


def _stop_lighthouse_gracefully(plan, service_name):
    """
    Stop lighthouse service gracefully by sending SIGTERM.
    This triggers lighthouse to flush beacon chain state to disk.

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

    # Wait for graceful shutdown and state flush
    plan.print("Waiting for lighthouse to flush state and stop...")
    plan.run_sh(
        name="wait-for-lighthouse-stop",
        description="Wait for lighthouse to flush state and stop",
        image=constants.TOOLBOX_IMAGE,
        run="sleep 10",
    )
