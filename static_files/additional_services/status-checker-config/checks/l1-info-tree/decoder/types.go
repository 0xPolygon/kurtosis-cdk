package decoder

import (
	"errors"

	"github.com/ethereum/go-ethereum/core/types"
)

// ChangeL2BlockHeader is the header of a L2 block.
type ChangeL2BlockHeader struct {
	DeltaTimestamp  uint32
	IndexL1InfoTree uint32
}

// L2BlockRaw is the raw representation of a L2 block.
type L2BlockRaw struct {
	ChangeL2BlockHeader
	Transactions []L2TxRaw
}

// BatchRawV2 is the  representation of a batch of transactions.
type BatchRawV2 struct {
	Blocks []L2BlockRaw
}

// ForcedBatchRawV2 is the  representation of a forced batch of transactions.
type ForcedBatchRawV2 struct {
	Transactions []L2TxRaw
}

// L2TxRaw is the raw representation of a L2 transaction  inside a L2 block.
type L2TxRaw struct {
	EfficiencyPercentage uint8             // valid always
	TxAlreadyEncoded     bool              // If true the tx is already encoded (data field is used)
	Tx                   types.Transaction // valid if TxAlreadyEncoded == false
	Data                 []byte            // valid if TxAlreadyEncoded == true
}

const (
	changeL2Block = uint8(0x0b)
	sizeUInt32    = 4
)

var (
	// ErrBatchV2DontStartWithChangeL2Block is returned when the batch start directly with a trsansaction (without a changeL2Block)
	ErrBatchV2DontStartWithChangeL2Block = errors.New("batch v2 must start with changeL2Block before Tx (suspect a V1 Batch or a ForcedBatch?))")
	// ErrInvalidBatchV2 is returned when the batch is invalid.
	ErrInvalidBatchV2 = errors.New("invalid batch v2")
	// ErrInvalidRLP is returned when the rlp is invalid.
	ErrInvalidRLP = errors.New("invalid rlp codification")
)

const (
	double       = 2
	ether155V    = 27
	etherPre155V = 35
	// MaxEffectivePercentage is the maximum value that can be used as effective percentage
	MaxEffectivePercentage = uint8(255)
	// Decoding constants
	headerByteLength uint64 = 1
	sLength          uint64 = 32
	rLength          uint64 = 32
	vLength          uint64 = 1
	c0               uint64 = 192 // 192 is c0. This value is defined by the rlp protocol
	ff               uint64 = 255 // max value of rlp header
	shortRlp         uint64 = 55  // length of the short rlp codification
	f7               uint64 = 247 // 192 + 55 = c0 + shortRlp

	// EfficiencyPercentageByteLength is the length of the effective percentage in bytes
	EfficiencyPercentageByteLength uint64 = 1
)
