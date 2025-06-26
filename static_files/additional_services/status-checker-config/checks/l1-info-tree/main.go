package main

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"os"

	"github.com/0xPolygonHermez/zkevm-node/state"
	"github.com/ethereum/go-ethereum/common"
)

func main() {
	batch, err := state.DecodeBatchV2(common.FromHex(os.Args[1]))
	if err != nil {
		slog.Error("Failed to decode L2 batch data", "err", err)
		os.Exit(1)
	}

	bytes, err := json.Marshal(batch)
	if err != nil {
		slog.Error("Failed to marshal L2 batch data", "err", err)
		os.Exit(1)
	}

	fmt.Println(string(bytes))
}
