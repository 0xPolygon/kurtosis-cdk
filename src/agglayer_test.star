agglayer = import_module("./agglayer.star")


def test_parse_version(plan):
    cases = [
        ("0.6.2", (0, 6, 2, 999)),
        ("v0.6.2", (0, 6, 2, 999)),
        ("0.6.0-rc.5", (0, 6, 0, 5)),
        ("0.6.0-rc7", (0, 6, 0, 7)),
        ("0.6", (0, 6, 0, 999)),
        ("0.5.0", (0, 5, 0, 999)),
        ("latest", (999, 0, 0, 999)),
        ("local", (999, 0, 0, 999)),
    ]
    for version, expected in cases:
        expect.eq(agglayer._parse_version(version), expected)


def test_settlement_config_gating(plan):
    # version -> (renders [outbound.rpc.settle], renders [settlement.*]).
    cases = [
        ("0.5.0", (True, False)),
        ("0.6.0-rc.1", (True, True)),
        ("0.6.0-rc.5", (True, True)),
        ("0.6.0-rc.6", (True, True)),
        ("0.6.0-rc.7", (False, True)),
        ("0.6.0", (False, True)),
        ("0.6.2", (False, True)),
        ("latest", (False, True)),
    ]
    for version, expected in cases:
        use_outbound = agglayer.use_outbound_settle(version)
        use_settlement = agglayer.use_settlement_config(version)
        expect.eq((use_outbound, use_settlement), expected)
