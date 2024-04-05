# Extract a specific key from a JSON file, within a service, using jq.
def extract_json_key_from_service(plan, service_name, filename, key):
    plan.print("Extracting contract addresses and ports...")
    exec_recipe = ExecRecipe(
        command=[
            "/bin/sh",
            "-c",
            "cat {}".format(filename),
        ],
        extract={"extracted_value": "fromjson | .{}".format(key)},
    )
    result = plan.exec(service_name=service_name, recipe=exec_recipe)
    return result["extract.extracted_value"]


# Get key from the contracts service.
# TODO: The contracts service should only run once, save config to artifacts and shut down.
# We need to use `get_file_artifacts` instead of this method.
def get_key_from_config(plan, args, key):
    return extract_json_key_from_service(
        plan,
        "contracts" + args["deployment_suffix"],
        "/opt/zkevm/combined.json",
        key,
    )
