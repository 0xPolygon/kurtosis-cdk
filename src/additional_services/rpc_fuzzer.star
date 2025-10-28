constants = import_module("../../src/package_io/constants.star")
wallet_module = import_module("../wallet/wallet.star")

RPC_FUZZER_FOLDER_NAME = "../../static_files/additional_services/rpc-fuzzer"
RPC_FUZZER_SCRIPT_NAME = "rpcfuzz.sh"


def run(plan, args):
    # Get rpc urls and funder private keys.
    l1_rpc_url = args.get("l1_rpc_url")
    l2_rpc_url = _get_l2_rpc_url(plan, args)
    l1_funder_private_key = args.get("l1_preallocated_private_key")
    l2_funder_private_key = args.get("l2_admin_private_key")

    # Start the fuzzer services.
    rpc_fuzz_artifact = plan.upload_files(
        src="{}/{}".format(RPC_FUZZER_FOLDER_NAME, RPC_FUZZER_SCRIPT_NAME),
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


def _start_rpc_fuzzer_service(plan, name, script_artifact, private_key, rpc_url):
    plan.add_service(
        name=name,
        config=ServiceConfig(
            image=constants.TOOLBOX_IMAGE,
            files={
                "/opt": Directory(artifact_names=[script_artifact]),
            },
            env_vars={
                "PRIVATE_KEY": private_key,
                "RPC_URL": rpc_url,
            },
            entrypoint=["bash", "-c"],
            cmd=["chmod +x /opt/{0} && /opt/{0}".format(RPC_FUZZER_SCRIPT_NAME)],
            # Resource limits
            min_cpu=100,  # 0.1 CPU
            max_cpu=1000,  # 1 CPU
            min_memory=128,  # 128Mb
            max_memory=1024,  # 1024Mb
        ),
    )
