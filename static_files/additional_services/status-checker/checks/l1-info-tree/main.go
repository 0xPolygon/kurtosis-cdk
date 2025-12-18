package main

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
	"strings"

	"github.com/0xPolygonHermez/zkevm-node/state"
	"github.com/ethereum/go-ethereum/common"
)

func main() {
	if len(os.Args) < 2 {
		slog.Error("Missing input file path argument")
		os.Exit(1)
	}

	data, err := os.ReadFile(os.Args[1])
	if err != nil {
		slog.Error("Failed to read input file", "err", err)
		os.Exit(1)
	}

	txs := common.FromHex(strings.TrimSpace(string(data)))
	batch, err := state.DecodeBatchV2(txs)
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
