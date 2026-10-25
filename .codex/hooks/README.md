# Comment preservation check

The repository Stop hook runs Swift formatting, then checks Swift comments. It
uses Git, the system shell, and Swift. On macOS it uses the Xcode Swift
toolchain that this app already requires. On Linux, install Swift 6.2 or later
and put `swiftc` and `swift-format` on `PATH`. On the first run, the hook
compiles its checker into the worktree's Git metadata.

The check compares HEAD with the current working tree, including staged changes,
deleted files, moved code, and new Swift files.

Missing or rewritten comment text makes the Stop hook require another pass. For
each finding, restore or update the comment if it still applies. If the comment
was rewritten or is obsolete, inspect its code and record the reasons:

```sh
/bin/sh .codex/hooks/stop.sh --review 'Explain each intentional change.'
/bin/sh .codex/hooks/stop.sh --check </dev/null
```

The review is stored in the worktree's Git metadata, not in source files. It is
valid only for that exact Swift change set. A later Swift change requires review
again.

Git hashes the source snapshot without writing it to the object database or
applying file filters. This avoids a platform-specific crypto dependency.

Run the checker tests with:

```sh
/bin/sh .codex/hooks/test_comments.sh
```
