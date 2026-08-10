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
    # _aggkit_version_gte, which parses major/minor as integers and compares
    # them as a tuple, ordering correctly regardless of digit count.
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


def test_aggkit_version_gte_legacy_bridge_addr(plan):
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
    # _aggkit_version_gte instead parses major/minor as integers and compares
    # them as a tuple, which orders correctly regardless of digit count.
    # aggkit.star derives the legacy-polygonBridgeAddr flag as
    # `not _aggkit_version_gte(image, 0, 8)`, so `expect_legacy` below is the
    # negation of the raw gte(0, 8) result.
    cases = [
        ("ghcr.io/agglayer/aggkit:0.11.0-rc4", False),  # the bug case
        ("ghcr.io/agglayer/aggkit:0.9.0-rc3", False),
        ("ghcr.io/agglayer/aggkit:0.7.5", True),
        ("ghcr.io/agglayer/aggkit:0.4.5", True),
        ("ghcr.io/agglayer/aggkit:0.8", False),  # boundary: not < 0.8
        ("ghcr.io/agglayer/aggkit:1.0.0", False),
        ("ghcr.io/agglayer/aggkit:local", False),
    ]
    for image, expect_legacy in cases:
        result = not aggkit._aggkit_version_gte(image, 0, 8)
        expect.eq(result, expect_legacy)

    # NOTE on fallback semantics: unlike this package's earlier
    # _parse_aggkit_major_minor helper (which treated any non-numeric,
    # non-"local" CI build tag -- e.g.
    # "develop_2026_08_03_13_20_56c849c" -- as (999, 9), i.e. "assume
    # latest"), _aggkit_version_gte falls back to (0, 0) for such tags, i.e.
    # "assume oldest" (only the literal "local" tag is special-cased to
    # "latest"). This package only ever pins numeric release tags in
    # practice (see params-aggkit-l2l2-run1.yml / run2.yml), so the fallback
    # path is not exercised by real deployments; documented here so a future
    # non-numeric CI tag isn't a surprise.
    expect.eq(
        aggkit._aggkit_version_gte(
            "ghcr.io/agglayer/aggkit:develop_2026_08_03_13_20_56c849c", 0, 8
        ),
        False,
    )
