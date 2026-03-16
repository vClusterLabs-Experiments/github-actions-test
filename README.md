# github-actions-test

Integration tests for [loft-sh/github-actions](https://github.com/loft-sh/github-actions) reusable workflows.

## How it works

This repo contains caller workflows that exercise each reusable workflow from
`loft-sh/github-actions@main`. Tests are triggered in two ways:

1. **`repository_dispatch`** — sent automatically by `loft-sh/github-actions`
   after merging changes to reusable workflows.
2. **`workflow_dispatch`** — manual trigger for on-demand testing.

## Caller workflows

| Workflow | Tests |
|----------|-------|
| `caller-validate-renovate.yaml` | `validate-renovate.yaml` |
| `caller-actionlint.yaml` | `actionlint.yaml` |
| `caller-detect-changes.yaml` | `detect-changes.yaml` |
| `caller-backport.yaml` | `backport.yaml` |
| `caller-clean-github-cache.yaml` | `clean-github-cache.yaml` |
| `caller-cleanup-backport-branches.yaml` | `cleanup-backport-branches.yaml` |

## Integration test orchestrator

`integration-tests.yaml` runs all E2E tests in parallel, creating real PRs,
branches, and GitHub events to exercise each workflow end-to-end.

## Required secrets

| Secret | Purpose |
|--------|---------|
| `GH_ACCESS_TOKEN` | PAT with `repo` scope for creating PRs, merging, deleting branches |
