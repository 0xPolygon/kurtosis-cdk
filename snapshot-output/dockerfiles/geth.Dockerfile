# Geth Dockerfile for snapshot (Datadir-based approach)
# ======================================================
# This Dockerfile copies a COMPLETE geth datadir including:
# - geth/chaindata (state database)
# - geth/ancient (immutable ancient blocks)
# - keystore/ (account keys)
# - jwtsecret (Engine API authentication)
# - All other datadir contents
#
# This allows geth to continue from where it left off during snapshot creation.
#
# Template Variables (replaced during image build):
#   ethereum/client-go:v1.16.8 - Base geth image (e.g., ethereum/client-go:v1.16.8)
#   271828        - Network chain ID
#   json      - Log format: "json" or "terminal"
#
# Build Context:
#   The build context should contain:
#   - execution-data/: Complete geth datadir extracted from running container

FROM ethereum/client-go:v1.16.8

# Copy the ENTIRE extracted geth datadir
# This includes: geth/, ancient/, keystore/, etc.
COPY execution-data/ /root/.ethereum/

# Copy JWT secret (CRITICAL for Engine API authentication with lighthouse)
# Must be at /jwt/jwtsecret to match Kurtosis deployment path
COPY jwtsecret /jwt/jwtsecret

# Fix permissions (jwtsecret must be 600)
RUN chmod 600 /jwt/jwtsecret && \
    chmod -R u+rwX /root/.ethereum/

# Expose ports
# 8545: HTTP RPC endpoint
# 8546: WebSocket RPC endpoint
# 8551: Engine API endpoint (for consensus client)
EXPOSE 8545 8546 8551

# Set entrypoint
# Geth will start from the initialized genesis (block 0) and begin producing blocks
ENTRYPOINT ["geth", \
    "--datadir", "/root/.ethereum", \
    "--http", \
    "--http.addr", "0.0.0.0", \
    "--http.port", "8545", \
    "--http.api", "eth,net,web3,engine", \
    "--ws", \
    "--ws.addr", "0.0.0.0", \
    "--ws.port", "8546", \
    "--ws.api", "eth,net,web3", \
    "--authrpc.addr", "0.0.0.0", \
    "--authrpc.port", "8551", \
    "--authrpc.jwtsecret", "/jwt/jwtsecret", \
    "--gcmode", "archive", \
    "--log.format", "json", \
    "--networkid", "271828", \
    "--http.corsdomain", "*", \
    "--http.vhosts", "*" \
]
