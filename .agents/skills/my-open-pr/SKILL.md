---
name: my-open-pr
description: Open a pull request in this repo with net-new code breakdowns and the skip-ios-tests label when applicable. Use whenever opening a PR.
---

## Swift comment check

Before opening the PR, run `swift scripts/check_comments.swift --base origin/main` once. Restore any dropped comment that still applies, update stale ones, and ignore intentional rewrites or obsolete comments.

## Net-new code breakdown (200+ lines)

Count net new production code lines against the base branch (exclude tests, docs, configs, deletions, and moved code).

If 200+ lines, add a concise breakdown at the end of the PR description so a reviewer can judge whether the code pulls its weight:

- Group where the new lines come from and what each part does.
- For any part that looks larger than expected, briefly explain why it exists and whether a requirements change could drop major parts (for example, unneeded backwards compatibility or rare edge cases).

## Skip iOS tests label

Check `.github/workflows/ios-tests.yml` (App unit tests, Local backup tests, UI tests). If the PR does not affect any test it runs, add the `skip-ios-tests` label in the initial PR creation call (for example, `gh pr create --label skip-ios-tests`) so the workflow does not trigger on open.
