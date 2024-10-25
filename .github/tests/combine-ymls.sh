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
            base_fork="$(extract_base_name "$fork")"
            base_da="$(extract_base_name "$da")"
            base_comp="$(extract_base_name "$comp")"


            # The legacy stack doesn't work with fork 12
            if [[ "$base_fork" == "fork12" && "$base_comp" == "legacy-zkevm-stack" ]]; then
                continue
            fi

            # The legacy stack also doesn't work with fork 13
            if [[ "$base_fork" == "fork13" && "$base_comp" == "legacy-zkevm-stack" ]]; then
                continue
            fi

            # The combination of fork 11 with the zkevm stack with validium mode does not work
            if [[ "$base_fork" == "fork11" && "$base_comp" == "legacy-zkevm-stack" && "$base_da" == "cdk-validium" ]]; then
                continue
            fi

            output_file="$COMBINATIONS_FOLDER/$base_fork-$base_comp-$base_da.yml"
            yq --slurp ".[0] * .[1] * .[2]" "$fork" "$da" "$comp" --yaml-output > "$output_file"
            echo "- $output_file"
        done
    done
done
echo "All combinations created!"
