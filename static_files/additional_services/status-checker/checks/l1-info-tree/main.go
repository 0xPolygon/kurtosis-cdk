// Decodes Etrog (batch v2) L2 batch data into JSON. This is a stdlib-only port
// of DecodeBatchV2 from github.com/0xPolygonHermez/zkevm-node/state, limited to
// the framing: transactions are kept as raw hex instead of being decoded.
package main

import (
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"strings"
)

const (
	changeL2Block = 0x0b
	// R (32) + S (32) + V (1) + efficiency percentage (1) follow each tx RLP.
	txSuffixLength = 66
)

type L2TxRaw struct {
	Tx                   string
	EfficiencyPercentage uint8
}

type L2BlockRaw struct {
	DeltaTimestamp  uint32
	IndexL1InfoTree uint32
	Transactions    []L2TxRaw
}

type BatchRawV2 struct {
	Blocks []L2BlockRaw
}

var errInvalidBatch = errors.New("invalid batch v2")

func readUint32(data []byte, pos int) (int, uint32, error) {
	if len(data)-pos < 4 {
		return 0, 0, fmt.Errorf("not enough data for uint32 at pos %d: %w", pos, errInvalidBatch)
	}
	v := uint32(data[pos])<<24 | uint32(data[pos+1])<<16 | uint32(data[pos+2])<<8 | uint32(data[pos+3])
	return pos + 4, v, nil
}

// rlpListLength returns the full length (header included) of the RLP list
// starting at pos.
func rlpListLength(data []byte, pos int) (int, error) {
	b := int(data[pos])
	switch {
	case b < 0xc0:
		return 0, fmt.Errorf("first byte of tx (%x) is not an RLP list: %w", b, errInvalidBatch)
	case b <= 0xf7:
		return 1 + b - 0xc0, nil
	}
	n := b - 0xf7
	if n > 8 || pos+1+n > len(data) {
		return 0, fmt.Errorf("invalid RLP list length at pos %d: %w", pos, errInvalidBatch)
	}
	var payload uint64
	for _, c := range data[pos+1 : pos+1+n] {
		payload = payload<<8 | uint64(c)
	}
	if payload > uint64(len(data)) {
		return 0, fmt.Errorf("RLP list too long at pos %d: %w", pos, errInvalidBatch)
	}
	return 1 + n + int(payload), nil
}

func decodeTx(data []byte, pos int) (int, L2TxRaw, error) {
	length, err := rlpListLength(data, pos)
	if err != nil {
		return 0, L2TxRaw{}, err
	}
	end := pos + length + txSuffixLength
	if end > len(data) {
		return 0, L2TxRaw{}, fmt.Errorf("not enough data for tx (end=%d len=%d): %w", end, len(data), errInvalidBatch)
	}
	tx := L2TxRaw{
		Tx:                   "0x" + hex.EncodeToString(data[pos:end-1]),
		EfficiencyPercentage: data[end-1],
	}
	return end, tx, nil
}

func decodeBatchV2(data []byte) (*BatchRawV2, error) {
	batch := &BatchRawV2{}
	var current *L2BlockRaw
	pos := 0
	for pos < len(data) {
		if data[pos] == changeL2Block {
			if current != nil {
				batch.Blocks = append(batch.Blocks, *current)
			}
			current = &L2BlockRaw{}
			var err error
			if pos, current.DeltaTimestamp, err = readUint32(data, pos+1); err != nil {
				return nil, fmt.Errorf("can't get deltaTimestamp: %w", err)
			}
			if pos, current.IndexL1InfoTree, err = readUint32(data, pos); err != nil {
				return nil, fmt.Errorf("can't get indexL1InfoTree: %w", err)
			}
			continue
		}
		if current == nil {
			return nil, fmt.Errorf("batch must start with changeL2Block: %w", errInvalidBatch)
		}
		var tx L2TxRaw
		var err error
		if pos, tx, err = decodeTx(data, pos); err != nil {
			return nil, fmt.Errorf("can't decode transactions: %w", err)
		}
		current.Transactions = append(current.Transactions, tx)
	}
	if current != nil {
		batch.Blocks = append(batch.Blocks, *current)
	}
	return batch, nil
}

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

	raw, err := hex.DecodeString(strings.TrimPrefix(strings.TrimSpace(string(data)), "0x"))
	if err != nil {
		slog.Error("Failed to decode hex input", "err", err)
		os.Exit(1)
	}

	batch, err := decodeBatchV2(raw)
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
