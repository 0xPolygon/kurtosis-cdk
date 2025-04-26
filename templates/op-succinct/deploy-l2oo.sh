#!/usr/bin/env bash
export FOUNDRY_DISABLE_NIGHTLY_WARNING=1

pushd /opt/op-succinct || { echo "op-succinct directory doesn't exit"; exit 1; }

set -a
# shellcheck disable=SC1091
source /opt/op-succinct/.env
set +a

cat .env

RUST_LOG=info fetch-rollup-config --env-file .env 2> fetch-rollup-config.out

