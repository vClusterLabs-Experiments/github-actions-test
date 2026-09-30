# Fork `/test-e2e` scenarios

Live checks for running `/test-e2e` on pull requests from forks (DEVOPS-1541).
The caller workflows here mirror `vcluster-pro#2478` with stand-in suites:

- Fork commands dispatch the target branch's workflow and check out the PR SHA
  captured when the comment was posted.
- Same-repository commands keep dispatching their own branch.
- Suite runs set `cache-mode: read`, and a probe step tries to save a cache anyway.
- The contract check runs on the workflow that will run, so a branch without
  `.github/e2e-command-contract-v2` is refused before dispatch.

`caller-comment-triggered-check.yaml` and both suite runs pin
`comment-triggered-check` to the `loft-sh/github-actions#276` head. Move them
back to `@comment-triggered-check/v1` once that tag is advanced.

## Run

```bash
repro/fork-command/run.sh
```

Needs `gh` logged in as a user with write access to this repository and a fork
of it (`<you>/github-actions-test`). Override `FORK`, `UPSTREAM`, or `TIMEOUT`
through the environment. The script closes every pull request it opened on exit.
It leaves `release-no-contract` in place for the next run.

## Scenarios

| # | Setup | Expected |
|---|---|---|
| 1 | Fork PR, `/test-e2e fork-smoke` | `e2e-pro` and `e2e-oss` succeed on the fork commit |
| 2 | A second fork PR sends the same request at the same time | Both PRs succeed. Neither run cancels the other |
| 3 | The same request twice on one PR | The older check is `cancelled`, the newer one succeeds |
| 4 | Push to the fork branch after commenting | The check on the commented commit succeeds. The new commit gets none |
| 5 | Same-repository PR | Both trees succeed |
| 6 | Fork PR into `release-no-contract` | Both checks are `neutral` without a dispatch |
| 7 | After the runs | No `fork-cache-probe` cache exists |

A commenter without write access is not scripted, because it needs a second
account. Check it by hand: the command should reply with `insufficient-permission`.
