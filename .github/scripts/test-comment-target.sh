#!/usr/bin/env bash
# shellcheck disable=SC2016 # GitHub expressions and shell snippets are literal fixtures.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
command_workflow="$root/.github/workflows/caller-comment-triggered-check.yaml"
pro_workflow="$root/.github/workflows/caller-e2e-pro-run.yaml"
oss_workflow="$root/.github/workflows/caller-e2e-oss-run.yaml"

assert_contains() {
  local file="$1" value="$2"
  grep -Fq -- "$value" "$file" || {
    printf 'missing from %s: %s\n' "$file" "$value" >&2
    return 1
  }
}

assert_not_contains() {
  local file="$1" value="$2"
  if grep -Fq -- "$value" "$file"; then
    printf 'unexpected in %s: %s\n' "$file" "$value" >&2
    return 1
  fi
}

assert_contains "$command_workflow" 'target: ${{ steps.pro.outputs.target }}'
assert_contains "$command_workflow" 'comment-triggered-check@comment-triggered-check/v1'
assert_not_contains "$command_workflow" 'comment-triggered-check@2a21f174b4a1486e06353e740af9c8822162fa46'
assert_contains "$command_workflow" 'target-name: pro'
assert_contains "$command_workflow" 'target-name: oss'
assert_contains "$command_workflow" "steps.pro.outputs.target == 'oss' || (steps.pro.outputs.target == '' && steps.pro.outputs.should-run == 'true')"
assert_contains "$command_workflow" "if: \${{ needs.prepare.outputs.target != 'oss' }}"
assert_contains "$command_workflow" "if: \${{ needs.prepare.outputs.target != 'pro' }}"
assert_contains "$command_workflow" "steps.pro.outputs.reason != 'target-not-selected'"
assert_contains "$command_workflow" "steps.oss.outputs.reason != 'target-not-selected'"
assert_contains "$command_workflow" "needs.prepare.outputs.target != '' && needs.prepare.outputs.target || 'pro + oss'"
assert_not_contains "$command_workflow" '<!-- e2e-command-error -->'

assert_contains "$pro_workflow" 'empty_conclusion=neutral'
assert_contains "$oss_workflow" 'empty_conclusion=neutral'
assert_not_contains "$pro_workflow" '[[ -n "${CHECK_RUN_ID}" ]] && empty_conclusion=failure'
assert_not_contains "$oss_workflow" '[[ -n "${CHECK_RUN_ID}" ]] && empty_conclusion=failure'

printf 'comment target contract passed\n'
