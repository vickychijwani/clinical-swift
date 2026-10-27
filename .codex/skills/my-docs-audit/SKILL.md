---
name: my-docs-audit
description: Audit and clean up this repo's maintained documentation when asked to reduce duplication, remove implementation detail, or check documentation quality. Use for a documentation audit, not routine documentation updates for a code change.
---

# Documentation audit

Keep useful context easy to find. Retain consequential decisions and constraints
whose reasons are not clear from code or tests. A shorter document is useful only
if it preserves that context; do not set a word-count or deletion target.

## Scope and evidence

- Read `AGENTS.md` and use its documentation map to find the maintained guides.
  Unless the user narrows the scope, audit all maintained guides, including
  persistence, testing, backups, and the patient-data restore procedure.
- Leave plans, specs, and validation reports unchanged. They are historical
  context, not authority for current architecture. Do not copy their completion
  checklists into maintained guides.
- Check claims against the owning code, tests, scripts, and pinned dependencies
  as needed. Read history when the reason for a decision is unclear. Do not invent
  a reason or assume that an old guide describes current behavior.
- Keep edits within maintained docs and targeted fixes to the documentation
  guidance or map in `AGENTS.md`. Flag code problems and unrelated instruction or
  skill problems instead of changing them during the audit.

## Decide what to keep

For each passage, ask what plausible mistake its absence would permit, and why
the code or tests do not provide enough context to prevent that mistake.

- Keep surprising product rules and their reasons. For example, explain why
  overlapping bookings are allowed; omit ordinary labels, colors, sort keys,
  and control behavior that the implementation already makes clear.
- Keep constraints that span modules or processes in guides. Local technical
  traps belong beside their code. Check existing comments before removing a
  guide's only explanation; flag missing local context if code edits are needed.
- Preserve business reasons, even when tests enforce the result. A test can show
  what happens without explaining why the clinic needs that behavior.
- Keep runnable setup, release, and recovery procedures, including necessary
  prerequisites and limits. Remove test inventories, old results, local log
  paths, screenshot lists, and completed-work reports from maintained guides.
- Retain confirmed future product intent when it affects decisions made today.
  Separate that intent from implemented guarantees and speculative library
  restrictions. Use the owning guide for current choices and known trade-offs.

Use the user's established preferences and make the best supported judgment for
borderline cuts. Explain material judgment calls in the result. Do not repeatedly
ask the user to decide routine keep-or-cut questions. If evidence cannot resolve
a consequential conflict, retain the uncertain constraint and report the gap.

## Clean up and verify

- Give each decision one home. Link from other guides instead of repeating it
  under invariants, warnings, regression lists, and edge cases.
- State the rule and its concrete reason in short, direct language. Remove empty
  sections, obsolete claims, implementation inventories, and duplicate text.
  Rewrite the affected passage instead of appending a feature summary.
- Check whether agent instructions or plan templates encouraged the duplication.
  Make only concise documentation-guidance or map fixes in `AGENTS.md`; report
  other causes. A code change alone does not require a documentation update.
- Review the diff for lost reasons, changed policy, and broken procedures. Check
  local links and anchors, referenced paths and commands, and `git diff --check`.
  Run applicable repository checks. Documentation-only edits do not need app tests.
- Report the important cuts, retained context, material judgment calls, and
  validation. If the docs already meet the standard, report that without making
  cosmetic changes just to produce a diff.

## Commit or PR delivery

Commit, push, or open a PR only when the audit request authorizes that delivery.
For documentation-only cleanup commits, include `[skip ci]` in every commit
message. When PR delivery is requested, update an existing open docs-audit PR
when one exists; otherwise open one ready for review. Explain material decisions
in the PR, attach it to the chat, and leave merging to the user. If no changes
are needed, do not create an empty commit or PR.
