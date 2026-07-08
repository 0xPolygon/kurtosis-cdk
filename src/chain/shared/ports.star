# Port identifiers and numbers.
HTTP_RPC_PORT_ID = "rpc"
HTTP_RPC_PORT_NUMBER = 8545

WS_RPC_PORT_ID = "ws-rpc"
WS_RPC_PORT_NUMBER = 8546

# paychain-node's AggchainProofService gRPC facade. The aggsender talks to this
# directly (there is no separate aggkit-prover for the cdk-payments flavor).
PAYCHAIN_GRPC_PORT_ID = "grpc"
PAYCHAIN_GRPC_PORT_NUMBER = 4446
