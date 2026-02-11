constants = import_module("../package_io/constants.star")
wallet_module = import_module("../wallet/wallet.star")

NETWORK_NAME = "devnet"

MONGODB_DB_NAME = "bridge-hub"
MONGODB_ROOT_USER = "user"
MONGODB_ROOT_PASSWORD = "password"

MONGODB_PORT_ID = "mongodb"
MONGODB_PORT_NUMBER = 27017

API_PORT_ID = "http"
API_PORT_NUMBER = 3001

AGGLAYER_DEV_UI_PORT_ID = "http"
AGGLAYER_DEV_UI_PORT_NUMBER = 80


def run(plan, args, contract_setup_addresses, l2_context):
    if l2_context.aggkit_bridge_url == None:
        plan.print(
            "Skipping bridge hub api deployment since no aggkit bridge instance was found"
        )
        return

    # Start the database
    mongodb_url = run_mongodb(plan, args)

    # Start the L1 consumer (indexer)
    l1_bridge_address = contract_setup_addresses.get("l1_bridge_address")
    run_l1_consumer(
        plan,
        args,
        l1_bridge_address,
        l2_context.aggkit_bridge_url,
        args.get("l1_rpc_url"),
        mongodb_url,
    )

    # Start the L2 consumer (indexer)
    l2_bridge_address = contract_setup_addresses.get("l2_bridge_address")
    run_l2_consumer(
        plan,
        args,
        l2_bridge_address,
        l2_context.aggkit_bridge_url,
        l2_context.rpc_url,
        mongodb_url,
    )

    # Start the API
    api_url = run_api(
        plan, args, l2_context.aggkit_bridge_url, mongodb_url, l2_context.rpc_url
    )

    # Start the L2 auto-claimer
    run_l2_autoclaimer(plan, args, api_url, l2_context.rpc_url, l1_bridge_address)

    # Start the agglayer-dev-ui
    run_agglayer_dev_ui(plan, args, api_url)


def run_mongodb(plan, args):
    service = plan.add_service(
        name="bridge-hub-db",
        config=ServiceConfig(
            image=constants.DEFAULT_IMAGES.get("mongodb_image"),
            env_vars={
                "MONGO_INITDB_DATABASE": MONGODB_DB_NAME,
                "MONGO_INITDB_ROOT_USERNAME": MONGODB_ROOT_USER,
                "MONGO_INITDB_ROOT_PASSWORD": MONGODB_ROOT_PASSWORD,
            },
            files={
                "/data/db": Directory(persistent_key="mongodb-data"),
            },
            ports={
                MONGODB_PORT_ID: PortSpec(
                    number=MONGODB_PORT_NUMBER, application_protocol="mongodb"
                )
            },
        ),
    )
    url = "mongodb://{}:{}@{}:{}".format(
        MONGODB_ROOT_USER, MONGODB_ROOT_PASSWORD, service.hostname, MONGODB_PORT_NUMBER
    )
    return url


def run_l1_consumer(
    plan, args, bridge_address, aggkit_bridge_service_url, rpc_url, mongodb_url
):
    plan.add_service(
        name="bridge-hub-consumer-l1",
        config=ServiceConfig(
            image=constants.DEFAULT_IMAGES.get("bridge_hub_consumer_image"),
            env_vars={
                "NODE_ENV": "production",
                "NETWORK_ID": "0",  # L1
                "NETWORK": NETWORK_NAME,
                "BRIDGE_SERVICE_URL": "{}/bridge/v1".format(aggkit_bridge_service_url),
                "BRIDGE_CONTRACT_ADDRESS": bridge_address,
                "RPC_URL": rpc_url,
                # db
                "MONGODB_CONNECTION_URI": mongodb_url,
                "MONGODB_DB_NAME": MONGODB_DB_NAME,
            },
        ),
    )


def run_l2_consumer(
    plan, args, bridge_address, aggkit_bridge_service_url, rpc_url, mongodb_url
):
    l2_network_id = str(args.get("l2_network_id"))
    plan.add_service(
        name="bridge-hub-consumer{}".format(args.get("deployment_suffix")),
        config=ServiceConfig(
            image=constants.DEFAULT_IMAGES.get("bridge_hub_consumer_image"),
            env_vars={
                "NODE_ENV": "production",
                "NETWORK_ID": l2_network_id,
                "NETWORK": NETWORK_NAME,
                "BRIDGE_SERVICE_URL": "{}/bridge/v1".format(aggkit_bridge_service_url),
                "BRIDGE_CONTRACT_ADDRESS": bridge_address,
                "RPC_URL": rpc_url,
                # db
                "MONGODB_CONNECTION_URI": mongodb_url,
                "MONGODB_DB_NAME": MONGODB_DB_NAME,
            },
        ),
    )


def run_api(plan, args, aggkit_bridge_service_url, mongodb_url, l2_rpc_url):
    # RPC URLs are nested by network name and network ID.
    rpc_config = {
        NETWORK_NAME: {
            "0": args.get("l1_rpc_url"),  # L1
            "1": l2_rpc_url,  # L2
        },
    }

    # Bridge URLs are nested by network name and network ID.
    proof_config = {
        NETWORK_NAME: {
            "0": "{}/bridge/v1".format(aggkit_bridge_service_url),
            "1": "{}/bridge/v1".format(aggkit_bridge_service_url),
        },
    }

    service = plan.add_service(
        name="bridge-hub-api",
        config=ServiceConfig(
            image=constants.DEFAULT_IMAGES.get("bridge_hub_api_image"),
            env_vars={
                "NODE_ENV": "production",
                "PROOF_CONFIG": json.encode(proof_config),
                "RPC_CONFIG": json.encode(rpc_config),
                # db
                "MONGODB_CONNECTION_URI": mongodb_url,
                "MONGODB_DB_NAME": MONGODB_DB_NAME,
            },
            ports={
                API_PORT_ID: PortSpec(
                    number=API_PORT_NUMBER, application_protocol="http"
                )
            },
        ),
    )
    url = service.ports[API_PORT_ID].url
    return url


def run_l2_autoclaimer(plan, args, api_url, l2_rpc_url, l1_bridge_address):
    l1_chain_id = args.get("l1_chain_id")
    l2_chain_id = args.get("l2_chain_id")

    # RPC URLs are nested by chain ID.
    rpc_config = {
        str(l1_chain_id): args.get("l1_rpc_url"),  # L1
        str(l2_chain_id): l2_rpc_url,  # L2
    }

    # Generate new wallet for the auto-claimer.
    funder_private_key = args.get("l2_admin_private_key")
    wallet = _generate_new_funded_l2_wallet(plan, funder_private_key, l2_rpc_url)

    l2_network_id = args.get("l2_network_id")
    plan.add_service(
        name="bridge-hub-autoclaim{}".format(args.get("deployment_suffix")),
        config=ServiceConfig(
            image=constants.DEFAULT_IMAGES.get("bridge_hub_autoclaim_image"),
            env_vars={
                "NODE_ENV": "production",
                "BRIDGE_HUB_API_URL": api_url,
                "SOURCE_NETWORKS": "[0, 1]",  # Claim for both L1 (0) and L2 (1) bridges
                "DESTINATION_NETWORK_CHAINID": str(l2_chain_id),
                "DESTINATION_NETWORK": str(l2_network_id),
                "BRIDGE_CONTRACT": l1_bridge_address,
                "PRIVATE_KEY": wallet.private_key,
                "RPC_CONFIG": json.encode(rpc_config),
            },
        ),
    )


def _generate_new_funded_l2_wallet(plan, funder_private_key, l2_rpc_url):
    wallet = wallet_module.new(plan)
    wallet_module.fund(
        plan,
        address=wallet.address,
        rpc_url=l2_rpc_url,
        funder_private_key=funder_private_key,
    )
    return wallet


def run_agglayer_dev_ui(plan, args, api_url):
    # The API URL is hardcoded inside the image. That's not ideal...
    plan.add_service(
        name="agglayer-dev-ui",
        config=ServiceConfig(
            image=constants.DEFAULT_IMAGES.get("agglayer_dev_ui_image"),
            ports={
                AGGLAYER_DEV_UI_PORT_ID: PortSpec(
                    number=AGGLAYER_DEV_UI_PORT_NUMBER, application_protocol="http"
                )
            },
        ),
    )
