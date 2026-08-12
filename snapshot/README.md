# Snapshot

Two flavors:

- **default** — geth/lighthouse L1 (optionally with an op-reth L2). Full documentation:
  [L1 Snapshot Tool](../docs/docs/advanced/snapshot.md).
- **`--flavor anvil-aggkit`** — anvil L1 + two anvil L2s + agglayer + aggkit ×2 +
  aggkit-proxy + the [Agglayer Dev UI](https://github.com/agglayer/agglayer-dev-ui),
  captured into a self-contained `docker-compose.yml` + `summary.json` bundle for
  `agglayer/agglayer-dev-ui`'s hermetic CI. Full documentation:
  [Anvil-Flavor DevUI Snapshot](../docs/docs/advanced/anvil-devui-snapshot.md). Built
  and published to GHCR by `.github/workflows/snapshot-devui.yml`.

See the [docs site](https://docs.polygon.technology) for the latest version.
