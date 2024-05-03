#!/bin/bash

# This script compares default parameters specified in main.star, kurtosis.yml, and params.yml.
# The true reference for default parameters is params.yml.

echo "Dumping default parameters..."
sed -n '/args={/,/},/p' main.star | sed 's/args=//' | sed 's/},/}/' | yq --yaml-output > default-args.yml
# shellcheck disable=SC2016
sed -n '/```/,/```/p' kurtosis.yml | sed 's/```//' | yq --yaml-output > kurtosis-args.yml
yq --yaml-output .args params.yml > params-args.yml

echo; echo "Diff default-args.yml <> params-args.yml"
diff default-args.yml params-args.yml

echo; echo "Diff kurtosis-args.yml <> params-args.yml"
diff kurtosis-args.yml params-args.yml