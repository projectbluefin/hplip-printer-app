# AGENTS.md

Bluefin fork of OpenPrinting's HPLIP Printer Application, built as an FSDK/BuildStream OCI appliance on PAPPL. See `README.md` for the build, release and plugin details.

## Checks and CI

- **`validate`** (`.github/workflows/validate.yml`): runs `pre-commit run --all-files` on `pull_request` and `merge_group`: `actionlint`, YAML/JSON/toml hygiene, and `no-floating-action-tags` (third-party actions must be pinned to a full SHA). Required in the `main` ruleset. Run `pre-commit run --all-files` before every commit.
- **FSDK OCI CI** (`.github/workflows/fsdk-ci.yml`): pull requests run `just validate` (BuildStream graph and entrypoint checks); the merge queue runs the full native x86_64 and aarch64 build plus `just verify`.
- **Plugin and discovery checks** (`plugin-*.yml`, `hp-*.yml`): host-only C and shell tests under `tests/`.
- **Scorecard** (`.github/workflows/scorecard.yml`): OpenSSF Scorecard supply-chain check.

## Issues, pull requests and labels

Prow drives review and merge commands: `/` commands in comments set labels, reviewers and approvals, and Prow merges through the merge queue on `lgtm` + `approved` (approvers come from `OWNERS`). See [Prow commands](https://github.com/cncf/prow-github-actions/blob/v3.0.1/docs/commands.md) and [how issues and PRs work here](https://github.com/projectbluefin/common/blob/main/docs/skills/label-workflow.md). Repository Prow overrides live in `.github/prow.yaml`. Hive manages contributor work and its metadata labels, including the `needs-human` agent opt-out; do not remove these merely because they are outside Prow's catalog.

## Branches and releases

Target `main` for development and fsdk-containers updates. There is no manual promotion step: every push to `main` (each one already passed the merge queue's full build) is rebuilt, verified with `just verify` and published by `registry-actions.yml` as a signed amd64+arm64 GHCR index, which then moves `<VERSION>` and `stable` to that commit (never backwards to an ancestor of what `stable` already carries). Reverting a PR is the rollback. Identify a build by its immutable `sha-<commit>` tag or digest; see `README.md` for the full tag contract.
