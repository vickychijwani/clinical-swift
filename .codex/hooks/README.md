# Comment preservation check

The repository Stop hook runs Swift formatting, then checks Swift comments. It
uses Git, the system shell, and the Xcode Swift toolchain that this app already
requires. It does not need Python or a package installation. On the first run,
the hook compiles its checker into the worktree's Git metadata. Later runs reuse
that executable until the checker source or compiler changes. The macOS SDK is
selected through Xcode, without a fixed SDK version.

The check compares HEAD with the current working tree, including staged changes,
deleted files, moved code, and new Swift files. Unchanged comment text can move
between changed files without a finding. Whitespace changes are ignored. Inline
comments, documentation comments, and nested block comments are included. Comment
markers inside normal, raw, and multiline string literals are ignored.

Missing or rewritten comment text makes the Stop hook require another pass. For
each finding, restore or update the comment if it still applies. If the comment
was rewritten or is obsolete, inspect its code and record the reasons:

```sh
/bin/sh .codex/hooks/stop.sh --review 'Explain each intentional change.'
/bin/sh .codex/hooks/stop.sh --check </dev/null
```

The review is stored in the worktree's Git metadata, not in source files. It is
valid only for that exact Swift change set. A later Swift change requires review
again. The hook does not skip the check on a Stop continuation. Formatting and
checking run in sequence, so the check sees the final formatted source.

This is a text check, not a Swift parser or a review of meaning. It cannot prove
that a comment still describes its code. Comments inside string interpolation
expressions are not checked. Regex literals can require an explicit review.
Comments added and removed before they reach HEAD are outside this baseline.
The AGENTS.md rule still requires review of the code and its comments.

Use `/hooks` in Codex CLI to review and trust the changed Stop hook definition.
Codex skips new or changed hooks until they are trusted. The project must also
be trusted. See [OpenAI hook documentation](https://learn.chatgpt.com/docs/hooks).

Run the checker tests with:

```sh
/bin/sh .codex/hooks/test_comments.sh
```
