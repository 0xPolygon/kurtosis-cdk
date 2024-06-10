const bridgeABIJson = '[{"inputs":[],"stateMutability":"nonpayable","type":"constructor"},{"inputs":[],"name":"AlreadyClaimed","type":"error"},{"inputs":[],"name":"AmountDoesNotMatchMsgValue","type":"error"},{"inputs":[],"name":"DestinationNetworkInvalid","type":"error"},{"inputs":[],"name":"EtherTransferFailed","type":"error"},{"inputs":[],"name":"FailedTokenWrappedDeployment","type":"error"},{"inputs":[],"name":"GasTokenNetworkMustBeZeroOnEther","type":"error"},{"inputs":[],"name":"GlobalExitRootInvalid","type":"error"},{"inputs":[],"name":"InvalidSmtProof","type":"error"},{"inputs":[],"name":"MerkleTreeFull","type":"error"},{"inputs":[],"name":"MessageFailed","type":"error"},{"inputs":[],"name":"MsgValueNotZero","type":"error"},{"inputs":[],"name":"NativeTokenIsEther","type":"error"},{"inputs":[],"name":"NoValueInMessagesOnGasTokenNetworks","type":"error"},{"inputs":[],"name":"NotValidAmount","type":"error"},{"inputs":[],"name":"NotValidOwner","type":"error"},{"inputs":[],"name":"NotValidSignature","type":"error"},{"inputs":[],"name":"NotValidSpender","type":"error"},{"inputs":[],"name":"OnlyEmergencyState","type":"error"},{"inputs":[],"name":"OnlyNotEmergencyState","type":"error"},{"inputs":[],"name":"OnlyRollupManager","type":"error"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint8","name":"leafType","type":"uint8"},{"indexed":false,"internalType":"uint32","name":"originNetwork","type":"uint32"},{"indexed":false,"internalType":"address","name":"originAddress","type":"address"},{"indexed":false,"internalType":"uint32","name":"destinationNetwork","type":"uint32"},{"indexed":false,"internalType":"address","name":"destinationAddress","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"},{"indexed":false,"internalType":"bytes","name":"metadata","type":"bytes"},{"indexed":false,"internalType":"uint32","name":"depositCount","type":"uint32"}],"name":"BridgeEvent","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint256","name":"globalIndex","type":"uint256"},{"indexed":false,"internalType":"uint32","name":"originNetwork","type":"uint32"},{"indexed":false,"internalType":"address","name":"originAddress","type":"address"},{"indexed":false,"internalType":"address","name":"destinationAddress","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"ClaimEvent","type":"event"},{"anonymous":false,"inputs":[],"name":"EmergencyStateActivated","type":"event"},{"anonymous":false,"inputs":[],"name":"EmergencyStateDeactivated","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint8","name":"version","type":"uint8"}],"name":"Initialized","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint32","name":"originNetwork","type":"uint32"},{"indexed":false,"internalType":"address","name":"originTokenAddress","type":"address"},{"indexed":false,"internalType":"address","name":"wrappedTokenAddress","type":"address"},{"indexed":false,"internalType":"bytes","name":"metadata","type":"bytes"}],"name":"NewWrappedToken","type":"event"},{"inputs":[],"name":"BASE_INIT_BYTECODE_WRAPPED_TOKEN","outputs":[{"internalType":"bytes","name":"","type":"bytes"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"WETHToken","outputs":[{"internalType":"contract TokenWrapped","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"activateEmergencyState","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint32","name":"destinationNetwork","type":"uint32"},{"internalType":"address","name":"destinationAddress","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"},{"internalType":"address","name":"token","type":"address"},{"internalType":"bool","name":"forceUpdateGlobalExitRoot","type":"bool"},{"internalType":"bytes","name":"permitData","type":"bytes"}],"name":"bridgeAsset","outputs":[],"stateMutability":"payable","type":"function"},{"inputs":[{"internalType":"uint32","name":"destinationNetwork","type":"uint32"},{"internalType":"address","name":"destinationAddress","type":"address"},{"internalType":"bool","name":"forceUpdateGlobalExitRoot","type":"bool"},{"internalType":"bytes","name":"metadata","type":"bytes"}],"name":"bridgeMessage","outputs":[],"stateMutability":"payable","type":"function"},{"inputs":[{"internalType":"uint32","name":"destinationNetwork","type":"uint32"},{"internalType":"address","name":"destinationAddress","type":"address"},{"internalType":"uint256","name":"amountWETH","type":"uint256"},{"internalType":"bool","name":"forceUpdateGlobalExitRoot","type":"bool"},{"internalType":"bytes","name":"metadata","type":"bytes"}],"name":"bridgeMessageWETH","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"bytes32","name":"leafHash","type":"bytes32"},{"internalType":"bytes32[32]","name":"smtProof","type":"bytes32[32]"},{"internalType":"uint32","name":"index","type":"uint32"}],"name":"calculateRoot","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"pure","type":"function"},{"inputs":[{"internalType":"uint32","name":"originNetwork","type":"uint32"},{"internalType":"address","name":"originTokenAddress","type":"address"},{"internalType":"address","name":"token","type":"address"}],"name":"calculateTokenWrapperAddress","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"bytes32[32]","name":"smtProofLocalExitRoot","type":"bytes32[32]"},{"internalType":"bytes32[32]","name":"smtProofRollupExitRoot","type":"bytes32[32]"},{"internalType":"uint256","name":"globalIndex","type":"uint256"},{"internalType":"bytes32","name":"mainnetExitRoot","type":"bytes32"},{"internalType":"bytes32","name":"rollupExitRoot","type":"bytes32"},{"internalType":"uint32","name":"originNetwork","type":"uint32"},{"internalType":"address","name":"originTokenAddress","type":"address"},{"internalType":"uint32","name":"destinationNetwork","type":"uint32"},{"internalType":"address","name":"destinationAddress","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"},{"internalType":"bytes","name":"metadata","type":"bytes"}],"name":"claimAsset","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"bytes32[32]","name":"smtProofLocalExitRoot","type":"bytes32[32]"},{"internalType":"bytes32[32]","name":"smtProofRollupExitRoot","type":"bytes32[32]"},{"internalType":"uint256","name":"globalIndex","type":"uint256"},{"internalType":"bytes32","name":"mainnetExitRoot","type":"bytes32"},{"internalType":"bytes32","name":"rollupExitRoot","type":"bytes32"},{"internalType":"uint32","name":"originNetwork","type":"uint32"},{"internalType":"address","name":"originAddress","type":"address"},{"internalType":"uint32","name":"destinationNetwork","type":"uint32"},{"internalType":"address","name":"destinationAddress","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"},{"internalType":"bytes","name":"metadata","type":"bytes"}],"name":"claimMessage","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"","type":"uint256"}],"name":"claimedBitMap","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"deactivateEmergencyState","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"depositCount","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"gasTokenAddress","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"gasTokenMetadata","outputs":[{"internalType":"bytes","name":"","type":"bytes"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"gasTokenNetwork","outputs":[{"internalType":"uint32","name":"","type":"uint32"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint8","name":"leafType","type":"uint8"},{"internalType":"uint32","name":"originNetwork","type":"uint32"},{"internalType":"address","name":"originAddress","type":"address"},{"internalType":"uint32","name":"destinationNetwork","type":"uint32"},{"internalType":"address","name":"destinationAddress","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"},{"internalType":"bytes32","name":"metadataHash","type":"bytes32"}],"name":"getLeafValue","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"pure","type":"function"},{"inputs":[],"name":"getRoot","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"token","type":"address"}],"name":"getTokenMetadata","outputs":[{"internalType":"bytes","name":"","type":"bytes"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint32","name":"originNetwork","type":"uint32"},{"internalType":"address","name":"originTokenAddress","type":"address"}],"name":"getTokenWrappedAddress","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"globalExitRootManager","outputs":[{"internalType":"contract IBasePolygonZkEVMGlobalExitRoot","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint32","name":"_networkID","type":"uint32"},{"internalType":"address","name":"_gasTokenAddress","type":"address"},{"internalType":"uint32","name":"_gasTokenNetwork","type":"uint32"},{"internalType":"contract IBasePolygonZkEVMGlobalExitRoot","name":"_globalExitRootManager","type":"address"},{"internalType":"address","name":"_polygonRollupManager","type":"address"},{"internalType":"bytes","name":"_gasTokenMetadata","type":"bytes"}],"name":"initialize","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint32","name":"leafIndex","type":"uint32"},{"internalType":"uint32","name":"sourceBridgeNetwork","type":"uint32"}],"name":"isClaimed","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"isEmergencyState","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"lastUpdatedDepositCount","outputs":[{"internalType":"uint32","name":"","type":"uint32"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"networkID","outputs":[{"internalType":"uint32","name":"","type":"uint32"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"polygonRollupManager","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint32","name":"originNetwork","type":"uint32"},{"internalType":"address","name":"originTokenAddress","type":"address"},{"internalType":"string","name":"name","type":"string"},{"internalType":"string","name":"symbol","type":"string"},{"internalType":"uint8","name":"decimals","type":"uint8"}],"name":"precalculatedWrapperAddress","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"name":"tokenInfoToWrappedToken","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"updateGlobalExitRoot","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"bytes32","name":"leafHash","type":"bytes32"},{"internalType":"bytes32[32]","name":"smtProof","type":"bytes32[32]"},{"internalType":"uint32","name":"index","type":"uint32"},{"internalType":"bytes32","name":"root","type":"bytes32"}],"name":"verifyMerkleProof","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"pure","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"wrappedTokenToTokenInfo","outputs":[{"internalType":"uint32","name":"originNetwork","type":"uint32"},{"internalType":"address","name":"originTokenAddress","type":"address"}],"stateMutability":"view","type":"function"}]';

const nets = {};
let accounts;

// https://docs.metamask.io/wallet/reference/json-rpc-api/
// https://docs.web3js.org/

document.getElementById('connectButton').addEventListener('click', async () => {

    //check if Metamask is installed
    if (window.ethereum) {
        document.getElementById('connectButton').disabled = true;
        document.getElementById('connectButton').style.display = 'none';
        const web3 = new Web3(window.ethereum);
        // Request the user to connect accounts (Metamask will prompt)

        await window.ethereum.request({ method: 'eth_requestAccounts' });

        // Get the connected accounts
        accounts = await web3.eth.getAccounts();

        // Display the connected account
        document.getElementById('connectedAccount').innerText = accounts[0];
        document.getElementById('dest_addr').value = accounts[0];
        document.getElementById('claim-account').value = accounts[0];
        console.log(accounts);
    } else {
        // Alert the user to download Metamask
        alert('Please download Metamask');
        return;
    }

    // reveal
    document.getElementById('deposit-form').style.display = 'block';

    let defaultL1Rpc = document.getElementById('l1-rpc-url').value;
    let defaultL2Rpc = document.getElementById('l2-rpc-url').value;
    let defaultBridgeService = document.getElementById('bridge-api-url').value;
    let bridgeAddress = document.getElementById('lxly-bridge-addr').value;

    document.getElementById('l1-rpc-url').disabled = true;
    document.getElementById('l2-rpc-url').disabled = true;
    document.getElementById('bridge-api-url').disabled = true;
    document.getElementById('lxly-bridge-addr').disabled = true;


    const l1web3 = new Web3(defaultL1Rpc);
    const l1ChainId = await l1web3.eth.getChainId();
    const l1Bridge = new l1web3.eth.Contract(JSON.parse(bridgeABIJson), bridgeAddress);
    const l1NetworkId = await l1Bridge.methods.networkID().call();

    nets[l1NetworkId] = {
        rpc: l1web3,
        rpcUrl: defaultL1Rpc,
        bridge: l1Bridge,
        chainId: l1ChainId,
        chainIdHex: new Web3().utils.toHex(l1ChainId),
        rollupId: l1NetworkId,
    };

    const l2web3 = new Web3(defaultL2Rpc);
    const l2ChainId = await l2web3.eth.getChainId();
    const l2Bridge = new l2web3.eth.Contract(JSON.parse(bridgeABIJson), bridgeAddress);
    const l2NetworkId = await l2Bridge.methods.networkID().call();

    nets[l2NetworkId] = {
        rpc: l2web3,
        rpcUrl: defaultL2Rpc,
        bridge: l2Bridge,
        chainId: l2ChainId,
        chainIdHex: new Web3().utils.toHex(l2ChainId),
        rollupId: l2NetworkId,
    };

    console.log(nets);
    console.log(l1ChainId, l2ChainId);
    console.log(l1NetworkId, l2NetworkId);

    async function refreshDeposits() {
        document.getElementById("deposits").innerHTML = 'loading...';
        let acc = document.getElementById('claim-account').value;
        const currentDeposits = await getAllDeposits(defaultBridgeService, acc);
        let df = renderDeposits(defaultBridgeService, bridgeAddress, currentDeposits);
        document.getElementById("deposits").innerHTML = '';
        document.getElementById("deposits").appendChild(df);
    }

    await refreshDeposits();
    document.getElementById('deposit-stuff').style.display = 'block';
    document.getElementById('refresh-deposits').addEventListener('click', refreshDeposits);

    document.getElementById("deposit-btn").addEventListener("click", async function () {
        let depositArgs = getDepositArgs();
        console.log(depositArgs);
        let originId = document.getElementById('orig_net').value;
        let curNet = nets[originId];
        if (!curNet) {
            alert(`The origin network ${originId} doesn't look familiar`);
            return;
        }
        let ba = curNet.bridge.methods.bridgeAsset;
        let txData = ba.apply(ba, depositArgs).encodeABI();
        console.log(txData);

        await addChain(curNet);
        await window.ethereum.request({ method: 'wallet_switchEthereumChain', params: [{"chainId": curNet.chainIdHex}] });

        let bridgeValue = "0x0";
        if (depositArgs[3] == "0x0000000000000000000000000000000000000000") {
            bridgeValue = new Web3().utils.toHex(depositArgs[2]);
        }

        const depositCall = {
            method: "eth_sendTransaction",
            params: [
                {
                    to: bridgeAddress,
                    from: accounts[0],
                    data: txData,
                    value: bridgeValue,
                }
            ]
        };

        console.log(depositCall);
        await window.ethereum.request(depositCall);

    });
});

function getDepositArgs() {
    const depositArgs = [];
    depositArgs.push(document.getElementById('dest_net').value);
    depositArgs.push(document.getElementById('dest_addr').value);
    depositArgs.push(BigInt(document.getElementById('amount').value));
    depositArgs.push(document.getElementById('orig_addr').value);
    depositArgs.push(document.getElementById('is_forced').checked);
    depositArgs.push(document.getElementById('metadata').value);
    return depositArgs;
}


async function addChain(net) {
    await window.ethereum.request({
        "method": "wallet_addEthereumChain",
        "params": [
            {
                "chainId": net.chainIdHex,
                "chainName": `TEST Network - ${net.chainId} - ${net.rollupId}`,
                "rpcUrls": [
                    net.rpcUrl
                ],
                "nativeCurrency": {
                    "symbol": `TST${net.rollupId}`,
                    "decimals": 18
                }
            }
        ]
    });
}


async function getAllDeposits(defaultBridgeService, account) {
    const url = `${defaultBridgeService}/bridges/${account}`;
    const depositRequest = new Request(url);
    const depositResponse = await fetch(depositRequest);
    const depositData = await depositResponse.json();
    return depositData;
}

function renderDeposits(defaultBridgeService, bridgeAddress, deposits) {
    const df = document.createDocumentFragment();
    for(var i = 0; i < deposits.deposits.length; i = i + 1){
        let dep = deposits.deposits[i];

        let txtDiv = document.createElement("div");
        txtDiv.innerText = "#########################################################################";
        txtDiv.className = "divider";
        df.appendChild(txtDiv);

        let h2 = document.createElement("h2");
        let url = `${defaultBridgeService}/bridge?deposit_cnt=${dep.deposit_cnt}&net_id=${dep.network_id}`;
        let a = document.createElement("a");
        a.href = url;
        a.target = "_blank";
        a.innerText = "Deposit: " + dep.deposit_cnt;
        h2.appendChild(a);
        df.appendChild(h2);

        let dl = document.createElement("dl");
        for (const [key, value] of Object.entries(dep)) {

            let dt = document.createElement("dt");
            dt.innerText = key + ":";
            let dd = document.createElement("dd");
            dd.innerText = value;

            dl.appendChild(dt);
            dl.appendChild(dd);
        }
        df.appendChild(dl);
        let btn = document.createElement('button')
        btn.innerText = "Claim Deposit: " + dep.deposit_cnt;
        btn.addEventListener('click', async function() {
            attemptClaimTx(defaultBridgeService, bridgeAddress, dep);
        });
        df.appendChild(btn);
    }
    return df;
}

async function attemptClaimTx(defaultBridgeService, bridgeAddress, deposit) {
    const mp = await getMerkleProof(defaultBridgeService, deposit);
    if (!mp) {
        return;
    }


    merkleProof = mp.proof.merkle_proof;
    rollupMerkleProof = mp.proof.rollup_merkle_proof;
    globalIndex = deposit.global_index;
    mainExitRoot = mp.proof.main_exit_root;
    rollupExitRoot = mp.proof.rollup_exit_root;
    origNet = deposit.orig_net;
    origAddr = deposit.orig_addr;
    destNet = deposit.dest_net;
    destAddr = deposit.dest_addr;
    amount = deposit.amount;
    metadata = deposit.metadata;

    console.log(merkleProof, rollupMerkleProof, globalIndex, mainExitRoot, rollupExitRoot, origNet, origAddr, destNet, destAddr, amount, metadata);

    let net = nets[destNet];
    if (!net) {
        alert(`Unknown destination network: ${destNet}`);
        return;
    }

    await addChain(net);
    await window.ethereum.request({ method: 'wallet_switchEthereumChain', params: [{"chainId": net.chainIdHex}] });

    let txData = net.bridge.methods.claimAsset(merkleProof, rollupMerkleProof, globalIndex, mainExitRoot, rollupExitRoot, origNet, origAddr, destNet, destAddr, amount, metadata).encodeABI();
    console.log(txData);

    await window.ethereum.request({
        method: "eth_sendTransaction",
        params: [
            {
                to: bridgeAddress,
                from: accounts[0],
                data: txData
            }
        ]
    });

    console.log(mp)
}

async function getMerkleProof(defaultBridgeService, deposit) {
    try {
        const url = `${defaultBridgeService}/merkle-proof?deposit_cnt=${deposit.deposit_cnt}&net_id=${deposit.network_id}`;
        const mpRequest = new Request(url);
        const mpResponse = await fetch(mpRequest);
        const mpData = await mpResponse.json();
        return mpData;

    } catch (e) {
        console.warn(e);
        alert("unable to get merkle proof! Is it ready??");
        return null;
    }
}
