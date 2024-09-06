#!/bin/bash

COMBINATIONS_FOLDER="combinations"

# Extracts the base file name from a full path, removing the directory path and the .yml extension.
# e.g. get_file_name "forks/fork10.yml" should return "fork10".
extract_base_name() {
    echo "$1" | sed 's|.*/||; s|\.yml$||'
}

# File combinations.
forks=(forks/*.yml)
data_availability=(da-modes/*.yml)
components=(components/*.yml)

# Nested loops to create all combinations.
echo "Creating combinations..."
mkdir -p "$COMBINATIONS_FOLDER"
for fork in "${forks[@]}"; do
    for da in "${data_availability[@]}"; do
        for comp in "${components[@]}"; do
            # Skipping tests for zkevm-node and cdk-validium-node with fork 11 and fork 12, as they are currently not supported.
            if [ "$(extract_base_name "$comp")" == "legacy-zkevm-stack" ] && {
                [ "$(extract_base_name "$fork")" == "fork11" ] || [ "$(extract_base_name "$fork")" == "fork12" ];
            }; then
                continue
            fi

            output_file="$COMBINATIONS_FOLDER/$(extract_base_name "$fork")-$(extract_base_name "$comp")-$(extract_base_name "$da").yml"
            yq --slurp ".[0] * .[1] * .[2]" "$fork" "$da" "$comp" --yaml-output > "$output_file"
            echo "- $output_file"
        done
    done
done
echo "All combinations created!"
