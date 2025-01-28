FROM debian:stable-slim as builder

# WARNING (DL3008): Pin versions in apt get install.
# hadolint ignore=DL3008
RUN apt-get update \
  && apt-get --yes upgrade \
  && apt-get install --yes --no-install-recommends libssl-dev ca-certificates jq git curl make \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  # Pull kurtosis-cdk package.
  && git clone --branch v0.2.27 https://github.com/0xPolygon/kurtosis-cdk \
  # Pull kurtosis-cdk dependencies.
  # The package has other dependencies (blockscout, prometheus and grafana) but they shouldn't be used when testing the package with Antithesis.
  && git clone --branch 4.4.0 https://github.com/ethpandaops/ethereum-package \
  && git clone --branch 1.2.0 https://github.com/ethpandaops/optimism-package \
  # Make the kurtosis-cdk package reference locally pulled dependencies.
  && sed -i '$ a\\nreplace:\n    github.com/ethpandaops/ethereum-package: ../ethereum-package\n    github.com/ethpandaops/optimism-package: ../optimism-package\n    github.com/kurtosis-tech/redis-package: ../redis-package\n    github.com/kurtosis-tech/postgres-package: ../postgres-package\n    github.com/bharath-123/db-adminer-package: ../db-adminer-package\n    github.com/kurtosis-tech/prometheus-package: ../prometheus-package' /kurtosis-cdk/kurtosis.yml \
  # Pull ethereum package dependencies.
  && git clone --branch main https://github.com/kurtosis-tech/prometheus-package \
  && git clone --branch main https://github.com/kurtosis-tech/postgres-package \
  && git clone --branch main https://github.com/bharath-123/db-adminer-package \
  && git clone --branch main https://github.com/kurtosis-tech/redis-package \
  # Make the ethereum package reference locally pulled dependencies.
  && sed -i '$ a\\nreplace:\n    github.com/kurtosis-tech/prometheus-package: ../prometheus-package\n    github.com/kurtosis-tech/postgres-package: ../postgres-package\n    github.com/bharath-123/db-adminer-package: ../db-adminer-package\n    github.com/kurtosis-tech/redis-package: ../redis-package' /ethereum-package/kurtosis.yml \
  # Pull optimism package dependencies.
  # It relies on the ethereum package which is already pulled.
  && sed -i '$ a\\nreplace:\n    github.com/ethpandaops/ethereum-package: ../ethereum-package' /optimism-package/kurtosis.yml


FROM scratch
LABEL author="devtools@polygon.technology"
LABEL description="Antithesis config image for kurtosis-cdk"

COPY --from=builder /kurtosis-cdk /kurtosis-cdk
COPY --from=builder /ethereum-package /ethereum-package
COPY --from=builder /prometheus-package /prometheus-package
COPY --from=builder /postgres-package /postgres-package
COPY --from=builder /db-adminer-package /db-adminer-package
COPY --from=builder /redis-package /redis-package
COPY --from=builder /optimism-package /optimism-package
