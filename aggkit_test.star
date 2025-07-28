aggkit = import_module("aggkit.star")


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
    valid_cases = [
        ("ghcr.io/agglayer/aggkit:0.5.0-beta1", "grpc"),
        ("ghcr.io/agglayer/aggkit:local", "grpc"),
        ("ghcr.io/agglayer/aggkit:1.0.0", "grpc"),
        ("ghcr.io/agglayer/aggkit:0.2.14", "readrpc"),
        ("ghcr.io/agglayer/aggkit:0.1", "readrpc"),
        ("ghcr.io/agglayer/aggkit:0", "readrpc"),
    ]
    for image, expected in valid_cases:
        result = aggkit._get_agglayer_endpoint(image)
        expect.eq(result, expected)
