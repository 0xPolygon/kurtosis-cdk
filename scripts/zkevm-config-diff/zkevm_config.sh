#!/bin/bash
# This script is a simple tool to compare our kurtosis-cdk configurations with the default ones and list any missing or unnecessary fields.
# Here is how it should be used:

# Dump the default zkevm configuration to the default-configs/ folder.
# The versions of the zkevm components will be fetched from params.yml.
# $ mkdir -p default-configs (or rm -rf ./default-configs/* if the folder is not empty)
# $ sh zkevm_config.sh dump default ./default-configs

# Dump the kurtosis CDK configuration to the kurtosis-cdk-configs/ folder.
# $ mkdir -p kurtosis-cdk-configs (or rm -rf ./kurtosis-cdk-configs/* if the folder is not empty)
# $ sh zkevm_config.sh dump kurtosis-cdk ./kurtosis-cdk-configs

# Compare default and kurtosis-cdk configurations.
# $ sh zkevm_config.sh compare configs ./default-configs ./kurtosis-cdk-configs

# Compare two specific files.
# $ sh zkevm_config.sh compare files ./default-configs/cdk-data-availability-config.toml ./kurtosis-cdk-configs/cdk-data-availability-config.toml

params_path="../../params.yml"

set_zkevm_components_versions() {
  echo "Updating zkevm component versions in the go.mod file using values from params.yml"

  cdk_validium_node_version="v$(yq -r .args.zkevm_node_image "$params_path" | cut -d':' -f 2 | sed 's/-/+/g')"
  echo "Using cdk validium node version: $cdk_validium_node_version"
  sed "s|github.com/0xPolygon/cdk-validium-node .*|github.com/0xPolygon/cdk-validium-node $cdk_validium_node_version|g" go.mod > go.mod.new
  mv go.mod.new go.mod
  go mod tidy

  zkevm_da_version="v$(yq -r .args.zkevm_da_image "$params_path" | cut -d':' -f 2)"
  echo "Using zkevm da version: $zkevm_da_version"
  go get "github.com/0xPolygon/cdk-data-availability@$zkevm_da_version"

  zkevm_agglayer_version="v$(yq -r .args.zkevm_agglayer_image "$params_path" | cut -d':' -f 2)"
  echo "Using zkevm agglayer version: $zkevm_agglayer_version"
  go get "github.com/0xPolygon/agglayer@$zkevm_agglayer_version"

  # TODO: Use a tagged version for the zkevm bridge service once a new release including this commit has been created:
  # https://github.com/0xPolygonHermez/zkevm-bridge-service/commit/48f8b52b09ae3b1fe1b854d03424d5fac1b4149b
  #zkevm_bridge_service_version="$(yq -r .args.zkevm_bridge_service_image "$params_path" | cut -d':' -f 2)"
  zkevm_bridge_service_version="develop"
  echo "Using zkevm bridge service version: $zkevm_bridge_service_version"
  go get "github.com/0xPolygonHermez/zkevm-bridge-service@$zkevm_bridge_service_version"
}

dump_default_zkevm_configs() {
  directory="${1%/}"
  echo "Dumping default zkevm configurations in $directory/"

  # Dump default configs of zkevm components written in go.
  go run dump_zkevm_default_config.go "$directory"

  # Dump default configs of the rest of the zkevm components, not written in go.
  cdk_validium_node_version="v$(yq -r .args.zkevm_node_image "$params_path" | cut -d':' -f 2 | sed 's/-/+/g')"
  ZKEVM_NODE_INIT_EVENT_DB_DEFAULT_SCRIPT="https://raw.githubusercontent.com/0xPolygon/cdk-validium-node/$cdk_validium_node_version/db/scripts/init_event_db.sql"
  ZKEVM_NODE_INIT_PROVER_DB_DEFAULT_SCRIPT="https://raw.githubusercontent.com/0xPolygon/cdk-validium-node/$cdk_validium_node_version/db/scripts/init_prover_db.sql"

  zkevm_prover_version="$(yq -r .args.zkevm_prover_image "$params_path" | cut -d':' -f 2)"
  ZKEVM_PROVER_DEFAULT_CONFIG="https://raw.githubusercontent.com/0xPolygonHermez/zkevm-prover/$zkevm_prover_version/config/config_prover.json"
  ZKEVM_EXECUTOR_DEFAULT_CONFIG="https://raw.githubusercontent.com/0xPolygonHermez/zkevm-prover/$zkevm_prover_version/config/config_executor.json"

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

dump_kurtosis_cdk_configs() {
  directory="${1%/}"
  ENCLAVE="cdk-v1"
  echo "Dumping kurtosis-cdk configurations from kurtosis $ENCLAVE enclave in $directory"

  # Dump kurtosis-cdk configs from the Kurtosis enclave.
  echo "Dumping kurtosis-cdk zkevm-node config"
  kurtosis service exec "$ENCLAVE" zkevm-node-rpc-001 "cat /etc/zkevm/node-config.toml" | tail -n +2 > "$directory/zkevm-node-config.toml"

  echo "Dumping kurtosis-cdk zkevm-agglayer config"
  kurtosis service exec "$ENCLAVE" zkevm-agglayer-001 "cat /etc/zkevm/agglayer-config.toml" | tail -n +2 > "$directory/zkevm-agglayer-config.toml"

  echo "Dumping kurtosis-cdk cdk-data-availability config"
  kurtosis service exec "$ENCLAVE" zkevm-dac-001 "cat /etc/zkevm/dac-config.toml" | tail -n +2 > "$directory/cdk-data-availability-config.toml"

  echo "Dumping kurtosis-cdk zkevm-bridge-service config"
  kurtosis service exec "$ENCLAVE" zkevm-bridge-service-001 "cat /etc/zkevm/bridge-config.toml" | tail -n +2 > "$directory/zkevm-bridge-service-config.toml"

  echo "Dumping kurtosis-cdk event db init script"
  kurtosis service exec "$ENCLAVE" event-db-001 "cat /docker-entrypoint-initdb.d/event-db-init.sql" | tail -n +2 > "$directory/event-db-init.sql"

  echo "Dumping kurtosis-cdk prover db init script"
  kurtosis service exec "$ENCLAVE" prover-db-001 "cat /docker-entrypoint-initdb.d/prover-db-init.sql" | tail -n +2 > "$directory/prover-db-init.sql"

  echo "Dumping kurtosis-cdk zkevm-prover config"
  kurtosis service exec "$ENCLAVE" zkevm-prover-001 "cat /etc/zkevm/prover-config.json" | tail -n +2 > "$directory/zkevm-prover-config.json"

  echo "Dumping kurtosis-cdk zkevm-executor config"
  kurtosis service exec "$ENCLAVE" zkevm-executor-pless-001 "cat /etc/zkevm/executor-config.json" | tail -n +2 > "$directory/zkevm-executor-config.json"

  echo "Dumping kurtosis-cdk zkevm-bridge-ui config"
  kurtosis service exec "$ENCLAVE" zkevm-bridge-ui-001 "cat /etc/zkevm/.env" | tail -n +2 | sort > "$directory/zkevm-bridge-ui.env"

  # Normalize TOML files.
  for file in "$directory"/*.toml; do
    echo "Normalizing $file"
    normalize_toml_file "$file"
  done
}

normalize_toml_file() {
  file="$1"
  tomlq --toml-output --sort-keys 'walk(if type=="object" then with_entries(.key|=ascii_downcase) else . end)' "$file" > "$file.tmp"
  mv "$file.tmp" "$file"
}

jq_query_get_leaf_keys='
  def getLeafKeys:
    path(.. | select(type != "array" and type != "object"));

  def removeArrayIndices:
    if type == "array" then
      map(select(type != "number"))
    else
      .
    end;

  [getLeafKeys | removeArrayIndices | join(".")] | unique
'

get_config_keys() {
  config_file="$1"
  extension="${config_file##*.}"

  case "$extension" in
    toml)
      keys="$(tomlq -r "$jq_query_get_leaf_keys" "$config_file")"
      ;;
    json)
      keys="$(jq -r "$jq_query_get_leaf_keys" "$config_file")"
      ;;
    *)
      echo "Unsupported file format: $extension"
      exit 1
      ;;
  esac

  echo "$keys"
}

find_missing_keys_in_kurtosis_cdk_config_file() {
  default_config_file="$1"
  kurtosis_cdk_config_file="$2"

  default_config_keys="$(get_config_keys "$default_config_file")"
  kurtosis_cdk_config_keys="$(get_config_keys "$kurtosis_cdk_config_file")"

  filename="$(basename "$kurtosis_cdk_config_file" | cut -d'.' -f 1)"
  missing_keys=$(jq -n --argjson d "$default_config_keys" --argjson c "$kurtosis_cdk_config_keys" '$d - $c')
  echo "$missing_keys" > "diff/$filename-missing-keys.json"
  if [ "$(echo "$missing_keys" | jq length)" -gt 0 ]; then
    if [ "$CI" = "true" ]; then
      echo "::warning::$kurtosis_cdk_config_file lacks some properties present in $default_config_file."
      echo "$missing_keys"
    else
      echo "diff/$filename-missing-keys.json"
    fi
  else
    echo "No missing keys in $kurtosis_cdk_config_file."
  fi
}

find_unnecessary_keys_in_kurtosis_cdk_config_file() {
  default_config_file="$1"
  kurtosis_cdk_config_file="$2"

  default_config_keys="$(get_config_keys "$default_config_file")"
  kurtosis_cdk_config_keys="$(get_config_keys "$kurtosis_cdk_config_file")"

  filename="$(basename "$kurtosis_cdk_config_file" | cut -d'.' -f 1)"
  unnecessary_keys=$(jq -n --argjson d "$default_config_keys" --argjson c "$kurtosis_cdk_config_keys" '$c - $d')
  echo "$unnecessary_keys" > "diff/$filename-unnecessary-keys.json"
  if [ "$(echo "$unnecessary_keys" | jq length)" -gt 0 ]; then
    if [ "$CI" = "true" ]; then
      echo "::error::$kurtosis_cdk_config_file defines unnecessary properties that are not in $default_config_file."
      echo "$unnecessary_keys"
    else
      echo "diff/$filename-unnecessary-keys.json"
    fi
  else
    echo "No unnecessary keys in $kurtosis_cdk_config_file."
  fi
}

compare_files_keys() {
  default_file="$1"
  kurtosis_cdk_file="$2"

  echo "Comparing $default_file and $kurtosis_cdk_file:"
  mkdir -p diff/
  find_missing_keys_in_kurtosis_cdk_config_file "$default_file" "$kurtosis_cdk_file"
  find_unnecessary_keys_in_kurtosis_cdk_config_file "$default_file" "$kurtosis_cdk_file"
}

diff_files() {
  file1="$1"
  file2="$2"
  filename="$(basename "$file2" | cut -d'.' -f 1)"
  diff "$file1" "$file2" > "diff/$filename.diff"
  if [ "$CI" != "true" ]; then
    echo "diff/$filename.diff"
  fi
}

compare_configs_keys() {
  default_directory="${1%/}"
  kurtosis_cdk_directory="${2%/}"

  echo "Comparing configs in $default_directory/ and $kurtosis_cdk_directory/"
  mkdir -p diff/
  find "$default_directory" -type f \( -name "*.toml" -o -name "*.json" \) | while read -r f; do
    file="$(basename "$f")"
    echo
    if [ -f "$default_directory/$file" ]; then
      compare_files_keys "$default_directory/$file" "$kurtosis_cdk_directory/$file"
      diff_files "$default_directory/$file" "$kurtosis_cdk_directory/$file"
    else
      if [ "$CI" = "true" ]; then
        echo "::warning file={$file}::Missing default file"
      fi
      echo "Missing default file $file"
    fi
  done

  echo; echo "Comparing $default_directory/event-db-init.sql and $kurtosis_cdk_directory/event-db-init.sql"
  diff_files "$default_directory/event-db-init.sql" "$kurtosis_cdk_directory/event-db-init.sql"
  cat "diff/event-db-init.diff"

  echo; echo "Comparing $default_directory/prover-db-init.sql and $kurtosis_cdk_directory/prover-db-init.sql"
  diff_files "$default_directory/prover-db-init.sql" "$kurtosis_cdk_directory/prover-db-init.sql"
  cat "diff/prover-db-init.diff"

  echo; echo "Comparing $default_directory/zkevm-bridge-ui.env and $kurtosis_cdk_directory/zkevm-bridge-ui.env"
  diff_files "$default_directory/zkevm-bridge-ui.env" "$kurtosis_cdk_directory/zkevm-bridge-ui.env"
  cat "diff/zkevm-bridge-ui.diff"
}

# Check the number of arguments
if [ $# -lt 1 ]; then
  echo "Usage: $0 <action> <target>"
  echo "> Dump default configs: $0 dump default <directory>"
  echo "> Dump kurtosis_cdk configs: $0 dump kurtosis-cdk <directory>"
  echo "> Compare default and kurtosis-cdk configs: $0 compare configs <directory1> <directory2>"
  echo "> Compare files: $0 compare files <file1> <file2>"
  exit 1
fi

# Determine the action and target based on the arguments
case $1 in
  dump)
    case $2 in
      default)
        set_zkevm_components_versions
        echo

        directory="$3"
        dump_default_zkevm_configs "$directory"
        ;;
      kurtosis-cdk)
        directory="$3"
        dump_kurtosis_cdk_configs "$directory"
        ;;
      *)
        echo "Invalid target. Please choose 'default' or 'kurtosis-cdk'."
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
        compare_configs_keys "$directory1" "$directory2"
        ;;
    esac
    ;;
  *)
    echo "Invalid action. Please choose 'dump' or 'compare'."
    exit 1
    ;;
esac
