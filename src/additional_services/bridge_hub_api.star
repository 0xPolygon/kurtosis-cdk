constants = import_module("../package_io/constants.star")
wallet_module = import_module("../wallet/wallet.star")

NETWORK_NAME = "mainnet"

MONGODB_DB_NAME = "bridge-hub"
MONGODB_ROOT_USER = "user"
MONGODB_ROOT_PASSWORD = "password"

MONGODB_PORT_ID = "mongodb"
MONGODB_PORT_NUMBER = 27017

API_PORT_ID = "api"
API_PORT_NUMBER = 3001


def run(plan, args, contract_setup_addresses, l2_context):
    # Start the database
    mongodb_url = run_mongodb(plan, args)

    # Start the consumer
    l1_bridge_address = contract_setup_addresses.get("l1_bridge_address")

    bridge_service_url = None
    if l2_context.aggkit_bridge_url != None:
        bridge_service_url = l2_context.aggkit_bridge_url
    elif l2_context.zkevm_bridge_service_url != None:
        bridge_service_url = l2_context.zkevm_bridge_service_url
    else:
        fail("No bridge service url found in l2 context")

    rpc_config = {'"{}"'.format(NETWORK_NAME): {"0": rpc_url}}

    run_consumer(plan, args, l1_bridge_address, bridge_service_url, mongodb_url)

    # Start the API
    api_url = run_api(plan, bridge_service_url, rpc_config)

    # Start the L2 auto-claimer
    run_l2_autoclaimer(
        plan, args, api_url, l2_context.l2_rpc_url, l1_bridge_address, rpc_config
    )


def run_mongodb(plan, args):
    service = plan.add_service(
        name="bridge-hub-db",
        image=constants.DEFAULT_IMAGES.mongodb_image,
        environment={
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
    )
    url = "mongodb://{}:{}@{}:{}".format(
        MONGODB_ROOT_USER, MONGODB_ROOT_PASSWORD, service.hostname, MONGODB_PORT_NUMBER
    )
    return url


def run_consumer(plan, args, l1_bridge_address, bridge_service_url, mongodb_url):
    l1_chain_id = str(args.get("l1_chain_id"))
    plan.add_service(
        name="bridge-hub-consumer",
        image=constants.DEFAULT_IMAGES.bridge_hub_consumer_image,
        environment={
            "NODE_ENV": "production",
            "NETWORK_ID": l1_chain_id,
            "NETWORK": NETWORK_NAME,
            "BRIDGE_SERVICE_URL": bridge_service_url,
            "BRIDGE_CONTRACT_ADDRESS": l1_bridge_address,
            # db
            "MONGODB_CONNECTION_URI": mongodb_url,
            "MONGODB_DB_NAME": MONGODB_DB_NAME,
        },
    )


def run_api(plan, bridge_service_url, rpc_config):
    proof_config = {
        '"{}"'.format(NETWORK_NAME): {"0": "{}/bridge/v1".format(bridge_service_url)}
    }

    service = plan.add_service(
        name="bridge-hub-api",
        image=constants.DEFAULT_IMAGES.bridge_hub_api_image,
        environment={
            "NODE_ENV": "production",
            "PROOF_CONFIG": str(proof_config),
            "RPC_CONFIG": str(rpc_config),
            # db
            "MONGODB_CONNECTION_URI": mongodb_url,
            "MONGODB_DB_NAME": MONGODB_DB_NAME,
        },
        ports={
            API_PORT_ID: PortSpec(number=API_PORT_NUMBER, application_protocol="http")
        },
    )
    url = service.ports[API_PORT_ID].url
    return url


def run_l2_autoclaimer(plan, args, api_url, l2_rpc_url, l1_bridge_address, rpc_config):
    # Generate new wallet for the auto-claimer.
    funder_private_key = args.get("l2_admin_private_key")
    wallet = _generate_new_funded_l2_wallet(plan, funder_private_key, l2_rpc_url)

    l1_chain_id = args.get("l1_chain_id")
    l2_chain_id = args.get("l2_chain_id")
    l2_network_id = args.get("l2_network_id")
    plan.add_service(
        name="bridge-hub-autoclaim",
        image=constants.DEFAULT_IMAGES.bridge_hub_autoclaim_image,
        environment={
            "NODE_ENV": "production",
            "BRIDGE_HUB_API_URL": api_url,
            "SOURCE_NETWORKS": "[{}]".format(l1_chain_id),
            "DESTINATION_NETWORK_CHAINID": l2_chain_id,
            "DESTINATION_NETWORK": l2_network_id,
            "BRIDGE_CONTRACT": l1_bridge_address,
            "PRIVATE_KEY": wallet.private_key,
            "RPC_CONFIG": str(rpc_config),
        },
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
