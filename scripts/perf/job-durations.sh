#!/usr/bin/env bash
# Print a Markdown table of how long each job of a workflow run took.
#
# Usage: job-durations.sh <run_id>
#
# Only the latest attempt is listed. Jobs still running (e.g. the one calling
# this script) and skipped ones are left out. Requires GH_TOKEN and
# GITHUB_REPOSITORY.
set -euo pipefail

run_id=$1

jobs=$(gh api --paginate "repos/${GITHUB_REPOSITORY}/actions/runs/${run_id}/jobs?filter=latest" --jq '.jobs[]')

echo "## ⏱ Job durations"
echo
echo "| Job | Result | Duration |"
echo "| --- | --- | --- |"
jq -rs 'map(select(.completed_at != null and .conclusion != "skipped"))
  | map(. + {secs: ((.completed_at | fromdate) - (.started_at | fromdate))})
  | sort_by(.name)[]
  | "| [\(.name)](\(.html_url)) | \(.conclusion) | \(.secs / 60 | floor)m \(.secs % 60 | floor)s |"' <<< "$jobs"
echo
