# Build command guard

The `PreToolUse` hook matches `Bash`, which also covers unified `exec_command`
calls in code mode. It denies direct `xcodebuild` commands before execution and
points the agent to the Makefile targets. Make can still run Xcode internally.
The Swift checker is compiled once and cached in the worktree's Git metadata.

Run its command-matching tests with:

```sh
/bin/sh .codex/hooks/check_xcodebuild.sh --test
```

This is a text guard for accidental direct runs. It covers command paths, common
wrappers, shell chains, and command substitution. It does not inspect arbitrary
scripts or stop deliberate shell obfuscation.

# Simulator command guard

The `PreToolUse` hook runs `check_simctl.sh` for Codex (`Bash`) and Antigravity
(`run_command`, with `--antigravity`). It denies direct `xcrun simctl openurl`,
`xcrun simctl launch`, and `xcrun simctl ui` commands before execution and points
the agent to `make run`, `make build-and-run`, `make appearance`, and
`make screenshot`. Make can still run `simctl` internally. The Swift checker is
compiled once and cached in the worktree's Git metadata.

Run its command-matching and JSON contract tests with:

```sh
/bin/sh .codex/hooks/check_simctl.sh --test
```

This is a text guard for accidental direct runs. It covers command paths, common
wrappers, shell chains, and command substitution. It does not inspect arbitrary
scripts or stop deliberate shell obfuscation.

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

# Swift formatting

The repository Stop hook runs `format_swift.sh` to format changed Swift files
with `swift-format`. On macOS it uses the Xcode toolchain; on Linux it uses
`swift-format` from `PATH`.

Comment preservation checking runs on demand instead of as a Stop hook:

```sh
swift scripts/check_comments.swift
swift scripts/check_comments.swift --base origin/main
```

It compares `HEAD` (or the merge base with `--base <ref>`) against the working
tree, including staged changes, deleted files, moved code, and new Swift files.
Run its tests with `sh scripts/test_scripts.sh check_comments`.
