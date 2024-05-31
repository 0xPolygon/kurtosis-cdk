#!/bin/bash

# This script compares default parameters specified in main.star, kurtosis.yml, and params.yml.
# The true reference for default parameters is params.yml.

echo "Dumping default parameters..."
sed -n '/DEFAULT_ARGS = {/,/}/ { s/DEFAULT_ARGS = //; s/}/}/; p; }' input_parser.star | yq --yaml-output > input-parser-args.yml
# shellcheck disable=SC2016
sed -n '/```yml/,/```/ { /```yml/d; /```/d; p;}' kurtosis.yml | yq --yaml-output > kurtosis-args.yml
yq --yaml-output .args params.yml > params-args.yml

echo; echo "Diff input-parser-args.yml <> params-args.yml"
diff input-parser-args.yml params-args.yml

echo; echo "Diff kurtosis-args.yml <> params-args.yml"
diff kurtosis-args.yml params-args.yml