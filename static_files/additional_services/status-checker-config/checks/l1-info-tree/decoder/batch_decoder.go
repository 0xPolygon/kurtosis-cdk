package decoder

import (
	"encoding/binary"
	"fmt"
	"math/big"
	"strconv"

	"github.com/0xPolygon/kurtosis-cdk/static_files/additional_services/status-checker-config/checks/l1-info-tree-count/hex"
	"github.com/0xPolygonHermez/zkevm-data-streamer/log"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/rlp"
)

// decodeBlockHeader decodes a block header from a byte slice.
//
//	Extract: 4 bytes for deltaTimestamp + 4 bytes for indexL1InfoTree
func decodeBlockHeader(txsData []byte, pos int) (int, *L2BlockRaw, error) {
	var err error
	currentBlock := &L2BlockRaw{}
	pos, currentBlock.DeltaTimestamp, err = decodeUint32(txsData, pos)
	if err != nil {
		return 0, nil, fmt.Errorf("can't get deltaTimestamp: %w", err)
	}
	pos, currentBlock.IndexL1InfoTree, err = decodeUint32(txsData, pos)
	if err != nil {
		return 0, nil, fmt.Errorf("can't get leafIndex: %w", err)
	}

	return pos, currentBlock, nil
}

func DecodeBatchV2(txsData []byte) (*BatchRawV2, error) {
	// The transactions is not RLP encoded. Is the raw bytes in this form: 1 byte for the transaction type (always 0b for changeL2Block) + 4 bytes for deltaTimestamp + for bytes for indexL1InfoTree
	var err error
	var blocks []L2BlockRaw
	var currentBlock *L2BlockRaw
	pos := int(0)
	for pos < len(txsData) {
		switch txsData[pos] {
		case changeL2Block:
			if currentBlock != nil {
				blocks = append(blocks, *currentBlock)
			}
			pos, currentBlock, err = decodeBlockHeader(txsData, pos+1)
			if err != nil {
				return nil, fmt.Errorf("pos: %d can't decode new BlockHeader: %w", pos, err)
			}
		// by RLP definition a tx never starts with a 0x0b. So, if is not a changeL2Block
		// is a tx
		default:
			if currentBlock == nil {
				_, _, err := DecodeTxRLP(txsData, pos)
				if err == nil {
					// There is no changeL2Block but have a valid RLP transaction
					return nil, ErrBatchV2DontStartWithChangeL2Block
				} else {
					// No changeL2Block and no valid RLP transaction
					return nil, fmt.Errorf("no ChangeL2Block neither valid Tx, batch malformed : %w", ErrInvalidBatchV2)
				}
			}
			var tx *L2TxRaw
			pos, tx, err = DecodeTxRLP(txsData, pos)
			if err != nil {
				return nil, fmt.Errorf("can't decode transactions: %w", err)
			}

			currentBlock.Transactions = append(currentBlock.Transactions, *tx)
		}
	}
	if currentBlock != nil {
		blocks = append(blocks, *currentBlock)
	}
	return &BatchRawV2{blocks}, nil
}

func encodeUint32(value uint32) []byte {
	data := make([]byte, sizeUInt32)
	binary.BigEndian.PutUint32(data, value)
	return data
}

func decodeUint32(txsData []byte, pos int) (int, uint32, error) {
	if len(txsData)-pos < sizeUInt32 {
		return 0, 0, fmt.Errorf("can't get u32 because not enough data: %w", ErrInvalidBatchV2)
	}
	return pos + sizeUInt32, binary.BigEndian.Uint32(txsData[pos : pos+sizeUInt32]), nil
}

// DecodeTxRLP decodes a transaction from a byte slice.
func DecodeTxRLP(txsData []byte, offset int) (int, *L2TxRaw, error) {
	var err error
	length, err := decodeRLPListLengthFromOffset(txsData, offset)
	if err != nil {
		return 0, nil, fmt.Errorf("can't get RLP length (offset=%d): %w", offset, err)
	}
	endPos := uint64(offset) + length + rLength + sLength + vLength + EfficiencyPercentageByteLength
	if endPos > uint64(len(txsData)) {
		return 0, nil, fmt.Errorf("can't get tx because not enough data (endPos=%d lenData=%d): %w",
			endPos, len(txsData), ErrInvalidBatchV2)
	}
	fullDataTx := txsData[offset:endPos]
	dataStart := uint64(offset) + length
	txInfo := txsData[offset:dataStart]
	rData := txsData[dataStart : dataStart+rLength]
	sData := txsData[dataStart+rLength : dataStart+rLength+sLength]
	vData := txsData[dataStart+rLength+sLength : dataStart+rLength+sLength+vLength]
	efficiencyPercentage := txsData[dataStart+rLength+sLength+vLength]
	var rlpFields [][]byte
	err = rlp.DecodeBytes(txInfo, &rlpFields)
	if err != nil {
		log.Error("error decoding tx Bytes: ", err, ". fullDataTx: ", hex.EncodeToString(fullDataTx), "\n tx: ", hex.EncodeToString(txInfo), "\n Txs received: ", hex.EncodeToString(txsData))
		return 0, nil, err
	}
	legacyTx, err := RlpFieldsToLegacyTx(rlpFields, vData, rData, sData)
	if err != nil {
		log.Debug("error creating tx from rlp fields: ", err, ". fullDataTx: ", hex.EncodeToString(fullDataTx), "\n tx: ", hex.EncodeToString(txInfo), "\n Txs received: ", hex.EncodeToString(txsData))
		return 0, nil, err
	}

	l2Tx := &L2TxRaw{
		Tx:                   *types.NewTx(legacyTx),
		EfficiencyPercentage: efficiencyPercentage,
	}

	return int(endPos), l2Tx, err
}

// It returns the length of data from the param offset
// ex:
// 0xc0 -> empty data -> 1 byte because it include the 0xc0
func decodeRLPListLengthFromOffset(txsData []byte, offset int) (uint64, error) {
	txDataLength := uint64(len(txsData))
	num := uint64(txsData[offset])
	if num < c0 { // c0 -> is a empty data
		log.Debugf("error num < c0 : %d, %d", num, c0)
		return 0, fmt.Errorf("first byte of tx (%x) is < 0xc0: %w", num, ErrInvalidRLP)
	}
	length := num - c0
	if length > shortRlp { // If rlp is bigger than length 55
		// n is the length of the rlp data without the header (1 byte) for example "0xf7"
		pos64 := uint64(offset)
		lengthInByteOfSize := num - f7
		if (pos64 + headerByteLength + lengthInByteOfSize) > txDataLength {
			log.Debug("error not enough data: ")
			return 0, fmt.Errorf("not enough data to get length: %w", ErrInvalidRLP)
		}

		n, err := strconv.ParseUint(hex.EncodeToString(txsData[pos64+1:pos64+1+lengthInByteOfSize]), hex.Base, hex.BitSize64) // +1 is the header. For example 0xf7
		if err != nil {
			log.Debug("error parsing length: ", err)
			return 0, fmt.Errorf("error parsing length value: %w", err)
		}
		// TODO: RLP specifications says length = n ??? that is wrong??
		length = n + num - f7 // num - f7 is the header. For example 0xf7
	}
	return length + headerByteLength, nil
}

func RlpFieldsToLegacyTx(fields [][]byte, v, r, s []byte) (tx *types.LegacyTx, err error) {
	const (
		fieldsSizeWithoutChainID = 6
		fieldsSizeWithChainID    = 7
	)

	if len(fields) < fieldsSizeWithoutChainID {
		return nil, types.ErrTxTypeNotSupported
	}

	nonce := big.NewInt(0).SetBytes(fields[0]).Uint64()
	gasPrice := big.NewInt(0).SetBytes(fields[1])
	gas := big.NewInt(0).SetBytes(fields[2]).Uint64()
	var to *common.Address

	if fields[3] != nil && len(fields[3]) != 0 {
		tmp := common.BytesToAddress(fields[3])
		to = &tmp
	}
	value := big.NewInt(0).SetBytes(fields[4])
	data := fields[5]

	txV := big.NewInt(0).SetBytes(v)
	if len(fields) >= fieldsSizeWithChainID {
		chainID := big.NewInt(0).SetBytes(fields[6])

		// a = chainId * 2
		// b = v - 27
		// c = a + 35
		// v = b + c
		//
		// same as:
		// v = v-27+chainId*2+35
		a := new(big.Int).Mul(chainID, big.NewInt(double))
		b := new(big.Int).Sub(new(big.Int).SetBytes(v), big.NewInt(ether155V))
		c := new(big.Int).Add(a, big.NewInt(etherPre155V))
		txV = new(big.Int).Add(b, c)
	}

	txR := big.NewInt(0).SetBytes(r)
	txS := big.NewInt(0).SetBytes(s)

	return &types.LegacyTx{
		Nonce:    nonce,
		GasPrice: gasPrice,
		Gas:      gas,
		To:       to,
		Value:    value,
		Data:     data,
		V:        txV,
		R:        txR,
		S:        txS,
	}, nil
}
