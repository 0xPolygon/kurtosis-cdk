# Read and retrieve the content of a file, within a service.
# Note: It automatically removes newline characters.
def read_file_from_service(plan, service_name, filename):
    exec_recipe = ExecRecipe(
        command=["/bin/sh", "-c", "cat {} | tr -d '\n'".format(filename)]
    )
    result = plan.exec(service_name=service_name, recipe=exec_recipe)
    return result["output"]


# Extract a specific key from a JSON file, within a service, using jq.
def extract_json_key_from_service(plan, service_name, filename, key):
    plan.print("Extracting contract addresses and ports...")
    exec_recipe = ExecRecipe(
        command=[
            "/bin/sh",
            "-c",
            "cat {} | grep -w '{}' | xargs -n1 | tail -1".format(filename, key),
        ]
    )
    result = plan.exec(service_name=service_name, recipe=exec_recipe)
    return result["output"]
