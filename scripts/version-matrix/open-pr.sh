#!/usr/bin/env bash
# Commit the working-tree changes to a fresh branch through the GitHub API and
# open a PR against main. API commits made with an app token are signed by
# GitHub, which satisfies the required_signatures rule on main.
#
# Usage: open-pr.sh <title> <body-file>
# Requires GH_TOKEN (the Claude GitHub App token inside claude-code-action, so
# that the PR triggers CI) and GITHUB_REPOSITORY.
set -euo pipefail

BRANCH="chore/bump-version-matrix"
title="$1"
body_file="$2"
repo="${GITHUB_REPOSITORY:?}"

# The body file may sit in the repo (the CI agent can only write there): skip it.
mapfile -t changed < <(git status --porcelain --untracked-files=all | cut -c4- | grep -vxF "$body_file" || true)
if [[ ${#changed[@]} -eq 0 ]]; then
  echo "No changes to commit."
  exit 0
fi
for path in "${changed[@]}"; do
  if [[ "$path" == .github/workflows/* ]]; then
    echo "Refusing to commit workflow changes: $path" >&2
    exit 1
  fi
done

if [[ -n "$(gh pr list --repo "$repo" --head "$BRANCH" --state open --json number --jq '.[]')" ]]; then
  echo "A bump PR is already open on $BRANCH." >&2
  exit 1
fi
# Leftover branch from a merged or closed PR.
gh api -X DELETE "repos/$repo/git/refs/heads/$BRANCH" >/dev/null 2>&1 || true

# Branch off main's tip, not HEAD: the checkout may be another branch.
base_sha="$(gh api "repos/$repo/git/ref/heads/main" --jq .object.sha)"
gh api "repos/$repo/git/refs" -f ref="refs/heads/$BRANCH" -f sha="$base_sha" >/dev/null

additions='[]'
deletions='[]'
for path in "${changed[@]}"; do
  if [[ -f "$path" ]]; then
    additions="$(jq --arg p "$path" --arg c "$(base64 -w0 "$path")" '. + [{path: $p, contents: $c}]' <<<"$additions")"
  else
    deletions="$(jq --arg p "$path" '. + [{path: $p}]' <<<"$deletions")"
  fi
done

jq -n \
  --arg repo "$repo" --arg branch "$BRANCH" --arg oid "$base_sha" --arg msg "$title" \
  --argjson additions "$additions" --argjson deletions "$deletions" \
  '{
    query: "mutation($input: CreateCommitOnBranchInput!) { createCommitOnBranch(input: $input) { commit { oid } } }",
    variables: { input: {
      branch: { repositoryNameWithOwner: $repo, branchName: $branch },
      message: { headline: $msg },
      expectedHeadOid: $oid,
      fileChanges: { additions: $additions, deletions: $deletions }
    } }
  }' | gh api graphql --input - >/dev/null

gh pr create --repo "$repo" --base main --head "$BRANCH" --title "$title" --body-file "$body_file"
