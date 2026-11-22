---
name: skill-creator-concise
description: Create token-minimal skills. Use when invoked via /skill-creator-concise or asked to author a concise skill.
---

Author a skill at `~/.gemini/config/skills/<name>/SKILL.md` (global) or `.agents/skills/<name>/SKILL.md` (workspace).

- Frontmatter: `name` (kebab-case) and `description` (what + when to trigger).
- Keep the skill super concise, using the minimum tokens necessary — assume execution by a smart model.
- Include only non-obvious steps, constraints, and paths; omit generic advice. Offload bulk to `references/` only if needed.
- Encapsulate and enforce deterministic steps and workflows in tested scripts under `scripts/` rather than prose commands.
- Show the user a draft and target path, and wait for approval before writing files.
