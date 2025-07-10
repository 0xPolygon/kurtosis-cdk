aggkit = import_module("aggkit.star")


def test_get_agglayer_endpoint(plan):
    """Test version comparison logic for grpc vs readrpc."""

    # Test cases for versions that should return "readrpc" (< 0.3.0).
    readrpc_cases = [
        "registry.example.com/aggkit:0.2.0-beta",
        "registry.example.com/aggkit:v0.2.0-rc.1",
        "aggkit:0.2.0-beta",
        "aggkit:v0.2.0-rc.1",
        "registry.example.com/aggkit:0.1.5-beta",
        "registry.example.com/aggkit:v0.1.5-rc.1",
        "aggkit:0.1.5-beta",
        "aggkit:v0.1.5-rc.1",
    ]
    for image in readrpc_cases:
        result = aggkit.get_agglayer_endpoint(plan, image)
        expect.eq(result, "readrpc")

    # Test cases for versions that should return "grpc" (>= 0.3.0).
    grpc_cases = [
        "registry.example.com/aggkit:0.3.0-beta",
        "registry.example.com/aggkit:v0.3.0-rc.1",
        "aggkit:0.3.0-beta",
        "aggkit:v0.3.0-rc.1",
        "registry.example.com/aggkit:0.4.5-beta",
        "registry.example.com/aggkit:v0.4.5-rc.1",
        "aggkit:0.4.5-beta",
        "aggkit:v0.4.5-rc.1",
        # local development images should always return grpc.
        "aggkit:local",
    ]
    for image in grpc_cases:
        result = aggkit.get_agglayer_endpoint(plan, image)
        expect.eq(result, "grpc")

    # Test cases that should fail.
    fail_cases = [
        ("aggkit:latest", "latest"),
        ("aggkit:main", "main"),
        ("aggkit", "aggkit"),
        ("aggkit:", ""),
        ("aggkit:v", "v"),
        ("aggkit:0.", "0."),
    ]
    for image, version_str in fail_cases:
        expect.fails(
            lambda: aggkit.get_agglayer_endpoint(plan, image),
            "Invalid aggkit version format: '{}'. Expected format is 'vX.Y.Z' or 'X.Y.Z'".format(
                version_str
            ),
        )
