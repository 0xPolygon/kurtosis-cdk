anvil = import_module("./anvil.star")
constants = import_module("../package_io/constants.star")
ethereum = import_module("./ethereum.star")


def launch(plan, args):
    l1_engine = args.get("l1_engine")
    if l1_engine == constants.L1_ENGINE.geth:
        ethereum.run(plan, args)
    elif l1_engine == constants.L1_ENGINE.anvil:
        anvil.run(plan, args)
    else:
        fail("Unsupported L1 engine type '%s'" % l1_engine)
