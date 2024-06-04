service_package = import_module("./lib/service.star")


def run(plan, args):
    # Create scripts artifacts.
    apply_workload_template = read_file(src="./templates/workload/apply_workload.sh")
    polycli_loadtest_template = read_file(
        src="./templates/workload/polycli_loadtest.sh"
    )
    polycli_rpcfuzz_template = read_file(src="./templates/workload/polycli_rpcfuzz.sh")
    bridge_template = read_file(src="./templates/workload/bridge.sh")

    contract_setup_addresses = service_package.get_contract_setup_addresses(plan, args)
    zkevm_rpc_service = plan.get_service("zkevm-node-rpc" + args["deployment_suffix"])
    zkevm_rpc_url = "http://{}:{}".format(
        zkevm_rpc_service.ip_address, zkevm_rpc_service.ports["http-rpc"].number
    )
    zkevm_bridge_service = plan.get_service(
        "zkevm-bridge-service" + args["deployment_suffix"]
    )
    zkevm_bridge_api_url = "http://{}:{}".format(
        zkevm_bridge_service.ip_address, zkevm_bridge_service.ports["rpc"].number
    )

    workload_script_artifact = plan.render_templates(
        name="workload-script-artifact",
        config={
            "apply_workload.sh": struct(
                template=apply_workload_template,
                data={
                    "commands": args["workload_commands"],
                },
            ),
            "polycli_loadtest_on_l2.sh": struct(
                template=polycli_loadtest_template,
                data={
                    "rpc_url": zkevm_rpc_url,
                    "private_key": args["zkevm_l2_admin_private_key"],
                },
            ),
            "polycli_rpcfuzz_on_l2.sh": struct(
                template=polycli_rpcfuzz_template,
                data={
                    "rpc_url": zkevm_rpc_url,
                    "private_key": args["zkevm_l2_admin_private_key"],
                },
            ),
            "bridge.sh": struct(
                template=bridge_template,
                data={
                    "zkevm_l2_admin_private_key": args["zkevm_l2_admin_private_key"],
                    "zkevm_l2_admin_address": args["zkevm_l2_admin_address"],
                    "l1_rpc_url": args["l1_rpc_url"],
                    "l2_rpc_url": zkevm_rpc_url,
                    "zkevm_bridge_api_url": zkevm_bridge_api_url,
                }
                | contract_setup_addresses,
            ),
        },
    )

    plan.add_service(
        name="workload" + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["toolbox_image"],
            files={
                "/usr/local/bin": Directory(artifact_names=[workload_script_artifact]),
            },
            entrypoint=["bash", "-c"],
            cmd=["chmod +x /usr/local/bin/*.sh && apply_workload.sh"],
            user=User(uid=0, gid=0),  # Run the container as root user.
        ),
    )
