package main

import (
	"fmt"

	"github.com/0xPolygon/cdk-contracts-tooling/contracts/banana/polygonzkevmglobalexitrootv2"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/ethclient"
)

const (
	pk         = "12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"
	l1ChainID  = 271828
	bridgeAddr = "0xD71f8F956AD979Cc2988381B8A743a2fE280537D"
	gerAddr    = "0x1f7ad7caA53e35b4f0D138dC5CBF91aC108a2674"
	l1RPC      = "http://localhost:33297"
)

func main() {
	// privateKey, err := crypto.HexToECDSA(pk)
	// if err != nil {
	// 	panic(err)
	// }
	// auth, err := bind.NewKeyedTransactorWithChainID(privateKey, big.NewInt(l1ChainID))
	// if err != nil {
	// 	panic(err)
	// }
	client, err := ethclient.Dial(l1RPC)
	if err != nil {
		panic(err)
	}
	contract, err := polygonzkevmglobalexitrootv2.NewPolygonzkevmglobalexitrootv2(
		common.HexToAddress(gerAddr),
		client,
	)
	if err != nil {
		panic(err)
	}
	ger, err := contract.L1InfoRootMap(&bind.CallOpts{Pending: false}, 1)
	if err != nil {
		panic(err)
	}
	fmt.Println(common.Bytes2Hex(ger[:]))
}
