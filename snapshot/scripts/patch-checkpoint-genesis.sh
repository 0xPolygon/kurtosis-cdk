#!/usr/bin/env bash
set -euo pipefail

# Patch checkpoint BeaconState genesis_time to match current time
# This allows snapshots to work with time gaps between creation and restore
#
# Usage: patch-checkpoint-genesis.sh <checkpoint_dir> <checkpoint_slot> <seconds_per_slot>
#
# Args:
#   checkpoint_dir: Directory containing checkpoint_state.ssz
#   checkpoint_slot: Slot number from checkpoint metadata
#   seconds_per_slot: Network's SECONDS_PER_SLOT config value

CHECKPOINT_DIR="${1:?Missing checkpoint_dir}"
CHECKPOINT_SLOT="${2:?Missing checkpoint_slot}"
SECONDS_PER_SLOT="${3:?Missing seconds_per_slot}"

CHECKPOINT_FILE="$CHECKPOINT_DIR/checkpoint_state.ssz"

if [[ ! -f "$CHECKPOINT_FILE" ]]; then
    echo "ERROR: Checkpoint file not found: $CHECKPOINT_FILE" >&2
    exit 1
fi

# Calculate new genesis time
# Formula: genesis_time = current_time - (checkpoint_slot * seconds_per_slot)
# This ensures that at current_time, the calculated current_slot equals checkpoint_slot
CURRENT_TIME=$(date +%s)
SLOT_OFFSET=$((CHECKPOINT_SLOT * SECONDS_PER_SLOT))
NEW_GENESIS_TIME=$((CURRENT_TIME - SLOT_OFFSET))

echo "=== Genesis Time Patcher ==="
echo "Checkpoint file: $CHECKPOINT_FILE"
echo "Checkpoint slot: $CHECKPOINT_SLOT"
echo "Seconds per slot: $SECONDS_PER_SLOT"
echo "Current time: $CURRENT_TIME"
echo "Calculated new genesis_time: $NEW_GENESIS_TIME"
echo ""

# Create Java patcher code
PATCHER_CODE=$(cat <<'EOF'
import tech.pegasys.teku.spec.Spec;
import tech.pegasys.teku.spec.SpecFactory;
import tech.pegasys.teku.spec.datastructures.state.beaconstate.BeaconState;
import tech.pegasys.teku.infrastructure.unsigned.UInt64;
import org.apache.tuweni.bytes.Bytes;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

public class GenesisTimePatcher {
    public static void main(String[] args) throws Exception {
        if (args.length != 3) {
            System.err.println("Usage: GenesisTimePatcher <spec_yaml> <input_ssz> <new_genesis_time>");
            System.exit(1);
        }

        String specYaml = args[0];
        Path inputFile = Paths.get(args[1]);
        UInt64 newGenesisTime = UInt64.valueOf(args[2]);

        System.out.println("Loading spec from: " + specYaml);
        Spec spec = SpecFactory.create(specYaml);

        System.out.println("Loading checkpoint state from: " + inputFile);
        byte[] sszData = Files.readAllBytes(inputFile);
        Bytes sszBytes = Bytes.wrap(sszData);
        BeaconState originalState = spec.deserializeBeaconState(sszBytes);

        System.out.println("Original genesis_time: " + originalState.getGenesisTime());
        System.out.println("New genesis_time: " + newGenesisTime);

        // Create modified state with new genesis_time
        BeaconState patchedState = originalState.updated(state ->
            state.setGenesisTime(newGenesisTime)
        );

        // Verify the change
        if (!patchedState.getGenesisTime().equals(newGenesisTime)) {
            throw new RuntimeException("Failed to update genesis_time");
        }

        System.out.println("Patched genesis_time: " + patchedState.getGenesisTime());

        // Serialize back to SSZ
        byte[] patchedSsz = patchedState.sszSerialize().toArrayUnsafe();

        // Write to temporary file first
        Path tempFile = Paths.get(inputFile.toString() + ".tmp");
        Files.write(tempFile, patchedSsz);

        // Atomic rename to replace original
        Files.move(tempFile, inputFile, java.nio.file.StandardCopyOption.REPLACE_EXISTING);

        System.out.println("Successfully patched checkpoint state");

        // Verify round-trip
        byte[] verifyData = Files.readAllBytes(inputFile);
        Bytes verifyBytes = Bytes.wrap(verifyData);
        BeaconState verifiedState = spec.deserializeBeaconState(verifyBytes);

        if (!verifiedState.getGenesisTime().equals(newGenesisTime)) {
            throw new RuntimeException("Round-trip verification failed");
        }

        System.out.println("Round-trip verification passed");
    }
}
EOF
)

# Create temporary directory for compilation
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Make directory readable and writable by Docker container
chmod 777 "$WORK_DIR"

echo "$PATCHER_CODE" > "$WORK_DIR/GenesisTimePatcher.java"

# Copy checkpoint and spec to work directory (Teku container needs access)
cp "$CHECKPOINT_FILE" "$WORK_DIR/checkpoint_state.ssz"
cp "$CHECKPOINT_DIR/../network-configs/spec.yaml" "$WORK_DIR/spec.yaml"

# Make files readable by Docker container
chmod 644 "$WORK_DIR/"*

echo "Compiling patcher inside Teku container..."
echo "DEBUG: Files in WORK_DIR:"
ls -la "$WORK_DIR"
docker run --rm \
    --entrypoint bash \
    -v "$WORK_DIR:/work" \
    -w /work \
    consensys/teku:24.12.0 \
    -c "ls -la && javac -cp '/opt/teku/lib/*' GenesisTimePatcher.java"

if [[ ! -f "$WORK_DIR/GenesisTimePatcher.class" ]]; then
    echo "ERROR: Compilation failed" >&2
    exit 1
fi

echo "Running patcher..."
docker run --rm \
    --entrypoint bash \
    -v "$WORK_DIR:/work" \
    -w /work \
    consensys/teku:24.12.0 \
    -c "java -cp '/opt/teku/lib/*:.' GenesisTimePatcher /work/spec.yaml /work/checkpoint_state.ssz $NEW_GENESIS_TIME"

# Copy patched checkpoint back
cp "$WORK_DIR/checkpoint_state.ssz" "$CHECKPOINT_FILE"

echo ""
echo "=== Patching Complete ==="
echo "Checkpoint has been patched with new genesis_time: $NEW_GENESIS_TIME"
