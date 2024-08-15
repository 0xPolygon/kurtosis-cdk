package main

import (
	"context"
	"fmt"
	"math/big"
	"time"

	"github.com/0xPolygon/cdk-contracts-tooling/contracts/banana/polygonzkevmbridgev2"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
)

const (
	pk         = "12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"
	l1ChainID  = 271828
	bridgeAddr = "0xD71f8F956AD979Cc2988381B8A743a2fE280537D"
	l1RPC      = "http://localhost:32965"
)

func main() {
	privateKey, err := crypto.HexToECDSA(pk)
	if err != nil {
		panic(err)
	}
	auth, err := bind.NewKeyedTransactorWithChainID(privateKey, big.NewInt(l1ChainID))
	if err != nil {
		panic(err)
	}
	client, err := ethclient.Dial(l1RPC)
	if err != nil {
		panic(err)
	}
	contract, err := polygonzkevmbridgev2.NewPolygonzkevmbridgev2(
		common.HexToAddress(bridgeAddr),
		client,
	)
	if err != nil {
		panic(err)
	}
	tx, err := contract.BridgeAsset(
		auth, 1, common.Address{}, big.NewInt(0), common.Address{}, true, nil,
	)
	if err != nil {
		panic(err)
	}
	fmt.Println("bridge tx sent, waiting for it to be mined...")
	for {
		time.Sleep(time.Second)
		r, err := client.TransactionReceipt(context.Background(), tx.Hash())
		if err != nil {
			fmt.Println("error getting tx receipt: ", err)
			continue
		}
		fmt.Printf("tx receipt: %+v\n", r)
		break
	}
}
