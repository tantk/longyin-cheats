---
name: pr-contributor
description: Submit pull requests to open source repos with proper CI verification. Use when the user says "create PR", "submit PR", "open pull request", "contribute to repo", or when code changes need to be submitted upstream. Ensures local CI passes, logs are saved, and PR is properly documented before submission.
---

# PR Contributor — Submit PRs with CI Verification

Submit pull requests to open source repos with full local CI verification before asking maintainers to review.

## Before Starting

Read the target repo's contributing guidelines:
- `CONTRIBUTING.md`
- `AGENTS.md` / `AGENTS.md` (if they exist)
- `.github/workflows/` — understand the exact CI pipeline

## Workflow

### Step 1: Fork and Branch

```bash
gh repo fork <owner>/<repo> --clone=false
git clone https://github.com/<your-user>/<repo>.git /tmp/<repo>-pr
cd /tmp/<repo>-pr
git checkout -b <fix-or-feat-branch>
```

### Step 2: Make Changes

- Follow the repo's commit conventions (check recent merged PRs for style)
- Keep diffs minimal and focused
- No drive-by refactors

### Step 3: Run Full Local CI

**Before pushing anything**, replicate the entire CI pipeline locally.

1. Read `.github/workflows/` to identify ALL CI steps
2. Run each step in order, capturing full output
3. Save logs to `C:/dev/longyin-cheats/docs/ci-logs/<repo>/<branch>/`

```
ci-logs/<repo>/<branch>/
├── 01-format.log
├── 02-lint.log
├── 03-typecheck.log
├── 04-tests.log
├── 05-tests-web.log (if applicable)
├── coverage-summary.json (if applicable)
├── test-results.json (if applicable)
└── ci-summary.md
```

Each `.log` file must contain the **full command output**, not just exit codes. The `ci-summary.md` links to each log and shows pass/fail.

**If the CI uses a specific Node/Python/etc version**, match it exactly. Use Docker or nvm if needed.

**If any step fails**, fix it before proceeding. Do not push broken code.

### Step 4: Run CI on Ubuntu Docker (REQUIRED)

Local Windows/Mac testing is not sufficient. Replicate the actual CI environment:

1. Use the Ubuntu server at `Z:/project/` with Docker matching the CI's Node version
2. Read `.github/workflows/` to identify the exact Node version (usually in `actions/setup-node`)
3. Run ALL CI steps — not just the ones you think are relevant
4. Save the full report AND per-step logs

```
Z:/project/<repo>_ci/reports/<branch>-<timestamp>/
├── report.md        # Summary with pipeline status table
└── logs/
    ├── quality_format.log
    ├── quality_lint.log
    ├── quality_typecheck.log
    ├── quality_typecheck-web.log
    ├── tests_ubuntu+coverage.log
    ├── tests_gitnexus-web.log
    └── build-gitnexus.log
```

Each `.log` file must contain the **full command output** — not summaries, not exit codes. A reviewer must be able to read the log and see every test that ran.

**Reliability note:** Local CI replication is ~90% match to GitHub Actions. The gap comes from the `setup-*` composite actions, cross-platform matrix (macOS), and environment variables. Always state in the PR comment that this is a local reproduction and maintainer CI is authoritative.

**If any step fails**, fix it and re-run ALL steps. Do not re-run only the failing step.

### Step 5: Push Logs to Fork (REQUIRED before PR comment)

Logs must be publicly accessible so the maintainer can verify. Commit them to a `ci-logs/` branch on your fork — NOT to the PR branch, NOT to main.

```bash
cd /tmp/<repo>-pr
git checkout main
git checkout -b ci-logs/<branch>
mkdir -p ci-logs/logs
cp Z:/project/<repo>_ci/reports/<branch>-<timestamp>/report.md ci-logs/
cp Z:/project/<repo>_ci/reports/<branch>-<timestamp>/logs/*.log ci-logs/logs/
git add -f ci-logs/
git commit -m "ci: local CI logs for <branch>"
git push origin ci-logs/<branch>
```

This creates a URL like:
`https://github.com/<your-user>/<repo>/tree/ci-logs/<branch>/ci-logs`

The maintainer can click into `ci-logs/logs/` and read every individual step's output.

### Step 6: Push Code and Create PR

Only after ALL CI steps pass and logs are pushed:

```bash
git checkout <fix-branch>
git push origin <fix-branch>
gh pr create --repo <owner>/<repo> --head <your-user>:<branch> \
  --title "<conventional-commit-style title>" \
  --body "<PR body with summary + test plan>"
```

### Step 7: Post CI Comment on PR

Post ONE clean comment with the summary table and link to logs. Do not spam multiple comments.

```markdown
## Local CI Verification (Ubuntu Docker, Node <version>)

Replicated CI pipeline locally. All steps pass.
**Note:** This is a local reproduction — maintainer CI approval needed for authoritative results.

| Step | Exit Code | Duration | Status |
|------|-----------|----------|--------|
| quality/format | 0 | Xs | PASS |
| quality/lint | 0 | Xs | PASS |
| quality/typecheck | 0 | Xs | PASS |
| tests (coverage) | 0 | Xs | PASS |

**Tests:** X passed / 0 failed
**Coverage:** XX.XX% stmts, XX.XX% branches, XX.XX% functions, XX.XX% lines

Full report + logs: https://github.com/<your-user>/<repo>/tree/ci-logs/<branch>/ci-logs
```

### Step 8: Respond to Review

- If CI needs rerun: fix the issue first, re-run full local CI, push logs, then ask for rerun
- If reviewer requests changes: make them, re-run full CI, push updated logs to the same ci-logs branch, post updated comment
- Never push without local CI verification
- Delete outdated comments — keep only the latest CI report

## Anti-Patterns

- Pushing code and hoping CI passes — **always verify locally first**
- Posting summary tables without logs — **show the actual output**
- Running only the failing step after a fix — **run ALL steps again**
- Using a different Node/runtime version than CI — **match exactly**
- Spamming PR comments — **one clean report per push, delete outdated ones**
- Mixing unrelated changes — **one PR per concern**

## PR Description Template

```markdown
## Summary
- Bullet points of what changed and why

## Test plan
- [x] Local CI: format, lint, typecheck, tests (link to logs)
- [x] Coverage: XX.XX% statements (delta from main)
- [ ] Maintainer CI approval needed (first-time contributor)
```
