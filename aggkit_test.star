aggkit = import_module("aggkit.star")


def test_get_aggkit_version(plan):
    """Test version extraction logic from aggkit image tags."""

    # Test cases for invalid aggkit image tags.
    invalid_cases = [
        "aggkit",
    ]
    for image in invalid_cases:
        expect.fails(
            lambda: aggkit.get_aggkit_version(image),
            "Aggkit image '{}' does not have a tag.".format(image),
        )

    # Test cases for valid aggkit image tags.
    valid_cases = [
        ("registry.example.com/aggkit:0.1.5-beta", "0.1.5"),
        ("registry.example.com/aggkit:xyz0.1.5-rc.1", "0.1.5"),
        ("aggkit:0.1.5-beta", "0.1.5"),
        ("aggkit:xyz0.1.5-rc.1", "0.1.5"),
        ("registry.example.com/aggkit:0.2.0-beta", "0.2.0"),
        ("registry.example.com/aggkit:xyz0.2.0-rc.1", "0.2.0"),
        ("aggkit:0.2.0-beta", "0.2.0"),
        ("aggkit:xyz0.2.0-rc.1", "0.2.0"),
        ("registry.example.com/aggkit:6-beta", "6"),
        ("registry.example.com/aggkit:xyz6-rc.1", "6"),
        ("aggkit:6-beta", "6"),
        ("aggkit:xyz6-rc.1", "6"),
        ("aggkit:latest", ""),
        ("aggkit:main", ""),
        ("aggkit:local", ""),
        ("aggkit:", ""),
        ("aggkit:xyz", ""),
        ("aggkit:0.", "0."),
    ]
    for image, tag in valid_cases:
        result = aggkit.get_aggkit_version(image)
        expect.eq(result, tag)


def test_get_agglayer_endpoint(plan):
    """Test version comparison logic for grpc vs readrpc."""

    # Test cases for versions that should return "readrpc" (< 0.3.0).
    readrpc_cases = [
        "0",
        "0.",
        "0.1",
        "0.1.5",
        "0.1.5.",
        "0.2.0",
        "0.2.15",
    ]
    for version in readrpc_cases:
        result = aggkit.get_agglayer_endpoint(version)
        expect.eq(result, "readrpc")

    # Test cases for versions that should return "grpc" (>= 0.3.0).
    grpc_cases = [
        "0.3",
        "0.3.",
        "0.3.0",
        "0.3.1",
        "0.3.1.",
        "1",
        "1.15",
        "2.16.2",
    ]
    for version in grpc_cases:
        result = aggkit.get_agglayer_endpoint(version)
        expect.eq(result, "grpc")

    # Tests case that should fail due to invalid version format.
    invalid_cases = [
        "",
        "xyz",
        "xyz0.3.1",
        "0.3.1xyz",
        "0.3.1-rc.1",
        "0.3.1+build",
    ]
    for version in invalid_cases:
        expect.fails(
            lambda: aggkit.get_agglayer_endpoint(version),
            "Invalid aggkit version format",
        )
