---
name: my-comments
description: Use this to add comments in the code describing intent
---

Add comments at key points to explain why the code exists.

- Use short, direct sentences and familiar words.
- Explain the concrete situation or result. Prefer "an appointment may now be in the past" to an explanation of how database observation works.
- Prefer one or two short sentences. Add detail only when a non-obvious constraint needs it.
- Include API details only when they are needed to understand the reason.
- Do not repeat actions that are already clear from the code.

For example:

```swift
// Refresh when the app returns: an appointment may now be in the past.
// Skip this when the app is inactive or patient selection is closed.
```
