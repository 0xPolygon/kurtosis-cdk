#!/bin/bash
set -euo pipefail

# Generate up.sh convenience wrapper
# Usage: create_up_script.sh <output_up.sh>

OUTPUT_FILE="$1"

cat > "$OUTPUT_FILE" <<'UP_SCRIPT_EOF'
#!/bin/bash
set -euo pipefail

echo "Starting snapshot with fresh genesis..."

# Clean runtime directory
rm -rf runtime/*
mkdir -p runtime

# Start services
docker-compose up --force-recreate --remove-orphans -d

echo ""
echo "Services starting..."
echo "  - init: Generating fresh genesis with current timestamp"
echo "  - geth: Initializing from genesis"
echo "  - lighthouse-bn: Syncing from geth"
echo "  - lighthouse-vc: Producing blocks"
echo ""
echo "Follow logs with: docker-compose logs -f"
echo "Check block number: cast block-number --rpc-url http://localhost:8545"
echo "Stop services: docker-compose down"
UP_SCRIPT_EOF

chmod +x "$OUTPUT_FILE"
echo "Up script created: $OUTPUT_FILE"
