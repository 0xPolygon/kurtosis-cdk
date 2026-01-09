anvil = import_module("./anvil.star")
constants = import_module("../package_io/constants.star")
ethereum = import_module("./ethereum.star")


def launch(plan, args):
    l1_engine = args.get("l1_engine")
    if l1_engine == constants.L1_ENGINE.geth:
        result = ethereum.run(plan, args)
        # private_key = wallet.derive_private_key(plan, mnemonic)
        return struct(
            chain_id=result.network_id,
            rpc_url=result.all_participants[0].el_context.rpc_http_url,
            all_participants=result.all_participants,
        )
    elif l1_engine == constants.L1_ENGINE.anvil:
        rpc_url = anvil.run(plan, args)
        return struct(
            chain_id=str(args["l1_chain_id"]),
            rpc_url=rpc_url,
            all_participants=[],
        )
    else:
        fail("Unsupported L1 engine type '%s'" % l1_engine)
