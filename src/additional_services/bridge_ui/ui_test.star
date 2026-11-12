ui = import_module("./ui.star")


def test_proxy_template_data_bridge_hub(plan):
    data = ui.get_proxy_template_data(
        {},
        "http://el-1:8545",
        "http://op-el:8545",
        "http://api:3001",
        "http://ui:80",
    )
    expect.eq(
        data,
        {
            "l1_rpc_url": "el-1:8545",
            "l2_rpc_url": "op-el:8545",
            "bridge_hub_api_url": "api:3001",
            "agglayer_dev_ui_url": "ui:80",
            "aggkit_backends": [],
            "l2_rpc_backends": [],
        },
    )


def test_proxy_template_data_aggkit_backend(plan):
    args = {
        "bridge_ui_l2_rpc_urls": [
            {"path_suffix": "-002", "url": "http://l2-anvil-002:8545"},
            {"path_suffix": "-001", "url": "http://l2-anvil-001:8545"},
        ]
    }
    data = ui.get_proxy_template_data(
        args,
        "http://anvil-001:8545",
        "http://l2-anvil-002:8545",
        None,
        None,
        aggkit_bridge_url="http://aggkit-proxy-001:8080",
    )
    expect.eq(
        data["aggkit_backends"],
        [{"path_suffix": "", "url": "aggkit-proxy-001:8080"}],
    )
    expect.eq(
        data["l2_rpc_backends"],
        [
            {"path_suffix": "-002", "url": "l2-anvil-002:8545"},
            {"path_suffix": "-001", "url": "l2-anvil-001:8545"},
        ],
    )
    # The bare /l2rpc route follows chain 1, not this run's own L2.
    expect.eq(data["l2_rpc_url"], "l2-anvil-001:8545")
    expect.eq(data["bridge_hub_api_url"], "")
    expect.eq(data["agglayer_dev_ui_url"], "")


def test_dev_ui_l2_chains(plan):
    args = {
        "l2_chain_id": 20201,
        "l2_network_id": 1,
        "bridge_ui_l2_rpc_urls": [
            {
                "path_suffix": "-001",
                "url": "http://l2-anvil-001:8545",
                "chain_id": 20201,
                "network_id": 1,
            },
            {"path_suffix": "-002", "url": "http://l2-anvil-002:8545"},
        ],
    }
    (chains, omitted) = ui.get_dev_ui_l2_chains(args, "http://own:8545")
    expect.eq(
        chains,
        [
            {
                "chain_key": "DEVNET_L2_001",
                "chain_id": 20201,
                "network_id": 1,
                "rpc_url": "http://l2-anvil-001:8545",
                "path_suffix": "-001",
            }
        ],
    )
    expect.eq(omitted, 1)


def test_dev_ui_l2_chains_falls_back_to_the_own_l2(plan):
    args = {"l2_chain_id": 20202, "l2_network_id": 2}
    (chains, omitted) = ui.get_dev_ui_l2_chains(args, "http://own:8545")
    expect.eq(
        chains,
        [
            {
                "chain_key": "DEVNET_L2",
                "chain_id": 20202,
                "network_id": 2,
                "rpc_url": "http://own:8545",
                "path_suffix": "",
            }
        ],
    )
    expect.eq(omitted, 0)
