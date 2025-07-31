#!/bin/bash

COMBINATIONS_FOLDER="combinations"
MATRIX_VERSION_FILE="matrix.yml"
MATRIX_VERSION_README="../../CDK_VERSION_MATRIX.MD"

# Extracts the base file name from a full path, removing the directory path and the .yml extension.
# e.g. get_file_name "forks/fork10.yml" should return "fork10".
extract_base_name() {
    echo "$1" | sed 's|.*/||; s|\.yml$||'
}

# Convert a YML array into a Markdown table.
yml2md() {
    echo "Fork ID|Consensus|CDK Erigon|ZkEVM Prover|Agglayer Contracts|Data Availability|Bridge"
    echo "---|---|---|---|---|---|---"
    yq -r '
        to_entries |
        sort_by(.value.fork_id | tonumber) | reverse |
        map(
            "\(.value.fork_id)|\(.value.consensus)|[\(.value.cdk_erigon.version)](\(.value.cdk_erigon.source))|[\(.value.zkevm_prover.version)](\(.value.zkevm_prover.source))|[\(.value.agglayer_contracts.version)](\(.value.agglayer_contracts.source))|[\(.value.data_availability.version)](\(.value.data_availability.source))|[\(.value.bridge_service.version)](\(.value.bridge_service.source))"
        ) |
        join("\n")
    ' "$1"
}

# Save version matrix for a fork-consensus combination.
save_version_matrix() {
    local fork_id="$1"
    local consensus="$2"
    local erigon_version="$3"
    local output_file="$4"

    # shellcheck disable=SC2016
    yq --raw-output \
        --arg fork_id "$fork_id" \
        --arg consensus "$consensus" \
        --arg bridge_version "$default_bridge_version" \
        --arg da_version "$default_da_version" \
        --arg erigon_version "$erigon_version" \
        --yaml-output '{
        ($fork_id + "-" + $consensus): {
            fork_id: $fork_id,
            consensus: $consensus,
            cdk_erigon: {
                version: $erigon_version,
                source: "https://github.com/0xPolygonHermez/cdk-erigon/releases/tag/\($erigon_version)",
            },
            zkevm_prover: {
                version: .args.zkevm_prover_image | split(":")[1],
                source: "https://github.com/0xPolygonHermez/zkevm-prover/releases/tag/\(.args.zkevm_prover_image | split(":")[1] | split("-fork")[0])",
            },
            agglayer_contracts: {
                version: .args.agglayer_contracts_image | split(":")[1],
                source: "https://github.com/agglayer/agglayer-contracts/releases/tag/\(.args.agglayer_contracts_image | split(":")[1])",
            },
            data_availability: {
                version: $da_version,
                source: "https://github.com/0xPolygon/cdk-data-availability/releases/tag/v\($da_version)",
            },
            bridge_service: {
                version: $bridge_version,
                source: "https://github.com/0xPolygonHermez/zkevm-bridge-service/releases/tag/\($bridge_version)",
            },
        }
        }' "$output_file" >>"$MATRIX_VERSION_FILE"
}

true >"$MATRIX_VERSION_FILE"
echo -e "# Polygon CDK Version Matrix\n\nWhich versions of the CDK stack are meant to work together?\n" >"$MATRIX_VERSION_README"

# File combinations.
forks=(forks/*.yml)
consensus=(consensus/*.yml)
components=(components/*.yml)

default_erigon_version="$(grep -E "cdk_erigon_node_image.*hermeznetwork/cdk-erigon" ../../input_parser.star | sed 's#.*hermeznetwork/cdk-erigon:\([^"]*\).*#\1#')"
default_sovereign_erigon_version="$(grep -E "cdk_sovereign_erigon_node_image.*hermeznetwork/cdk-erigon" ../../input_parser.star | sed 's#.*hermeznetwork/cdk-erigon:\([^"]*\).*#\1#')"
default_bridge_version="$(grep -E "zkevm_bridge_service_image.*hermeznetwork" ../../input_parser.star | sed 's#.*hermeznetwork/zkevm-bridge-service:\([^"]*\).*#\1#')"
default_da_version="$(grep -E "zkevm_da_image.*0xpolygon" ../../input_parser.star | sed 's#.*0xpolygon/cdk-data-availability:\([^"]*\).*#\1#')"

# Nested loops to create all combinations.
echo "Creating combinations..."
mkdir -p "$COMBINATIONS_FOLDER"
for fork in "${forks[@]}"; do
    for cons in "${consensus[@]}"; do
        for comp in "${components[@]}"; do
            base_fork="$(extract_base_name "$fork")"
            base_cons="$(extract_base_name "$cons")"
            base_comp="$(extract_base_name "$comp")"

            # The legacy stack doesn't work with fork 12 and 13.
            if [[ ("$base_fork" == "fork12" || "$base_fork" == "fork13") && "$base_comp" == "legacy-zkevm" ]]; then
                continue
            fi

            # The combination of fork 11 with the zkevm stack with validium mode does not work.
            if [[ "$base_fork" == "fork11" && "$base_comp" == "legacy-zkevm" && "$base_cons" == "validium" ]]; then
                continue
            fi

            # cdk-erigon-sovereign only works for fork12 for now.
            if [[ "$base_cons" == "sovereign" && "$base_fork" != "fork12" ]]; then
                continue
            fi

            output_file="$COMBINATIONS_FOLDER/$base_fork-$base_comp-$base_cons.yml"
            echo "# This file has been generated automatically." >"$output_file"
            yq --slurp '.[0] * .[1] * .[2]' "$fork" "$cons" "$comp" --yaml-output >>"$output_file"
            echo "- $output_file"

            # Save version matrix for each fork.
            if [[ "$base_comp" == "cdk-erigon" ]]; then
                fork_id=${base_fork#fork}
                if [[ "$base_cons" == "validium" ]]; then
                    save_version_matrix "$fork_id" "$base_cons" "$default_erigon_version" "$output_file"
                elif [[ "$base_cons" == "sovereign" ]]; then
                    save_version_matrix "$fork_id" "$base_cons" "$default_sovereign_erigon_version" "$output_file"
                fi
            fi
        done
    done
done
yml2md "$MATRIX_VERSION_FILE" >>"$MATRIX_VERSION_README"
echo "All combinations created!"