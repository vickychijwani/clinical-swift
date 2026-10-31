# UI test wait check

The Stop hook runs `check_ui_waits.sh` as a separate command with a one-second
timeout. It requires ripgrep (`rg`) on `PATH` and does not compile Swift or start
Xcode. It scans all Swift files in `clinical-swiftUITests`, including untracked
and ignored files. Only the root `ElementWaits.swift` file is exempt.

Direct element waits, XCTest waiter references, predicate expectations, and
`wait(for:)` or `fulfillment(of:)` calls must stay in that helper file. Add a
helper that checks the current state first when a new kind of wait is needed.
The check is text-based: it also matches comments and strings, and it does not
resolve Swift aliases or parse source.

Run the check and its regression tests with:

```sh
/bin/sh .codex/hooks/check_ui_waits.sh
/bin/sh .codex/hooks/test_ui_waits.sh
```

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
/bin/sh .codex/hooks/check_swift.sh --review 'Explain each intentional change.'
/bin/sh .codex/hooks/check_swift.sh --check </dev/null
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
