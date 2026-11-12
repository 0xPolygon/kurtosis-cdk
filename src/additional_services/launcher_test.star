launcher = import_module("./launcher.star")


def test_order_additional_services(plan):
    cases = [
        ([], []),
        (["bridge_ui", "test_runner"], ["bridge_ui", "test_runner"]),
        (["aggkit_proxy", "bridge_ui"], ["aggkit_proxy", "bridge_ui"]),
        (["bridge_ui", "aggkit_proxy"], ["aggkit_proxy", "bridge_ui"]),
        (
            ["tx_spammer", "bridge_ui", "aggkit_proxy", "test_runner"],
            ["aggkit_proxy", "tx_spammer", "bridge_ui", "test_runner"],
        ),
    ]
    for services, expected in cases:
        expect.eq(launcher.order_additional_services(services), expected)
