aggkit = import_module("./aggkit.star")


def test_extract_aggkit_version(plan):
    valid_cases = [
        ("ghcr.io/agglayer/aggkit:1", 1),
        ("ghcr.io/agglayer/aggkit:1.1", 1.1),
        ("ghcr.io/agglayer/aggkit:1.0.0", 1.0),
        ("ghcr.io/agglayer/aggkit:0.5.0-beta1", 0.5),
        ("ghcr.io/agglayer/aggkit:0.4.5", 0.4),
        ("ghcr.io/agglayer/aggkit:0.3.2-beta1", 0.3),
        ("ghcr.io/agglayer/aggkit:v0.5.0-beta1-custom", 0.5),
    ]
    for image, tag in valid_cases:
        result = aggkit._extract_aggkit_version(image)
        expect.eq(result, tag)


def test_get_agglayer_endpoint(plan):
    # "0.11" must order after "0.3": the minor version is compared as an integer.
    valid_cases = [
        ("ghcr.io/agglayer/aggkit:0.5.0-beta1", "grpc"),
        ("ghcr.io/agglayer/aggkit:local", "grpc"),
        ("ghcr.io/agglayer/aggkit:1.0.0", "grpc"),
        ("ghcr.io/agglayer/aggkit:0.11.0", "grpc"),
        ("ghcr.io/agglayer/aggkit:0.2.14", "readrpc"),
        ("ghcr.io/agglayer/aggkit:0.1", "readrpc"),
        ("ghcr.io/agglayer/aggkit:0", "readrpc"),
    ]
    for image, expected in valid_cases:
        result = aggkit._get_agglayer_endpoint(image)
        expect.eq(result, expected)


def test_aggkit_version_gte_legacy_bridge_addr(plan):
    # The legacy polygonBridgeAddr flag is `not _aggkit_version_gte(image, 0, 8)`;
    # "0.11" must not be read as older than "0.8".
    cases = [
        ("ghcr.io/agglayer/aggkit:0.11.0", False),
        ("ghcr.io/agglayer/aggkit:0.9.0", False),
        ("ghcr.io/agglayer/aggkit:0.7.5", True),
        ("ghcr.io/agglayer/aggkit:0.4.5", True),
        ("ghcr.io/agglayer/aggkit:0.8", False),
        ("ghcr.io/agglayer/aggkit:1.0.0", False),
        ("ghcr.io/agglayer/aggkit:local", False),
    ]
    for image, expect_legacy in cases:
        result = not aggkit._aggkit_version_gte(image, 0, 8)
        expect.eq(result, expect_legacy)


def test_aggkit_version_gte_non_numeric_tags_are_latest(plan):
    for image in [
        "ghcr.io/agglayer/aggkit:develop_2026_08_03_13_20_56c849c",
        "ghcr.io/agglayer/aggkit:feat-some-branch_20260803",
        "ghcr.io/agglayer/aggkit:latest",
    ]:
        expect.eq(aggkit._aggkit_version_gte(image, 0, 11), True)
        expect.eq(aggkit._get_agglayer_endpoint(image), "grpc")


def test_has_component(plan):
    cases = [
        ("aggsender,aggoracle", "bridge", False),
        ("aggsender,aggoracle,bridge", "bridge", True),
        ("aggsender, bridge", "bridge", True),
        ("bridge", "bridge", True),
        ("bridgeX,aggoracle", "bridge", False),
        ("", "bridge", False),
    ]
    for components, component, expected in cases:
        expect.eq(aggkit.has_component(components, component), expected)
