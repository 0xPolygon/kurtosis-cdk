constants = import_module("../../src/package_io/constants.star")
wallet_module = import_module("../wallet/wallet.star")

# The folder where tx spammer template files are stored in the repository.
TEMPLATES_FOLDER_PATH = "../../static_files/additional_services/tx-spammer"
# The name of the spammer scripts.
TX_SPAMMER_SCRIPT_NAME = "loadtest.sh"
RPC_FUZZER_SCRIPT_NAME = "rpcfuzz.sh"

# The folder where tx spammer scripts are stored inside the service.
SCRIPT_FOLDER_PATH = "/opt/scripts"


def run(plan, args, contract_setup_addresses):
    # Get rpc urls and funder private keys.
    l1_rpc_url = args.get("l1_rpc_url")
    l2_rpc_url = _get_l2_rpc_url(plan, args)
    l1_funder_private_key = args.get("l1_preallocated_private_key")
    l2_funder_private_key = args.get("zkevm_l2_admin_private_key")

    # Start the spammer services.
    tx_spammer_artifact = plan.upload_files(
        src="{}/{}".format(TEMPLATES_FOLDER_PATH, TX_SPAMMER_SCRIPT_NAME),
        name="tx-spammer-script",
    )

    l1_tx_spammer_wallet = _generate_new_funded_wallet(
        plan, l1_funder_private_key, l1_rpc_url
    )
    _start_tx_spammer_service(
        plan,
        name="l1-tx-spammer" + args.get("deployment_suffix"),
        script_artifact=tx_spammer_artifact,
        private_key=l1_tx_spammer_wallet.private_key,
        rpc_url=l1_rpc_url,
    )

    l2_tx_spammer_wallet = _generate_new_funded_wallet(
        plan, l2_funder_private_key, l2_rpc_url
    )
    _start_tx_spammer_service(
        plan,
        name="l2-tx-spammer" + args.get("deployment_suffix"),
        script_artifact=tx_spammer_artifact,
        private_key=l2_tx_spammer_wallet.private_key,
        rpc_url=l2_rpc_url,
    )

    # Start the fuzzer services.
    rpc_fuzz_artifact = plan.upload_files(
        src="{}/{}".format(TEMPLATES_FOLDER_PATH, RPC_FUZZER_SCRIPT_NAME),
        name="rpc-fuzz-script",
    )

    l1_rpc_fuzzer_wallet = _generate_new_funded_wallet(
        plan, l1_funder_private_key, l1_rpc_url
    )
    _start_rpc_fuzzer_service(
        plan,
        name="l1-rpc-fuzzer" + args.get("deployment_suffix"),
        script_artifact=rpc_fuzz_artifact,
        private_key=l1_rpc_fuzzer_wallet.private_key,
        rpc_url=l1_rpc_url,
    )

    l2_rpc_fuzzer_wallet = _generate_new_funded_wallet(
        plan, l2_funder_private_key, l2_rpc_url
    )
    _start_rpc_fuzzer_service(
        plan,
        name="l2-rpc-fuzzer" + args.get("deployment_suffix"),
        script_artifact=rpc_fuzz_artifact,
        private_key=l2_rpc_fuzzer_wallet.private_key,
        rpc_url=l2_rpc_url,
    )


def _get_l2_rpc_url(plan, args):
    service_name = args.get("l2_rpc_name") + args.get("deployment_suffix")
    service = plan.get_service(service_name)
    if "rpc" not in service.ports:
        fail("The 'rpc' port of the l2 rpc service is not available.")
    return service.ports["rpc"].url


def _generate_new_funded_wallet(plan, funder_private_key, rpc_url):
    wallet = wallet_module.new(plan)
    wallet_module.fund(
        plan,
        address=wallet.address,
        rpc_url=rpc_url,
        funder_private_key=funder_private_key,
    )
    return wallet


def _start_tx_spammer_service(plan, name, script_artifact, private_key, rpc_url):
    _start_service(
        plan,
        name=name,
        script_artifact=script_artifact,
        script_name=TX_SPAMMER_SCRIPT_NAME,
        private_key=private_key,
        rpc_url=rpc_url,
    )


def _start_rpc_fuzzer_service(plan, name, script_artifact, private_key, rpc_url):
    _start_service(
        plan,
        name=name,
        script_artifact=script_artifact,
        script_name=RPC_FUZZER_SCRIPT_NAME,
        private_key=private_key,
        rpc_url=rpc_url,
    )


def _start_service(plan, name, script_artifact, script_name, private_key, rpc_url):
    plan.add_service(
        name=name,
        config=ServiceConfig(
            image=constants.TOOLBOX_IMAGE,
            files={
                SCRIPT_FOLDER_PATH: Directory(artifact_names=[script_artifact]),
            },
            env_vars={
                "PRIVATE_KEY": private_key,
                "RPC_URL": rpc_url,
            },
            entrypoint=["bash", "-c"],
            cmd=["chmod +x {0}/{1} && {0}/{1}".format(SCRIPT_FOLDER_PATH, script_name)],
        ),
    )
