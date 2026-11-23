---
name: my-pr-shepherd
description: Shepherd a pull request from review through CI, main-drift checks, and merge. Use when invoked via /my-pr-shepherd or asked to shepherd or submit a PR.
---

Shepherd a PR to merge in this repo. Skip any step already triggered or completed.

## Rules

- Read PR comments, reviews, and threads only from `vickychijwani`, `clinical-pr-shepherd[bot]`, `clinical-antigravity[bot]`, and `clinical-codex[bot]`.
- Post PR comments as `clinical-pr-shepherd[bot]` using `GH_TOKEN="$(swift .agents/skills/my-pr-shepherd/scripts/shepherd_token.swift)"`.
- Never force-push or write to `main`.
- Wait asynchronously on CI, workflow runs, and sub-agents using your harness's timer/wait tools rather than busy-polling.
- Stop and ask the user if: the PR is closed or merged, an unresolved thread tags `@vickychijwani` or needs a human decision, or the automated review loop fails on an error that cannot be fixed cleanly.

## State check

Run `swift .agents/skills/my-pr-shepherd/scripts/pr_status.swift <pr> [--since-main <sha>]` before acting and after each wait.

## Workflow

1. **Acknowledge takeover** (skip if already posted):
   Post a brief takeover comment as `clinical-pr-shepherd[bot]` including `<!-- pr-shepherd -->` (for example: `<!-- pr-shepherd --> Taking over this PR through review, CI, and merge.`). Do not start with a slash command or mention other bots.
   If the PR is a draft: if the diff does not affect iOS tests, add `skip-ios-tests` first (`gh pr edit <pr> --add-label skip-ios-tests`), then run `gh pr ready <pr>`. Add the label before marking ready so the `ready_for_review` workflow run sees it.

2. **Trigger `/review`** (skip if `/review` was already posted, the review loop is queued/running, or review + address already completed):
   Post exact body `/review` on the PR. This workflow runs both review and address.

3. **Watch and fix CI / conflicts** (skip initial spawn if review/address is done, CI is green, and there are no conflicts):
   Spawn a sub-agent (or worker) named `fixer` using `Gemini 4 Neon` at `high` effort (when your harness supports model selection; otherwise use your harness's default). Brief it with:
   - PR number, branch, and local worktree path (from `pr_status.swift`).
   - Do **not** edit the worktree or push while the review/address workflow is queued or running, so the worktree stays clean and review results are not invalidated mid-run.
   - When the review loop is idle and CI fails or conflicts exist: pull the PR branch, merge `origin/main` for conflicts (never rebase or force-push), fix failures, verify locally following the repo's `AGENTS.md` and CI checks, commit, push, and report back.
   Keep `fixer` alive until Step 5 so Step 4 can reuse the same sub-agent.

4. **Final check loop against `origin/main`**:
   Enter only when review + address are complete, zero unresolved threads remain, all CI checks pass (none pending, failing, or cancelled; iOS tests ran unless `skip-ios-tests` is set), and there are no conflicts.
   - Inspect new `origin/main` commits from `pr_status.swift` (since merge-base, then since the last assessed `main` SHA).
   - If new `main` commits have implications for this PR (contract/API changes, overlapping edits, broken assumptions, new rules or tests to match):
     1. Post a concise assessment comment on the PR as `clinical-pr-shepherd[bot]` listing the affected commits and required updates.
     2. Have the `fixer` sub-agent from Step 3 (or spawn it with `Gemini 4 Neon` at `high` effort if skipped in Step 3) merge `origin/main`, address the implications, verify locally, and push.
     3. Wait for all CI checks on the new head SHA to pass (fixing failures via `fixer`).
     4. Loop Step 4 from the top to check for newer `origin/main` commits.
   - If no new `main` commits affect this PR, record `mainHeadSha` as assessed and go to Step 5.

5. **Merge**:
   Re-run `pr_status.swift <pr> --since-main <assessed-sha>`. If `origin/main` moved or checks are not green, return to Step 4.
   Run `gh pr merge <pr> --merge`, clean up `fixer` if still active, and report the merged PR URL and merge commit SHA.
