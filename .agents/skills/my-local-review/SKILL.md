---
name: my-local-review
description: Run a 1-round local review loop with Codex, address comments, and push to main.
---

Run one local review-and-address round with Codex. Do not run a second round.

1. **Run Codex review**: Run `codex exec` on this worktree using the `sol` model and effort from `scripts/agent_review_loop.swift`, `codex-skills-config` (`my-review,my-design-review`), and flags from `.github/workflows/agent-review-loop.yml`, with `sandbox_mode="read-only"` and `-o <file>`.
   - Prompt Codex to review local changes using `my-review` and `my-design-review`, not modify files or use GitHub, and return findings directly.
   - Include settled user decisions from this chat so Codex does not reopen them.
2. **Address findings**: Follow `my-address-review`, skipping its GitHub and PR-branch rules.
3. **Stop on disagreement**: If you disagree with a finding or need a design decision, do not commit or push. Show the finding, your recommendation, and ask the user.
4. **Commit and push**: Otherwise, commit, rebase onto `origin/main` if needed, push to `main`, and summarize Codex's feedback and your changes.
