# Port identifiers and numbers.
HTTP_RPC_PORT_ID = "rpc"
HTTP_RPC_PORT_NUMBER = 8545

WS_RPC_PORT_ID = "ws-rpc"
WS_RPC_PORT_NUMBER = 8546

# ------------------------------------------------------------------------------
# S11b HyperPay port map.
#
# Every number below is COPIED FROM `hyperpay-e2e/src/ports.rs` (port_base
# 50000), which is what `hp-stack materialize` renders into the generated
# config. They are duplicated here only because kurtosis needs `PortSpec`
# numbers at plan time, before the generator has run; they are never a second
# source of truth. `hyperpay-e2e/src/ports.rs`'s own docs explain why nothing
# in that map may be an implicit default (three real collisions).
#
# If a number here disagrees with the generated config, the service binds one
# port and kurtosis publishes another — so T5's handshake script re-reads the
# generated `endpoints.json` and compares, rather than trusting this block.
# ------------------------------------------------------------------------------
HYPERPAY_PORT_BASE = 50000

# The bridge shard: JSON-RPC (`eth_*`, the chain's RPC as far as aggkit,
# aggoracle and bridgesync are concerned), the gRPC pull API the aggregator
# reads SBPs from, and /metrics + /health.
# The port ID must be the fork-wide `rpc` id, not a HyperPay-specific one:
# generic consumers look the L2 RPC up by that id on the `l2_rpc_name` service
# (e.g. `src/additional_services/test_runner.star::_get_l2_rpc_url`, which
# `fail()`s if it is absent). Only the NUMBER is HyperPay's.
HYPERPAY_BRIDGE_RPC_PORT_ID = HTTP_RPC_PORT_ID
HYPERPAY_BRIDGE_RPC_PORT_NUMBER = HYPERPAY_PORT_BASE + 340
HYPERPAY_BRIDGE_PROVER_PORT_ID = "bridge-prover"
HYPERPAY_BRIDGE_PROVER_PORT_NUMBER = HYPERPAY_PORT_BASE + 330
HYPERPAY_BRIDGE_OPS_PORT_ID = "bridge-ops"
HYPERPAY_BRIDGE_OPS_PORT_NUMBER = HYPERPAY_PORT_BASE + 341

# The aggregator: the `aggkit.prover.v1.AggchainProofService` gRPC facade
# aggsender talks to directly (there is no aggkit-prover for this flavour),
# plus /metrics.
HYPERPAY_AGGREGATOR_GRPC_PORT_ID = "grpc"
HYPERPAY_AGGREGATOR_GRPC_PORT_NUMBER = HYPERPAY_PORT_BASE + 400
HYPERPAY_AGGREGATOR_METRICS_PORT_ID = "metrics"
HYPERPAY_AGGREGATOR_METRICS_PORT_NUMBER = HYPERPAY_PORT_BASE + 401

# NATS (the receipt bus) and Redis (the gateway's settle cache). One of each
# per stack, on their standard ports.
HYPERPAY_NATS_PORT_ID = "nats"
HYPERPAY_NATS_PORT_NUMBER = 4222
HYPERPAY_REDIS_PORT_ID = "redis"
HYPERPAY_REDIS_PORT_NUMBER = 6379


def hyperpay_shard_ports(shard_index):
    """One payment shard's ports — `ports.rs::shard_ports(50000, index)`.

    `shard_index` is 0-based and is NOT the genesis shard prefix, exactly as in
    `ports.rs` (for the shipped presets the two coincide).
    """
    base = HYPERPAY_PORT_BASE + 100 + shard_index * 100
    return struct(
        sequencer_ingress=base,
        sequencer_ops=base + 1,
        da_listen=base + 10,
        da_metrics=base + 11,
        replica_listen=base + 20,
        replica_metrics=base + 21,
        shard_prover_listen=base + 30,
    )


def hyperpay_gateway_ports(gateway_index):
    """One gateway's ports — `ports.rs::gateway_ports(index)`.

    Deliberately NOT derived from `HYPERPAY_PORT_BASE`: `ports.rs` gives the
    gateways their own numbering (8402/8545/9102, +10 per gateway).
    """
    step = gateway_index * 10
    return struct(
        http=8402 + step,
        rpc=8545 + step,
        admin=9102 + step,
    )
