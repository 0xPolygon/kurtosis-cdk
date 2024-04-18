#!/bin/bash
# This script will dump default and current configurations used in the CDK stack.

dump_default_zkevm_configs() {
  directory="${1%/}"
  echo "Dumping default zkevm configurations in $directory/..."

  # Dump default configs of zkevm components written in go.
  go run dump_zkevm_default_config.go "$directory"

  # Dump default configs of the rest of the zkevm components, not written in go.
  ZKEVM_NODE_INIT_EVENT_DB_DEFAULT_SCRIPT="https://raw.githubusercontent.com/0xPolygonHermez/zkevm-node/develop/db/scripts/init_event_db.sql"
  ZKEVM_NODE_INIT_PROVER_DB_DEFAULT_SCRIPT="https://raw.githubusercontent.com/0xPolygonHermez/zkevm-node/develop/db/scripts/init_prover_db.sql"
  ZKEVM_PROVER_DEFAULT_CONFIG="https://raw.githubusercontent.com/0xPolygonHermez/zkevm-prover/main/config/config_prover.json"
  ZKEVM_EXECUTOR_DEFAULT_CONFIG="https://raw.githubusercontent.com/0xPolygonHermez/zkevm-prover/main/config/config_executor.json"
  ZKEVM_BRIDGE_UI_DEFAULT_CONFIG="https://raw.githubusercontent.com/0xPolygonHermez/zkevm-bridge-ui/develop/.env.example"

  echo "Dumping default event db init script"
  curl --output "$directory/event-db-init.sql" "$ZKEVM_NODE_INIT_EVENT_DB_DEFAULT_SCRIPT"

  echo "Dumping default prover db init script"
  curl --output "$directory/prover-db-init.sql" "$ZKEVM_NODE_INIT_PROVER_DB_DEFAULT_SCRIPT"

  echo "Dumping default zkevm-prover config"
  curl --output "$directory/zkevm-prover-config.json" "$ZKEVM_PROVER_DEFAULT_CONFIG"

  echo "Dumping default zkevm-executor config"
  curl --output "$directory/zkevm-executor-config.json" "$ZKEVM_EXECUTOR_DEFAULT_CONFIG"

  echo "Dumping default zkevm-bridge-ui config"
  curl --output "$directory/zkevm-bridge-ui.env" "$ZKEVM_BRIDGE_UI_DEFAULT_CONFIG"

  # Normalize TOML files.
  for file in "$directory"/*.toml; do
    echo "Normalizing $file"
    normalize_toml_file "$file"
  done
}

dump_current_zkevm_configs() {
  directory="${1%/}"
  ENCLAVE="cdk-v1"
  echo "Dumping current zkevm configurations from kurtosis $ENCLAVE enclave in $directory..."

  # Dump current configs from the Kurtosis enclave.
  echo "Dumping current zkevm-node config"
  kurtosis service exec "$ENCLAVE" zkevm-node-rpc-001 "cat /etc/zkevm/node-config.toml" | tail -n +2 > "$directory/zkevm-node-config.toml"

  echo "Dumping current zkevm-agglayer config"
  kurtosis service exec "$ENCLAVE" zkevm-agglayer-001 "cat /etc/zkevm/agglayer-config.toml" | tail -n +2 > "$directory/zkevm-agglayer-config.toml"

  echo "Dumping current cdk-data-availability config"
  kurtosis service exec "$ENCLAVE" zkevm-dac-001 "cat /etc/zkevm/dac-config.toml" | tail -n +2 > "$directory/cdk-data-availability-config.toml"

  echo "Dumping current zkevm-bridge-service config"
  kurtosis service exec "$ENCLAVE" zkevm-bridge-service-001 "cat /etc/zkevm/bridge-config.toml" | tail -n +2 > "$directory/zkevm-bridge-service-config.toml"

  echo "Dumping current event db init script"
  kurtosis service exec "$ENCLAVE" event-db-001 "cat /docker-entrypoint-initdb.d/event-db-init.sql" | tail -n +2 > "$directory/event-db-init.sql"

  echo "Dumping current prover db init script"
  kurtosis service exec "$ENCLAVE" prover-db-001 "cat /docker-entrypoint-initdb.d/prover-db-init.sql" | tail -n +2 > "$directory/prover-db-init.sql"

  echo "Dumping current zkevm-prover config"
  kurtosis service exec "$ENCLAVE" zkevm-prover-001 "cat /etc/zkevm/prover-config.json" | tail -n +2 > "$directory/zkevm-prover-config.json"

  echo "Dumping current zkevm-executor config"
  kurtosis service exec "$ENCLAVE" zkevm-executor-pless-001 "cat /etc/zkevm/executor-config.json" | tail -n +2 > "$directory/zkevm-executor-config.json"

  echo "Dumping current zkevm-bridge-ui config"
  kurtosis service exec "$ENCLAVE" zkevm-bridge-ui-001 "cat /etc/zkevm/.env" | tail -n +2 | sort > "$directory/zkevm-bridge-ui.env"

  # Normalize TOML files.
  for file in "$directory"/*.toml; do
    echo "Normalizing $file"
    normalize_toml_file "$file"
  done
}

compare_files_keys() {
  file1="$1"
  file2="$2"
  echo "Comparing files keys: $file1 <> $file2"

  extension="${file1##*.}"
  case "$extension" in
    toml)
      keys1="$(tomlq -r '[paths | join(".")]' "$file1")"
      keys2="$(tomlq -r '[paths | join(".")]' "$file2")"
      ;;
    json)
      keys1="$(jq -r '[paths | join(".")]' "$file1")"
      keys2="$(jq -r '[paths | join(".")]' "$file2")"
      ;;
    *)
      echo "Unsupported file format: ${file1##*.}"
      exit 1
      ;;
  esac

  keys_exclusive_to_file1=$(jq -n --argjson k1 "$keys1" --argjson k2 "$keys2" '$k1 - $k2')
  echo; echo "Keys exclusive to $file1:"
  echo "$keys_exclusive_to_file1"

  keys_exclusive_to_file2=$(jq -n --argjson k1 "$keys1" --argjson k2 "$keys2" '$k2 - $k1')
  echo; echo "Keys exclusive to $file2:"
  echo "$keys_exclusive_to_file2"

  # if [ "$(echo "$diff" | jq length)" -gt 0 ]; then
  #   if [ "$CI" = "true" ]; then
  #     echo "::warning file={$file}::The configuration file lacks some properties present in the default file"
  #   fi
  #   echo "The config file $file lacks some properties present in the default file:"
  #   echo "$diff"
  # fi
}

compare_configs() {
  default_directory="${1%/}"
  current_directory="${2%/}"

  echo "Comparing configs in $default_directory/ and $current_directory/..."
  find "$default_directory" -type f \( -name "*.toml" -o -name "*.json" \) | while read -r f; do
    file="$(basename "$f")"
    echo
    if [ -f "$default_directory/$file" ]; then
      compare_files_keys "$default_directory/$file" "$current_directory/$file"
    else
      if [ "$CI" = "true" ]; then
        echo "::warning file={$file}::Missing default file"
      fi
      echo "Missing default file $file"
    fi
  done
}

normalize_toml_file() {
  file="$1"
  tomlq --toml-output --sort-keys 'walk(if type=="object" then with_entries(.key|=ascii_downcase) else . end)' "$file" > "$file.tmp"
  mv "$file.tmp" "$file"
}

# Check the number of arguments
if [ $# -lt 1 ]; then
  echo "Usage: $0 <action> <target>"
  echo "> Dump default configs: $0 dump default"
  echo "> Dump current configs: $0 dump current"
  echo "> Compare default and current configs: $0 compare"
  exit 1
fi

# Determine the action and target based on the arguments
case $1 in
  dump)
    case $2 in
      default)
        directory="$3"
        dump_default_zkevm_configs "$directory"
        ;;
      current)
        directory="$3"
        dump_current_zkevm_configs "$directory"
        ;;
      *)
        echo "Invalid target. Please choose 'current' or 'default'."
        exit 1
        ;;
    esac
    ;;
  compare)
    case $2 in
      files)
        file1="$3"
        file2="$4"
        compare_files_keys "$file1" "$file2"
        ;;
      configs)
        directory1="$3"
        directory2="$4"
        compare_configs "$directory1" "$directory2"
        ;;
    esac
    ;;
  *)
    echo "Invalid action. Please choose 'dump' or 'compare'."
    exit 1
    ;;
esac
