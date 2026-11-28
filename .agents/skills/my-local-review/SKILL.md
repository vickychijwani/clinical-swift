---
name: my-local-review
description: Run a 1-round local review loop with Codex, address comments, and land or keep changes as chosen.
---

Run one local review-and-address round with Codex. Do not run a second round.

1. **Ask how to finish**: Before starting, ask the user whether to push to `main`, open a PR, or keep changes locally after the review.
2. **Run Codex review**: Run `codex exec` on this worktree using the `sol` model and effort from `scripts/agent_review_loop.swift`, `codex-skills-config` (`my-review,my-design-review`), and flags from `.github/workflows/agent-review-loop.yml` — except omit `--dangerously-bypass-hook-trust`, add `--disable hooks`, and set `sandbox_mode="read-only"` with `-o <file>` (so repo Stop hooks neither format files nor block a read-only reviewer).
   - Prompt Codex to review local changes using `my-review` and `my-design-review`, not modify files or use GitHub, and return findings directly.
   - Include settled user decisions from this chat so Codex does not reopen them.
3. **Address findings**: Follow `my-address-review`, skipping its GitHub and PR-branch rules.
4. **Check Swift comments**: Run `swift scripts/check_comments.swift` (or `--base origin/main` if changes are already committed) once before finishing. Restore any dropped comment that still applies, update stale ones, and ignore intentional rewrites or obsolete comments.
5. **Stop on disagreement**: If you disagree with a finding or need a design decision, do not commit, push, or open a PR. Frame the real-world user scenario first in plain language without jargon, list each option with its concrete upside and downside (using real numbers or user-visible impact where available), state your recommendation, and ask the user.
6. **Finish as chosen**: Otherwise, summarize Codex's feedback and your changes, and apply the choice from step 1:
   - **Push to `main`**: Commit, rebase onto `origin/main` if needed, and push to `main`.
   - **Open a PR**: Commit, push the branch, and open a PR using `my-open-pr`.
   - **Keep locally**: Leave changes uncommitted in the worktree.
