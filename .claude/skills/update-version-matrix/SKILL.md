---
name: update-version-matrix
description: Bump the image and package pins flagged by the `check-version-matrix` job, regenerate docs/docs/version-matrix.md and open a PR. Use when given a check-version-matrix job URL, or asked to "bump the versions" / "update the version matrix". Also run unattended by .github/workflows/bump-version-matrix.yml.
---

# Update the version matrix

Image pins live in `src/package_io/constants.star`; Kurtosis package pins in the
`replace` block of `kurtosis.yml`. `scripts/version-matrix/version-matrix-system.md`
is the source of truth for how the scripts work.

## 1. Read the drift

From a job URL:

```bash
gh run view <run> --log --job <job> | grep -E '\s[-+]\|' | sed 's/.*Z //'
```

Otherwise regenerate (step 3) on a fresh `origin/main` and read
`git diff docs/docs/version-matrix.md`. The `+` rows are the new matrix. Keep only
rows marked 🚨 (behind stable). Skip:

- 📌 `pinned` rows: deliberate holds declared in `PINNED_VERSIONS` in
  `extract-versions.py`. Pins are per environment, so a component 📌 in one
  environment and 🚨 in another still needs bumping in the second.
- Pre-releases (`rc`, `beta`, `alpha`): flag them instead.
- The same component appears once per environment: it is one bump.

Before bumping, check the new image is published:
`docker manifest inspect <image>:<tag>`. A release often lands before its image
(agglayer images take ~30 min). Skip unpublished ones and say so in the PR.

## 2. Bump

- Replace the **full image reference** (`sigp/lighthouse:v8.2.2` →
  `…:v8.2.3`), not the bare version: `8.2.2` can match unrelated things.
- Grep the repo for the old reference and update every copy (docs, `.github/`
  configs, `README`), excluding `node_modules` and lock files. The matrix only
  reads the constants, so stale copies elsewhere are not caught by CI.
- A `kurtosis.yml` package bump is a commit SHA + date comment; then run
  `python3 scripts/version-matrix/verify-package-pins.py`.

## 3. Regenerate

```bash
GITHUB_TOKEN="${GITHUB_TOKEN:-$(gh auth token)}" python3 scripts/version-matrix/extract-versions.py
python3 scripts/version-matrix/generate-markdown.py
git diff --stat
```

In CI, `GITHUB_TOKEN` is already set: run both scripts without the prefix.

Check the bumped rows are now ✅ and nothing else flipped. If another dep drifted
since the nightly, bump it too rather than leaving a 🚨 row.

## 4. Checks

In CI, only `kurtosis lint .`: the PR's own CI runs the rest.

`kurtosis lint .` when a `.star` file changed. `rumdl` and `typos` already have
findings on `main`: only act on new ones. The PR's CI deploys a devnet.

## 5. Open the PR

Title: `chore: bump <dep> to <version>`, or `chore: bump <dep>, <dep> and <dep>`.
Body follows `.github/pull_request_template.md` (`## Description` /
`## References`), at most 5 bullets per section: one bullet per bump
`old → [new](release url)`, what was skipped and why (📌, rc, unpublished image).

**Local**: work in a worktree off `origin/main`, commit, push, `gh pr create`, then
`gh pr comment <n> --body "@claude please review"`.

**CI** (run by `bump-version-matrix.yml`): only edit files. Do not commit, push
or open the PR: return the title and body, and the workflow opens or refreshes the
PR. If nothing is left to bump (every drifted row is 📌, rc or unpublished), make
no change and return an empty title.
