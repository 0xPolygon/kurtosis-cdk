#!/bin/bash

# This script compares default parameters specified in three files: `input_parser.star`,
# `kurtosis.yml` and `params.yml` where `params.yml` is the source of truth for default parameters.
# The script outputs the differences between the specified parameters in each file compared to `params.yml`.

INPUT_PARSER_PATH="../../input_parser.star"
PARAMS_YML_PATH="../../params.yml"

# Extracting default parameters from the different files.
echo "Extracting default parameters from input_parser.star..."
if ! sed -n '/^DEFAULT_ARGS = {/,/^}/ { s/DEFAULT_ARGS = //; s/}/}/; p; }' "$INPUT_PARSER_PATH" | yq -S --yaml-output >.input_parser.star; then
  echo "Error: Failed to extract parameters from input_parser.star."
  exit 1
fi

echo "Extracting default parameters from params.yml..."
if ! yq -S --yaml-output .args "$PARAMS_YML_PATH" >.params.yml; then
  echo "Error: Failed to extract parameters from params.yml."
  exit 1
fi

# Function to compare files and output differences in a structured format
compare_with_source_of_truth() {
  local file1=.params.yml
  local file2=$1

  echo
  echo "🔍 Comparing $file1 and $file2..."
  differences=$(diff "$file1" "$file2" | grep -E '^[<>]')
  if [ -z "$differences" ]; then
    echo "No differences found."
  else
    diff_count=$(echo "$differences" | grep -c '^<')
    echo
    echo "$diff_count differences found:"
    echo

    # Print differences for file1
    echo "📄 $file1 (source of truth)"
    echo "--------------------------------------------------------------------------------"
    while IFS= read -r line; do
      if [[ $line == "<"* ]]; then
        echo "${line:2}"
      fi
    done <<<"$differences"

    echo
    # Print differences for file
    echo "📄 $file2 (🚨 to be updated 🚨)"
    echo "--------------------------------------------------------------------------------"
    while IFS= read -r line; do
      if [[ $line == ">"* ]]; then
        echo "${line:2}"
      fi
    done <<<"$differences"
    exit 1
  fi
}

echo
compare_with_source_of_truth .input_parser.star
