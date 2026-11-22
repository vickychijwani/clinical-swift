---
name: skill-creator-concise
description: Create token-minimal skills. Use when invoked via /skill-creator-concise or asked to author a concise skill.
---

Write a skill at `~/.gemini/config/skills/<name>/SKILL.md` (global) or `.agents/skills/<name>/SKILL.md` (workspace).

- Frontmatter: `name` (kebab-case) and `description` (what the skill does and when to use it).
- Express the user's intent and hard constraints. Do not overfit to one case or invent rigid rules the user did not ask for.
- Use the minimum tokens needed for a capable model. Include only non-obvious steps, rules, and paths; move large reference material to `references/` only when needed.
- Put repeatable mechanical work and hard rules in small, tested scripts under `scripts/` when code is more reliable than prose commands. Leave judgment calls to the model unless the user wants a fixed rule.
- Show the draft and target path, and wait for user approval before writing files.
