# Docker Network Fix for Snapshots

## Problem

When trying to restart snapshots using `docker compose up` or `docker compose down`, you would encounter this error:

```
network snapshot-cdk-YYYYMMDD-HHMMSS-l1 was found but has incorrect label
com.docker.compose.network set to "snapshot-cdk-YYYYMMDD-HHMMSS-l1"
```

This error occurs because Docker Compose was trying to manage the network with custom naming, but the labels didn't match on subsequent runs.

## Root Cause

The issue was in how the docker-compose.yml was configured:

**Before (Problematic):**
```yaml
networks:
  l1-network:
    name: snapshot-cdk-YYYYMMDD-HHMMSS-l1
    driver: bridge
```

When docker-compose creates this network, it adds internal labels. On restart, it checks these labels and fails if they don't match exactly.

## Solution

### Changes Made

Three files were modified in `/home/aigent/kurtosis-cdk/snapshot/scripts/generate-compose.sh`:

#### 1. Docker Compose Network Configuration

**After (Fixed):**
```yaml
networks:
  l1-network:
    name: snapshot-cdk-YYYYMMDD-HHMMSS-l1
    external: true
```

By marking the network as `external: true`, we tell docker-compose that the network is managed outside of docker-compose, so it won't try to validate or modify labels.

#### 2. Start Script Enhancement

The `start-snapshot.sh` script now creates the network if it doesn't exist:

```bash
NETWORK_NAME="snapshot-<snapshot-id>-l1"

# Create network if it doesn't exist
if ! docker network inspect "$NETWORK_NAME" &> /dev/null; then
    echo "Creating Docker network: $NETWORK_NAME"
    docker network create "$NETWORK_NAME" --driver bridge
else
    echo "Docker network already exists: $NETWORK_NAME"
fi

docker-compose -f docker-compose.yml up -d
```

#### 3. Stop Script Enhancement

The `stop-snapshot.sh` script now removes the network after stopping containers:

```bash
NETWORK_NAME="snapshot-<snapshot-id>-l1"

docker-compose -f docker-compose.yml down

# Remove the network if it exists and is not in use
if docker network inspect "$NETWORK_NAME" &> /dev/null; then
    echo "Removing Docker network: $NETWORK_NAME"
    docker network rm "$NETWORK_NAME" 2>/dev/null || echo "Network still in use or already removed"
fi
```

## Benefits

1. **No More Label Errors**: Docker Compose no longer validates network labels, preventing restart errors
2. **Clean Network Management**: Networks are properly created on start and removed on stop
3. **Idempotent Operations**: Running start multiple times is safe - it checks if the network exists first
4. **Proper Cleanup**: Stop script ensures networks are removed, preventing accumulation of stale networks

## Testing

To test the fix with a new snapshot:

1. **Create a new snapshot:**
   ```bash
   cd /home/aigent/kurtosis-cdk
   ./snapshot/snapshot.sh <enclave-name>
   ```

2. **Navigate to the snapshot directory:**
   ```bash
   cd snapshots/cdk-<timestamp>
   ```

3. **Start the snapshot:**
   ```bash
   ./start-snapshot.sh
   ```

   You should see:
   ```
   Creating Docker network: snapshot-cdk-<timestamp>-l1
   ```

4. **Stop the snapshot:**
   ```bash
   ./stop-snapshot.sh
   ```

   You should see:
   ```
   Removing Docker network: snapshot-cdk-<timestamp>-l1
   ```

5. **Start again (the key test):**
   ```bash
   ./start-snapshot.sh
   ```

   This should work without any label errors!

## Existing Snapshots

Existing snapshots generated before this fix will still have the old configuration. They can be updated using the fix-existing-snapshots.sh script:

```bash
/home/aigent/kurtosis-cdk/snapshot/fix-existing-snapshots.sh
```

However, the recommended approach is to **generate new snapshots** using the fixed scripts.

## Files Modified

- `/home/aigent/kurtosis-cdk/snapshot/scripts/generate-compose.sh`
  - Network configuration (line ~455): Added `external: true`
  - Start script generation (line ~472): Added network creation logic
  - Stop script generation (line ~498): Added network cleanup logic

## Additional Notes

- Each snapshot gets a unique network name based on its timestamp: `snapshot-cdk-<timestamp>-l1`
- The bridge driver is still used - only the management approach changed
- Networks are isolated per snapshot, allowing multiple snapshots to run simultaneously
- The network is created manually before docker-compose needs it, avoiding label conflicts
