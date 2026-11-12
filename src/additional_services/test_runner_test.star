test_runner = import_module("./test_runner.star")


def test_bridge_service_url_is_empty_without_a_bridge_component(plan):
    args = {"aggkit_components": "aggsender,aggoracle", "deployment_suffix": "-001"}
    expect.eq(test_runner._get_bridge_service_url(plan, args, False), "")
