// solc --bin --strict-assembly batch-filler.yul
{
        mstore(0x7000,1)
        let bigContract := create(0, 0x1000, 0x6000)
        for {} gt(gas(), 2500) {} {
                extcodecopy(bigContract, 0x1000, 0x1000, 0x6000)
        }
}
