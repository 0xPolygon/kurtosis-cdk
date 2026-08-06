aggkit_package = import_module("../shared/aggkit.star")
constants = import_module("../../package_io/constants.star")
hyperpay_vkey = import_module("../../vkey/hyperpay.star")
ports_package = import_module("../shared/ports.star")

# Where the generated config tree is mounted in EVERY HyperPay service.
#
# This must equal the `--out` given to `hp-stack materialize`, because the
# generated files reference their own absolute paths (a DA config's
# `data_dir = "/out/data/da-0"`, a gateway config's `genesis_path`). The fork
# mounts the artifact at the same path it was generated at and changes
# nothing inside it — ADR-010: "kurtosis consumes the same generated config,
# never a hand-written one".
CONFIG_MOUNT = "/out"

# The receipt bus and the gateway settle cache. Pinned to the SAME tags the
# host stack's supervisor uses (`hyperpay-e2e/src/docker.rs`: NATS_IMAGE,
# REDIS_IMAGE) so the enclave and a developer's `hp-stack up` differ in
# orchestration only.
NATS_IMAGE = "nats:2.14.4"
REDIS_IMAGE = "redis:7.4.10"

# Trap T-c, applied to every RPC/gRPC port in this file. HyperPay components
# do real work before they bind (store recovery, genesis validation, DA
# catch-up), and the precedent measured 45–60s for the analogous startup.
# `wait` makes `add_service` block until the port actually serves, so aggkit,
# aggoracle and the bridge service cannot start first and crash on
# connection-refused.
READY_WAIT = "180s"


def _suffix(args):
    return args["deployment_suffix"]


def service_names(args):
    """Every HyperPay service name, in one place.

    These are also the enclave DNS names. THEY ARE LOAD-BEARING: see the
    networking note at the bottom of this file — when the generator grows a
    kurtosis net mode, the names it emits must be exactly these.
    """
    suffix = _suffix(args)
    shards = args["hyperpay_shard_count"]
    gateways = args["hyperpay_gateway_count"]
    return struct(
        # The bridge shard is also the chain's JSON-RPC endpoint, so its name
        # comes from L2_RPC_MAPPING rather than being spelled again here.
        bridge_shard=args["l2_rpc_name"] + suffix,
        aggregator="hyperpay-aggregator" + suffix,
        nats="hyperpay-nats" + suffix,
        redis="hyperpay-redis" + suffix,
        das=["hyperpay-da-{}{}".format(i, suffix) for i in range(shards)],
        sequencers=["hyperpay-sequencer-{}{}".format(i, suffix) for i in range(shards)],
        replicas=["hyperpay-replica-{}{}".format(i, suffix) for i in range(shards)],
        shard_provers=[
            "hyperpay-shard-prover-{}{}".format(i, suffix) for i in range(shards)
        ],
        gateways=["hyperpay-gateway-{}{}".format(i, suffix) for i in range(gateways)],
    )


def materialize(plan, args):
    """Generate every HyperPay config, ONCE, with the hyperpay CLI.

    The whole `<out>` tree (`config/`, `env/`, `genesis/`, `endpoints.json`)
    becomes one files artifact that every service below mounts verbatim. This
    is the only place config comes from: there is no template, no
    `render_templates`, and no HyperPay config key anywhere in this fork.

    Runs inside `hyperpay_node_image`, which bakes the harness presets and the
    topology profiles at `$HYPERPAY_WORKSPACE_ROOT` (`/opt/hyperpay`) — the
    compile-time workspace root the host build uses does not exist in a
    container, so `materialize` would otherwise fail looking for presets. See
    `hyperpay-e2e/src/plan.rs`.
    """
    profile = args["hyperpay_stack_profile"]
    result = plan.run_sh(
        name="hyperpay-materialize",
        description="Generating HyperPay config for profile " + profile,
        image=args["hyperpay_node_image"],
        run="hp-stack materialize --profile {} --out {}".format(profile, CONFIG_MOUNT),
        store=[
            StoreSpec(
                src=CONFIG_MOUNT,
                name="hyperpay-config" + _suffix(args),
            )
        ],
    )
    return result.files_artifacts[0]


def launch(
    plan,
    args,
    contract_setup_addresses,
    sovereign_contract_setup_addresses,
    deployment_stages,
):
    """Deploy the full HyperPay payment fabric, then aggkit on top of it.

    Shape (`mvp/E2E_KURTOSIS.md` §1 in the hyperpay repo): one bridge shard;
    per payment shard a DA server, a sequencer and a read replica (plus a
    shard prover when the settlement plane is on); N gateways; the aggregator;
    NATS; Redis. There is no EVM, no geth/OP stack and no L2 genesis step —
    the bridge/GER "contracts" are native facades at HyperPay's own genesis
    addresses (ADR-007), which is why `hp-stack facades` exists.

    Ownership boundary (ADR-011): everything below is topology wiring — image
    refs, service names, ports, mount paths, and addresses that come out of
    the L1 contract deploy. No behaviour, no config authoring.
    """
    names = service_names(args)

    # The values aggkit, the aggoracle and the bridge service need that only
    # HyperPay can answer: its own genesis facade addresses, plus the
    # aggregator's gRPC endpoint. Read once, here, and threaded into the
    # template data as `hyperpay_*` -- never spelled out in any template.
    template_args = {
        "hyperpay_bridge_address": hyperpay_vkey.get_facade_address(
            plan,
            args["hyperpay_node_image"],
            args["hyperpay_stack_profile"],
            "bridge",
        ),
        "hyperpay_ger_manager_address": hyperpay_vkey.get_facade_address(
            plan,
            args["hyperpay_node_image"],
            args["hyperpay_stack_profile"],
            "ger-manager",
        ),
        "hyperpay_aggregator_grpc_url": "{}:{}".format(
            names.aggregator,
            ports_package.HYPERPAY_AGGREGATOR_GRPC_PORT_NUMBER,
        ),
    }
    args = args | template_args

    config_artifact = materialize(plan, args)
    files = {CONFIG_MOUNT: config_artifact}
    settlement = args["hyperpay_settlement"]

    plan.print("Deploying the HyperPay receipt bus and settle cache")
    _add_nats(plan, args, names, files)
    _add_redis(plan, args, names, files)

    plan.print("Deploying HyperPay payment shards")
    for i in range(args["hyperpay_shard_count"]):
        _add_payment_shard(plan, args, names, files, i, settlement)

    plan.print("Deploying the HyperPay bridge shard")
    _add_bridge_shard(plan, args, names, files, contract_setup_addresses)

    plan.print("Deploying HyperPay gateways")
    for i in range(args["hyperpay_gateway_count"]):
        _add_gateway(plan, args, names, files, i)

    if settlement:
        plan.print("Deploying the HyperPay aggregator")
        _add_aggregator(plan, args, names, files)
    else:
        # Named, not silent: without the aggregator there is no
        # AggchainProofService for aggsender to call, so nothing can settle.
        # `hyperpay_settlement` is False only until T6's `settlement` profile
        # exists to generate the prover/aggregator configs.
        plan.print(
            "HyperPay settlement plane DISABLED (hyperpay_settlement=false): no shard provers, "
            + "no aggregator, so no certificate can be produced. Set it to true once the "
            + "hyperpay repo's `settlement` topology profile exists (S11b T6)."
        )

    rpc_url = "http://{}:{}".format(
        names.bridge_shard,
        ports_package.HYPERPAY_BRIDGE_RPC_PORT_NUMBER,
    )

    plan.print("Deploying aggkit infrastructure")
    aggkit_bridge_url = aggkit_package.run(
        plan,
        args,
        contract_setup_addresses,
        sovereign_contract_setup_addresses,
        deployment_stages,
    )

    return struct(
        rpc_url=rpc_url,
        aggkit_bridge_url=aggkit_bridge_url,
        # Merged into `args` by src/chain/launcher.star so the
        # zkevm-bridge-service template (which does not receive `args`) can see
        # the same HyperPay-owned values aggkit's does.
        template_args=template_args,
    )


def _add_nats(plan, args, names, files):
    # `-js`: JetStream, which the receipt bus needs for explicit acks (the
    # host supervisor passes the same flag — `hyperpay-e2e/src/docker.rs`).
    plan.add_service(
        name=names.nats,
        config=ServiceConfig(
            image=NATS_IMAGE,
            ports={
                ports_package.HYPERPAY_NATS_PORT_ID: PortSpec(
                    ports_package.HYPERPAY_NATS_PORT_NUMBER,
                    wait=READY_WAIT,
                ),
            },
            cmd=["-js"],
        ),
    )


def _add_redis(plan, args, names, files):
    plan.add_service(
        name=names.redis,
        config=ServiceConfig(
            image=REDIS_IMAGE,
            ports={
                ports_package.HYPERPAY_REDIS_PORT_ID: PortSpec(
                    ports_package.HYPERPAY_REDIS_PORT_NUMBER,
                    wait=READY_WAIT,
                ),
            },
        ),
    )


def _add_payment_shard(plan, args, names, files, index, settlement):
    """One payment shard: DA server, sequencer, read replica, shard prover.

    File names use the shard INDEX. `hp-stack materialize` names them by the
    genesis shard PREFIX (`config/da-<prefix>.toml`), and for every preset
    that ships the two coincide (prefix 0, 1, … in
    `hyperpay-harness/presets/genesis-<n>shard.toml`). T5's handshake script
    re-reads the generated `endpoints.json` rather than trusting that.
    """
    ports = ports_package.hyperpay_shard_ports(index)
    image = args["hyperpay_node_image"]

    # DA server: the shard's durable block store, config-file driven.
    plan.add_service(
        name=names.das[index],
        config=ServiceConfig(
            image=image,
            ports={
                "da": PortSpec(ports.da_listen, wait=READY_WAIT),
                "metrics": PortSpec(ports.da_metrics, application_protocol="http"),
            },
            entrypoint=["/usr/local/bin/hyperpay-da-server"],
            cmd=["--config", "{}/config/da-{}.toml".format(CONFIG_MOUNT, index)],
            files=files,
            env_vars={"RUST_LOG": "info"},
        ),
    )

    # Sequencer: environment-driven, and the environment is GENERATED
    # (`env/sequencer-<n>.env`). Sourcing the generated file is what keeps the
    # sequencer's keys and endpoints out of this fork — spelling those
    # variables here would be exactly the hand-authored config ADR-010
    # forbids. `set -a` exports what the file assigns; `exec` keeps the
    # binary as PID 1 so kurtosis' signals reach it.
    plan.add_service(
        name=names.sequencers[index],
        config=ServiceConfig(
            image=image,
            ports={
                "ingress": PortSpec(ports.sequencer_ingress, wait=READY_WAIT),
                "ops": PortSpec(ports.sequencer_ops, application_protocol="http"),
            },
            entrypoint=["/bin/sh", "-c"],
            cmd=[
                "set -a; . {}/env/sequencer-{}.env; set +a; exec hyperpay-sequencer".format(
                    CONFIG_MOUNT, index
                )
            ],
            files=files,
            env_vars={"RUST_LOG": "info"},
        ),
    )

    plan.add_service(
        name=names.replicas[index],
        config=ServiceConfig(
            image=image,
            ports={
                "replica": PortSpec(ports.replica_listen, wait=READY_WAIT),
                "metrics": PortSpec(ports.replica_metrics, application_protocol="http"),
            },
            entrypoint=["/usr/local/bin/hyperpay-read-replica"],
            cmd=["--config", "{}/config/replica-{}.toml".format(CONFIG_MOUNT, index)],
            files=files,
            env_vars={"RUST_LOG": "info"},
        ),
    )

    if settlement:
        # The witness factory. Its config comes from the `settlement` profile
        # (S11b T6) — with `hyperpay_settlement=false` this service is not
        # added at all, rather than added and left crash-looping on a missing
        # file.
        plan.add_service(
            name=names.shard_provers[index],
            config=ServiceConfig(
                image=image,
                ports={
                    "prover": PortSpec(ports.shard_prover_listen, wait=READY_WAIT),
                },
                entrypoint=["/usr/local/bin/hyperpay-shard-prover"],
                cmd=["{}/config/shard-prover-{}.toml".format(CONFIG_MOUNT, index)],
                files=files,
                env_vars={"RUST_LOG": "info"},
            ),
        )


def _add_bridge_shard(plan, args, names, files, contract_setup_addresses):
    """The bridge shard — the chain's JSON-RPC surface and its LET producer.

    Two things here are NOT generated config, and cannot be:

    * `HYPERPAY_BRIDGE_GER_UPDATER_ADDRESS` is an **L1 deploy output**. aggoracle
      reads `globalExitRootUpdater()` AT STARTUP and refuses to run if it is
      not its own signer (trap T-n), so this must be the aggkit aggoracle EOA
      — a value that does not exist until the contracts are deployed, i.e.
      after `hp-stack materialize` has already run. It is an address, which is
      exactly what the ownership boundary allows this fork to pass.
    * The rest of the bridge shard's environment IS generated
      (`env/bridge-shard.env`, produced by the `settlement` profile) and is
      sourced, not restated. Until that profile exists this service will fail
      at run time on the missing file, loudly and by name.
    """
    ports = struct(
        rpc=ports_package.HYPERPAY_BRIDGE_RPC_PORT_NUMBER,
        prover=ports_package.HYPERPAY_BRIDGE_PROVER_PORT_NUMBER,
        ops=ports_package.HYPERPAY_BRIDGE_OPS_PORT_NUMBER,
    )
    plan.add_service(
        name=names.bridge_shard,
        config=ServiceConfig(
            image=args["hyperpay_node_image"],
            ports={
                ports_package.HYPERPAY_BRIDGE_RPC_PORT_ID: PortSpec(
                    ports.rpc,
                    application_protocol="http",
                    wait=READY_WAIT,
                ),
                ports_package.HYPERPAY_BRIDGE_PROVER_PORT_ID: PortSpec(
                    ports.prover,
                    application_protocol="grpc",
                    wait=READY_WAIT,
                ),
                ports_package.HYPERPAY_BRIDGE_OPS_PORT_ID: PortSpec(
                    ports.ops,
                    application_protocol="http",
                ),
            },
            entrypoint=["/bin/sh", "-c"],
            cmd=[
                "set -a; . {}/env/bridge-shard.env; set +a; exec hyperpay-bridge-shard".format(
                    CONFIG_MOUNT
                )
            ],
            files=files,
            env_vars={
                "RUST_LOG": "info",
                # Trap T-n. Must equal the aggkit aggoracle EOA or aggoracle
                # refuses to start.
                "HYPERPAY_BRIDGE_GER_UPDATER_ADDRESS": args["l2_aggoracle_address"],
            },
        ),
    )


def _add_gateway(plan, args, names, files, index):
    ports = ports_package.hyperpay_gateway_ports(index)
    plan.add_service(
        name=names.gateways[index],
        config=ServiceConfig(
            image=args["hyperpay_node_image"],
            ports={
                "http": PortSpec(
                    ports.http, application_protocol="http", wait=READY_WAIT
                ),
                "rpc": PortSpec(
                    ports.rpc, application_protocol="http", wait=READY_WAIT
                ),
                "admin": PortSpec(ports.admin, application_protocol="http"),
            },
            # The gateway takes its config path as a positional argument.
            entrypoint=["/usr/local/bin/hyperpay-gateway"],
            cmd=["{}/config/gateway-{}.toml".format(CONFIG_MOUNT, index)],
            files=files,
            env_vars={"RUST_LOG": "info"},
        ),
    )


def _add_aggregator(plan, args, names, files):
    """The aggregator: the `AggchainProofService` aggsender calls.

    There is no aggkit-prover for this flavour — the aggregator serves the
    unmodified `aggkit.prover.v1` contract itself, which is why the aggkit
    config template points `AggchainProofURL` at this service.
    """
    plan.add_service(
        name=names.aggregator,
        config=ServiceConfig(
            image=args["hyperpay_node_image"],
            ports={
                ports_package.HYPERPAY_AGGREGATOR_GRPC_PORT_ID: PortSpec(
                    ports_package.HYPERPAY_AGGREGATOR_GRPC_PORT_NUMBER,
                    application_protocol="grpc",
                    wait=READY_WAIT,
                ),
                ports_package.HYPERPAY_AGGREGATOR_METRICS_PORT_ID: PortSpec(
                    ports_package.HYPERPAY_AGGREGATOR_METRICS_PORT_NUMBER,
                    application_protocol="http",
                ),
            },
            entrypoint=["/usr/local/bin/hyperpay-aggregator"],
            cmd=["{}/config/aggregator.toml".format(CONFIG_MOUNT)],
            files=files,
            env_vars={"RUST_LOG": "info"},
        ),
    )


# ------------------------------------------------------------------------------
# KNOWN GAP FOR T5 — the generated config binds loopback
#
# `hp-stack materialize` emits every PEER address as `127.0.0.1:<port>`
# (`HYPERPAY_DA_ENDPOINT`, `HYPERPAY_NATS_URL`, the replica's `da_endpoint`,
# the gateway's `redis.url` and its `[[shards]]` table, and all of
# `endpoints.json`), because the host supervisor runs the whole fabric as one
# process group. In an enclave each component is its own container, so a peer
# address of `127.0.0.1` resolves to the CALLER. A dry-run cannot see this:
# the plan interprets, the mounts are correct, and the services start — they
# just never connect.
#
# This is deliberately NOT worked around here (a Starlark-side rewrite of
# generated config is precisely what ADR-010 forbids). It is recorded in the
# hyperpay repo's `mvp/results/QUESTIONS.md` — "S11b (T4) — materialize's
# generated config binds loopback" — with two options, and T5 must land one
# BEFORE bring-up. The service names in `service_names()` above are the names
# the preferred option (a `--net kurtosis` mode in the generator) must emit.
# ------------------------------------------------------------------------------
