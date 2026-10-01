#!/usr/bin/env bash
# Live scenarios for /test-e2e on fork pull requests (DEVOPS-1541).
#
# Opens real pull requests from your fork, comments the command, and asserts on
# the check-runs the command workflow publishes. Closes everything it opened on
# exit. See README.md for the scenarios and prerequisites.
set -euo pipefail

UPSTREAM="${UPSTREAM:-vClusterLabs-Experiments/github-actions-test}"
FORK="${FORK:-$(gh api user --jq .login)/github-actions-test}"
# A commit from before the contract file landed, standing in for an old release line.
NO_CONTRACT_SHA="${NO_CONTRACT_SHA:-9c994e6}"
NO_CONTRACT_BRANCH="release-no-contract"
TIMEOUT="${TIMEOUT:-900}"
RUN="fork-$(date +%s)"

WORK="$(mktemp -d)"
OPENED=()
FAILED=0

cleanup() {
  for pr in "${OPENED[@]}"; do
    gh pr close "$pr" -R "$UPSTREAM" --delete-branch >/dev/null 2>&1 || true
  done
  rm -rf "$WORK"
}
trap cleanup EXIT

log() { printf '\n==> %s\n' "$*"; }
pass() { printf '  PASS: %s\n' "$*"; }
fail() { printf '  FAIL: %s\n' "$*"; FAILED=$((FAILED + 1)); }

expect() {
  local want="$1" got="$2" what="$3"
  if [[ "$want" == "$got" ]]; then pass "$what ($got)"; else fail "$what: want $want, got $got"; fi
}

# gh clones with your usual git protocol and adds the parent as "upstream".
gh repo clone "$FORK" "$WORK/repo" -- -q
git -C "$WORK/repo" remote get-url upstream >/dev/null 2>&1 \
  || git -C "$WORK/repo" remote add upstream "$(gh repo view "$UPSTREAM" --json sshUrl --jq .sshUrl)"
git -C "$WORK/repo" fetch -q upstream

# open_pr <fork|upstream> <base> <name> — push a one-commit branch, open a PR, print its number.
open_pr() {
  local where="$1" base="$2" name="$3" branch="${RUN}-${3}" head
  git -C "$WORK/repo" checkout -q -B "$branch" "upstream/${base}"
  echo "${RUN} ${name}" > "$WORK/repo/fork-marker.txt"
  git -C "$WORK/repo" add fork-marker.txt
  git -C "$WORK/repo" commit -q -m "test: ${name}"
  if [[ "$where" == fork ]]; then
    git -C "$WORK/repo" push -q origin "$branch"
    head="${FORK%%/*}:${branch}"
  else
    git -C "$WORK/repo" push -q upstream "$branch"
    head="$branch"
  fi
  gh pr create -R "$UPSTREAM" --base "$base" --head "$head" \
    --title "test: ${name} (${RUN})" --body "Temporary PR for repro/fork-command. Closed automatically." \
    | sed 's|.*/||'
}

head_sha() { gh pr view "$1" -R "$UPSTREAM" --json headRefOid --jq .headRefOid; }

# checks <sha> <name> — "conclusion" per check-run with that name, oldest first.
# filter=all, because the API returns only the newest run per name by default.
checks() {
  gh api "repos/${UPSTREAM}/commits/$1/check-runs?check_name=$(jq -rn --arg n "$2" '$n|@uri')&filter=all&per_page=100" \
    --jq '.check_runs | sort_by(.id) | .[] | (.conclusion // .status)'
}

# wait_checks <sha> <name> <count> — wait until <count> check-runs with that name have completed.
wait_checks() {
  local sha="$1" name="$2" count="$3" deadline=$((SECONDS + TIMEOUT)) done_count
  while (( SECONDS < deadline )); do
    done_count="$(checks "$sha" "$name" | grep -cvE '^(queued|in_progress)$' || true)"
    if (( done_count >= count )); then return 0; fi
    sleep 15
  done
  fail "timed out waiting for ${count} x '${name}' on ${sha:0:7}"
  return 1
}

# ---------------------------------------------------------------------------
log "Setting up ${NO_CONTRACT_BRANCH} at ${NO_CONTRACT_SHA}"
if ! gh api "repos/${UPSTREAM}/branches/${NO_CONTRACT_BRANCH}" >/dev/null 2>&1; then
  git -C "$WORK/repo" push -q upstream "${NO_CONTRACT_SHA}:refs/heads/${NO_CONTRACT_BRANCH}"
  git -C "$WORK/repo" fetch -q upstream
fi

log "Opening pull requests"
PR_A="$(open_pr fork main fork-a)";            OPENED+=("$PR_A")
PR_B="$(open_pr fork main fork-b)";            OPENED+=("$PR_B")
PR_PUSH="$(open_pr fork main fork-push)";      OPENED+=("$PR_PUSH")
PR_SAME="$(open_pr upstream main same-repo)";  OPENED+=("$PR_SAME")
PR_OLD="$(open_pr fork "$NO_CONTRACT_BRANCH" fork-old)"; OPENED+=("$PR_OLD")
echo "  fork A #${PR_A}, fork B #${PR_B}, fork push #${PR_PUSH}, same-repo #${PR_SAME}, old branch #${PR_OLD}"

SHA_A="$(head_sha "$PR_A")"; SHA_B="$(head_sha "$PR_B")"; SHA_PUSH="$(head_sha "$PR_PUSH")"
SHA_SAME="$(head_sha "$PR_SAME")"; SHA_OLD="$(head_sha "$PR_OLD")"

log "Commenting"
# A and B send the same request at the same time: they must not cancel each other.
gh pr comment "$PR_A" -R "$UPSTREAM" --body "/test-e2e fork-smoke" >/dev/null
gh pr comment "$PR_B" -R "$UPSTREAM" --body "/test-e2e fork-smoke" >/dev/null
# The same request twice on one PR: the second must supersede the first.
gh pr comment "$PR_A" -R "$UPSTREAM" --body "/test-e2e fork-repeat --target pro" >/dev/null
sleep 20
gh pr comment "$PR_A" -R "$UPSTREAM" --body "/test-e2e fork-repeat --target pro" >/dev/null
gh pr comment "$PR_PUSH" -R "$UPSTREAM" --body "/test-e2e fork-push --target oss" >/dev/null
gh pr comment "$PR_SAME" -R "$UPSTREAM" --body "/test-e2e same-repo" >/dev/null
gh pr comment "$PR_OLD" -R "$UPSTREAM" --body "/test-e2e fork-old" >/dev/null
# The single-check Platform harness, mirroring loft-enterprise.
gh pr comment "$PR_A" -R "$UPSTREAM" --body "/test-platform-e2e platform-smoke" >/dev/null
gh pr comment "$PR_B" -R "$UPSTREAM" --body "/test-platform-e2e platform-smoke" >/dev/null
gh pr comment "$PR_OLD" -R "$UPSTREAM" --body "/test-platform-e2e platform-old" >/dev/null

log "Pushing to the fork-push PR once its check exists"
deadline=$((SECONDS + TIMEOUT))
until [[ -n "$(checks "$SHA_PUSH" "e2e-oss: fork-push --target oss")" ]] || (( SECONDS >= deadline )); do sleep 10; done
git -C "$WORK/repo" checkout -q "${RUN}-fork-push"
echo "moved" >> "$WORK/repo/fork-marker.txt"
git -C "$WORK/repo" commit -qam "test: move the branch after the command"
git -C "$WORK/repo" push -q origin "${RUN}-fork-push"

log "1. Fork PR, commenter with write access: both trees run the fork commit"
wait_checks "$SHA_A" "e2e-pro: fork-smoke" 1 && expect success "$(checks "$SHA_A" "e2e-pro: fork-smoke")" "fork A pro"
wait_checks "$SHA_A" "e2e-oss: fork-smoke" 1 && expect success "$(checks "$SHA_A" "e2e-oss: fork-smoke")" "fork A oss"

log "2. Two fork PRs, same request: neither cancels the other"
wait_checks "$SHA_B" "e2e-pro: fork-smoke" 1 && expect success "$(checks "$SHA_B" "e2e-pro: fork-smoke")" "fork B pro"
wait_checks "$SHA_B" "e2e-oss: fork-smoke" 1 && expect success "$(checks "$SHA_B" "e2e-oss: fork-smoke")" "fork B oss"

log "3. Same request twice on one PR: the newer run supersedes the older"
if wait_checks "$SHA_A" "e2e-pro: fork-repeat --target pro" 2; then
  # macOS ships bash 3.2, which has no mapfile.
  IFS=$'\n' read -r -d '' -a repeat < <(checks "$SHA_A" "e2e-pro: fork-repeat --target pro") || true
  expect cancelled "${repeat[0]}" "older fork-repeat run"
  expect success "${repeat[1]}" "newer fork-repeat run"
fi

log "4. A push after the command does not change the tested commit"
wait_checks "$SHA_PUSH" "e2e-oss: fork-push --target oss" 1 \
  && expect success "$(checks "$SHA_PUSH" "e2e-oss: fork-push --target oss")" "check on the commented commit"
expect "" "$(checks "$(head_sha "$PR_PUSH")" "e2e-oss: fork-push --target oss")" "no check on the pushed commit"

log "5. Same-repository PR keeps working"
wait_checks "$SHA_SAME" "e2e-pro: same-repo" 1 && expect success "$(checks "$SHA_SAME" "e2e-pro: same-repo")" "same-repo pro"
wait_checks "$SHA_SAME" "e2e-oss: same-repo" 1 && expect success "$(checks "$SHA_SAME" "e2e-oss: same-repo")" "same-repo oss"

log "6. Fork PR into a branch without the contract is refused before dispatch"
wait_checks "$SHA_OLD" "e2e-pro: fork-old" 1 && expect neutral "$(checks "$SHA_OLD" "e2e-pro: fork-old")" "old-branch pro"
wait_checks "$SHA_OLD" "e2e-oss: fork-old" 1 && expect neutral "$(checks "$SHA_OLD" "e2e-oss: fork-old")" "old-branch oss"

log "7. Platform: fork PRs run, and the same request on two PRs does not cancel"
wait_checks "$SHA_A" "e2e-platform: platform-smoke" 1 && expect success "$(checks "$SHA_A" "e2e-platform: platform-smoke")" "platform fork A"
wait_checks "$SHA_B" "e2e-platform: platform-smoke" 1 && expect success "$(checks "$SHA_B" "e2e-platform: platform-smoke")" "platform fork B"

log "8. Platform: fork PR into a branch without the contract is refused"
wait_checks "$SHA_OLD" "e2e-platform: platform-old" 1 && expect neutral "$(checks "$SHA_OLD" "e2e-platform: platform-old")" "platform old branch"

log "9. cache-mode: read blocked every cache save"
expect 0 "$(gh api "repos/${UPSTREAM}/actions/caches?key=fork-cache-probe" --jq .total_count)" "fork-cache-probe caches"

log "Done: ${FAILED} failed"
(( FAILED == 0 ))
