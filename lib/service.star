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
