FROM debian:stable-slim as builder

RUN apt-get update \
  && apt-get --yes upgrade \
  && apt-get install --yes --no-install-recommends libssl-dev ca-certificates jq git curl make \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Pull kurtosis-cdk package.
RUN git clone --branch v0.2.27 https://github.com/0xPolygon/kurtosis-cdk

# Pull kurtosis-cdk package dependencies.
# The package has other dependencies (blockscout, prometheus, grafana, etc.) but they shouldn't be used when testing the package with Antithesis.
RUN git clone --branch 4.4.0 https://github.com/ethpandaops/ethereum-package
RUN sed -i '$ a\\nreplace:\n    github.com/kurtosis-tech/ethereum-package: ../ethereum-package' /kurtosis-cdk/kurtosis.yml

# Pull ethereum package dependencies.
RUN git clone --branch main https://github.com/kurtosis-tech/prometheus-package
RUN git clone --branch main https://github.com/kurtosis-tech/postgres-package
RUN git clone --branch main https://github.com/bharath-123/db-adminer-package
RUN git clone --branch main https://github.com/kurtosis-tech/redis-package
# Make the package reference locally pulled dependencies.
RUN sed -i '$ a\\nreplace:\n    github.com/kurtosis-tech/prometheus-package: ../prometheus-package\n    github.com/kurtosis-tech/postgres-package: ../postgres-package\n    github.com/bharath-123/db-adminer-package: ../db-adminer-package\n    github.com/kurtosis-tech/redis-package: ../redis-package' /ethereum-package/kurtosis.yml


FROM scratch

COPY --from=builder /kurtosis-cdk /kurtosis-cdk
COPY --from=builder /ethereum-package /ethereum-package
COPY --from=builder /prometheus-package /prometheus-package
COPY --from=builder /postgres-package /postgres-package
COPY --from=builder /db-adminer-package /db-adminer-package
COPY --from=builder /redis-package /redis-package
