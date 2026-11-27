# Repository hooks

Swift-based hooks compile once and cache their binary in the worktree's Git
metadata. `PreToolUse` command guards are text-based checks for accidental direct
runs (covering command paths, common wrappers, shell chains, and command
substitution); they do not inspect arbitrary scripts or stop deliberate shell
obfuscation.

## Build command guard (`PreToolUse`)

Matches `Bash` (including unified `exec_command` calls in code mode). Denies
direct `xcodebuild` commands and points to `Makefile` targets (`make` still runs
Xcode internally).

```sh
/bin/sh .codex/hooks/check_xcodebuild.sh --test
```

## Simulator command guard (`PreToolUse`)

Runs `check_simctl.sh` for Codex (`Bash`) and Antigravity (`run_command`, with
`--antigravity`). Denies direct `xcrun simctl openurl`, `xcrun simctl launch`,
and `xcrun simctl ui` commands and points to `make run`, `make build-and-run`,
`make appearance`, and `make screenshot` (`make` still runs `simctl` internally).

```sh
/bin/sh .codex/hooks/check_simctl.sh --test
```

## UI test wait check (`Stop`)

Runs `check_ui_waits.sh` with a one-second timeout. Requires `rg` on `PATH` and
does not compile Swift or start Xcode. Scans all Swift files in
`clinical-swiftUITests` (including untracked and ignored files); only the root
`ElementWaits.swift` is exempt.

Keep direct element waits, XCTest waiter references, predicate expectations, and
`wait(for:)` or `fulfillment(of:)` calls in `ElementWaits.swift`. Add a helper
that checks current state first when a new wait is needed. The check is
text-based: it matches comments and strings and does not parse Swift.

```sh
/bin/sh .codex/hooks/check_ui_waits.sh
/bin/sh .codex/hooks/test_ui_waits.sh
```

## Comment preservation check (`Stop`)

Runs Swift formatting, then compares Swift comments between `HEAD` and the
working tree (including staged, deleted, moved, and new files). Uses Git, `/bin/sh`,
and Swift (Xcode toolchain on macOS; Swift 6.2+ with `swiftc` and `swift-format`
on `PATH` on Linux).

Missing or rewritten comments fail the check. Restore or update each comment if
it still applies. If a rewrite or removal is intentional, inspect the code and
record the reason:

```sh
/bin/sh .codex/hooks/check_swift.sh --review 'Explain each intentional change.'
/bin/sh .codex/hooks/check_swift.sh --check </dev/null
```

The review is stored in the worktree's Git metadata (not in source files) and
applies only to that exact Swift snapshot (hashed by Git without writing to the
object database or applying filters). Any later Swift edit requires review again.

```sh
/bin/sh .codex/hooks/test_comments.sh
```
