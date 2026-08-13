# Snapshot

Two flavors:

- **default** — geth/lighthouse L1 (optionally with an op-reth L2). Full documentation:
  [L1 Snapshot Tool](../docs/docs/advanced/snapshot.md).
- **`--flavor anvil-aggkit`** — anvil L1 + two anvil L2s + agglayer + aggkit ×2 (each
  also serving the bridge REST API in-process) + aggkit-proxy + the [Agglayer Dev
  UI](https://github.com/agglayer/agglayer-dev-ui), captured into a self-contained,
  9-service `docker-compose.yml` + `summary.json` bundle, plus a
  `docker-compose.mounts.yml` variant with an `AGGKIT_IMAGE`/`AGGLAYER_IMAGE`
  override seam for consumers who want to run their own build against the captured
  state. Consumable by dev-ui's hermetic CI, aggkit, or agglayer. Full documentation:
  [Anvil Devnet Snapshot](../docs/docs/advanced/anvil-devnet-snapshot.md). Built
  and published to GHCR by `.github/workflows/snapshot-devui.yml`.

See the [docs site](https://docs.polygon.technology) for the latest version.
