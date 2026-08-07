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
    # Regression test for the version-gate bug: _get_agglayer_endpoint used to
    # compare _extract_aggkit_version's collapsed float (`version >= 0.3`).
    # That collapses "<major>.<minor>" into a single float, so "0.11" becomes
    # 0.11, which is numerically LESS than 0.3 even though minor version 11 is
    # ordinally newer than minor version 3. ghcr.io/agglayer/aggkit:0.11.0-rc4
    # is exactly the case that tripped this -- it wrongly returned "readrpc",
    # which breaks certificate settlement against agglayer. Now uses
    # _parse_aggkit_major_minor, which parses major/minor as integers and
    # compares them as a tuple, ordering correctly regardless of digit count.
    valid_cases = [
        ("ghcr.io/agglayer/aggkit:0.5.0-beta1", "grpc"),
        ("ghcr.io/agglayer/aggkit:local", "grpc"),
        ("ghcr.io/agglayer/aggkit:1.0.0", "grpc"),
        ("ghcr.io/agglayer/aggkit:0.11.0-rc4", "grpc"),  # the bug case
        ("ghcr.io/agglayer/aggkit:0.2.14", "readrpc"),
        ("ghcr.io/agglayer/aggkit:0.1", "readrpc"),
        ("ghcr.io/agglayer/aggkit:0", "readrpc"),
    ]
    for image, expected in valid_cases:
        result = aggkit._get_agglayer_endpoint(image)
        expect.eq(result, expected)


def test_render_legacy_bridge_addr(plan):
    # Regression test for the version-gate bug: the config.toml /
    # cdk-config.toml templates used to do `{{- if lt .aggkit_version "0.8" }}`
    # inside Go's text/template, comparing a value Kurtosis stringifies --
    # i.e. a LEXICOGRAPHIC string comparison, under which "0.11" < "0.8" is
    # (wrongly) true digit-by-digit. ghcr.io/agglayer/aggkit:0.11.0-rc4 is
    # exactly the case that tripped this.
    #
    # Moving the comparison into Starlark as a plain `aggkit_version < 0.8`
    # float comparison does NOT fix it: _extract_aggkit_version collapses
    # "<major>.<minor>" into a single float, so "0.11" becomes the float
    # 0.11, which is numerically LESS than 0.8 -- reproducing the exact same
    # bug one level down (verified empirically while building this test).
    # _render_legacy_bridge_addr instead parses major/minor as integers and
    # compares them as a tuple, which orders correctly regardless of digit
    # count.
    cases = [
        ("ghcr.io/agglayer/aggkit:0.11.0-rc4", False),  # the bug case
        ("ghcr.io/agglayer/aggkit:0.9.0-rc3", False),
        ("ghcr.io/agglayer/aggkit:0.7.5", True),
        ("ghcr.io/agglayer/aggkit:0.4.5", True),
        ("ghcr.io/agglayer/aggkit:0.8", False),  # boundary: not < 0.8
        ("ghcr.io/agglayer/aggkit:1.0.0", False),
        ("ghcr.io/agglayer/aggkit:local", False),
        ("ghcr.io/agglayer/aggkit:develop_2026_08_03_13_20_56c849c", False),
    ]
    for image, expect_legacy in cases:
        result = aggkit._render_legacy_bridge_addr(image)
        expect.eq(result, expect_legacy)
