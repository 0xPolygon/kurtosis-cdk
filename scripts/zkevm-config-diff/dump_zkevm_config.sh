#!/bin/bash
# This script will dump default and current configurations used in the CDK stack.

normalize_toml_file() {
  file="$1"
  tomlq --toml-output --sort-keys 'walk(if type=="object" then with_entries(.key|=ascii_downcase) else . end)' "$file" > "$file.tmp"
  mv "$file.tmp" "$file"
}

dump_default_configs() {
  ZKEVM_NODE_INIT_EVENT_DB_DEFAULT_SCRIPT="https://raw.githubusercontent.com/0xPolygonHermez/zkevm-node/develop/db/scripts/init_event_db.sql"
  ZKEVM_NODE_INIT_PROVER_DB_DEFAULT_SCRIPT="https://raw.githubusercontent.com/0xPolygonHermez/zkevm-node/develop/db/scripts/init_prover_db.sql"
  ZKEVM_PROVER_DEFAULT_CONFIG="https://raw.githubusercontent.com/0xPolygonHermez/zkevm-prover/main/config/config_prover.json"
  ZKEVM_EXECUTOR_DEFAULT_CONFIG="https://raw.githubusercontent.com/0xPolygonHermez/zkevm-prover/main/config/config_executor.json"
  ZKEVM_BRIDGE_UI_DEFAULT_CONFIG="https://raw.githubusercontent.com/0xPolygonHermez/zkevm-bridge-ui/develop/.env.example"

  echo "Dumping default zkevm configurations..."

  # Dump zkevm components default configs (written in go).
  go run dump_zkevm_default_config.go

  # Dump the other configs.
  echo "Dumping default event db init script"
  curl --output default/event-db-init.sql "$ZKEVM_NODE_INIT_EVENT_DB_DEFAULT_SCRIPT"

  echo "Dumping default prover db init script"
  curl --output default/prover-db-init.sql "$ZKEVM_NODE_INIT_PROVER_DB_DEFAULT_SCRIPT"

  echo "Dumping default zkevm-prover config"
  curl --output default/zkevm-prover-config.json "$ZKEVM_PROVER_DEFAULT_CONFIG"

  echo "Dumping default zkevm-executor config"
  curl --output default/zkevm-executor-config.json "$ZKEVM_EXECUTOR_DEFAULT_CONFIG"

  echo "Dumping default zkevm-bridge-ui config"
  curl --output default/zkevm-bridge-ui.env "$ZKEVM_BRIDGE_UI_DEFAULT_CONFIG"

  # Normalize toml files.
  for file in ./default/*.toml; do
    echo "Normalizing $file"
    normalize_toml_file "$file"
  done
}

dump_current_configs() {
  CURRENT_CONFIG_FOLDER="current/"
  ENCLAVE="cdk-v1"

  echo "Dumping current zkevm configurations..."
  mkdir -p "$CURRENT_CONFIG_FOLDER"

  # Dump all the current configs from the kurtosis enclave.
  echo "Dumping current zkevm-node config"
  kurtosis service exec "$ENCLAVE" zkevm-node-rpc-001 "cat /etc/zkevm/node-config.toml" | tail -n +2 > "$CURRENT_CONFIG_FOLDER/zkevm-node-config.toml"

  echo "Dumping current zkevm-agglayer config"
  kurtosis service exec "$ENCLAVE" zkevm-agglayer-001 "cat /etc/zkevm/agglayer-config.toml" | tail -n +2 > "$CURRENT_CONFIG_FOLDER/zkevm-agglayer-config.toml"

  echo "Dumping current cdk-data-availability config"
  kurtosis service exec "$ENCLAVE" zkevm-dac-001 "cat /etc/zkevm/dac-config.toml" | tail -n +2 > "$CURRENT_CONFIG_FOLDER/cdk-data-availability-config.toml"

  echo "Dumping current zkevm-bridge-service config"
  kurtosis service exec "$ENCLAVE" zkevm-bridge-service-001 "cat /etc/zkevm/bridge-config.toml" | tail -n +2 > "$CURRENT_CONFIG_FOLDER/zkevm-bridge-service-config.toml"

  echo "Dumping current event db init script"
  kurtosis service exec "$ENCLAVE" event-db-001 "cat /docker-entrypoint-initdb.d/event-db-init.sql" | tail -n +2 > "$CURRENT_CONFIG_FOLDER/event-db-init.sql"

  echo "Dumping current prover db init script"
  kurtosis service exec "$ENCLAVE" prover-db-001 "cat /docker-entrypoint-initdb.d/prover-db-init.sql" | tail -n +2 > "$CURRENT_CONFIG_FOLDER/prover-db-init.sql"

  echo "Dumping current zkevm-prover config"
  kurtosis service exec "$ENCLAVE" zkevm-prover-001 "cat /etc/zkevm/prover-config.json" | tail -n +2 > "$CURRENT_CONFIG_FOLDER/zkevm-prover-config.json"

  echo "Dumping current zkevm-executor config"
  kurtosis service exec "$ENCLAVE" zkevm-executor-pless-001 "cat /etc/zkevm/executor-config.json" | tail -n +2 > "$CURRENT_CONFIG_FOLDER/zkevm-executor-config.json"

  echo "Dumping current zkevm-bridge-ui config"
  kurtosis service exec "$ENCLAVE" zkevm-bridge-ui-001 "cat /etc/zkevm/.env" | tail -n +2 | sort > "$CURRENT_CONFIG_FOLDER/zkevm-bridge-ui.env"

  # Normalize toml files.
  for file in ./current/*.toml; do
    echo "Normalizing $file"
    normalize_toml_file "$file"
  done
}

compare_files_keys() {
  file1="$1"
  file2="$2"

  extension="$(echo "$file1" | awk -F . '{print $NF}')"
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
      return 1
      ;;
  esac

  diff=$(jq -n --argjson k1 "$keys1" --argjson k2 "$keys2" '$k1 - $k2')
  if [ "$(echo "$diff" | jq length)" -gt 0 ]; then
    if [ "$CI" = "true" ]; then
      echo "::warning file={$file}::The configuration file lacks some properties present in the default file"
    fi
    echo "The config file $file lacks some properties present in the default file:"
    echo "$diff"
  fi


}

compare_configs() {
  echo "Comparing default and current configs..."
  find ./current -type f \( -name "*.toml" -o -name "*.json" \) | while read -r f; do
    file="$(basename "$f")"
    echo
    if [ -f "default/$file" ]; then
      compare_files_keys "default/$file" "current/$file"
    else
      if [ "$CI" = "true" ]; then
        echo "::warning file={$file}::Missing default file"
      fi
      echo "Missing default file $file"
    fi
  done
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
      current)
        dump_current_configs
        ;;
      default)
        dump_default_configs
        ;;
      *)
        echo "Invalid target. Please choose 'current' or 'default'."
        exit 1
        ;;
    esac
    ;;
  compare)
    compare_configs
    ;;
  *)
    echo "Invalid action. Please choose 'dump' or 'compare'."
    exit 1
    ;;
esac
