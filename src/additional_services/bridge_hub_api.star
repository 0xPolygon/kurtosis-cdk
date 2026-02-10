constants = import_module("../package_io/constants.star")

NETWORK_NAME = "mainnet"

MONGODB_DB_NAME = "bridge-hub"
MONGODB_ROOT_USER = "user"
MONGODB_ROOT_PASSWORD = "password"

MONGODB_PORT_ID = "mongodb"
MONGODB_PORT_NUMBER = 27017

API_PORT_ID = "api"
API_PORT_NUMBER = 3001


def run(plan, args, contract_setup_addresses, l2_context):
    mongodb_url = run_mongodb(plan, args)

    l1_chain_id = str(args.get("l1_chain_id"))
    l1_bridge_address = contract_setup_addresses.get("l1_bridge_address")
    aggkit_bridge_service_url = ""  # TODO: Add aggkit_bridge_url to l2_context
    run_consumer(
        plan, l1_chain_id, l1_bridge_address, aggkit_bridge_service_url, mongodb_url
    )

    run_api(plan, l2_context)


def run_mongodb(plan, args):
    result = plan.add_service(
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
        MONGODB_ROOT_USER, MONGODB_ROOT_PASSWORD, result.hostname, MONGODB_PORT_NUMBER
    )
    return url


def run_consumer(
    plan, l1_chain_id, l1_bridge_address, aggkit_bridge_service_url, mongodb_url
):
    plan.add_service(
        name="bridge-hub-consumer",
        image=constants.DEFAULT_IMAGES.bridge_hub_consumer_image,
        environment={
            "NODE_ENV": "production",
            "NETWORK_ID": l1_chain_id,
            "NETWORK": NETWORK_NAME,
            "BRIDGE_SERVICE_URL": aggkit_bridge_service_url,
            "BRIDGE_CONTRACT_ADDRESS": l1_bridge_address,
            # db
            "MONGODB_CONNECTION_URI": mongodb_url,
            "MONGODB_DB_NAME": MONGODB_DB_NAME,
        },
    )


def run_api(plan, l2_context):
    proof_endpoint = "aggkit_bridge_url/bridge/v1"
    proof_config = {'"{}"'.format(NETWORK_NAME): {"0": proof_endpoint}}
    rpc_config = {'"{}"'.format(NETWORK_NAME): {"0": l2_context.rpc_url}}

    plan.add_service(
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
