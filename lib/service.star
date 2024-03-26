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
