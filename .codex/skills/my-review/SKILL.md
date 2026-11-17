---
name: my-review
description: Use this when the user asks to review code changes
---

## What to review

Review changes from ALL of the following perspectives:

- Correctness
- Minimal incidental complexity
  - Perform an adversarial review of the changes from a code complexity perspective. If it seems like a lot of new code for what at first glance feels like a low-to-moderate-complexity feature, figure out what we can do (including, if needed, any refactor of pre-existing code) to dramatically reduce the complexity and size of the code needed to support this feature?
- Clean, well-designed code with no unjustified duplication
  - Use the /my-design-review skill for this
- Idiomatic code + following repo-wide conventions

## Output

- If given a PR, post comments on the PR directly at appropriate places.
- Write in a highly readable, friendly, concise style. Be concrete instead of abstract.
