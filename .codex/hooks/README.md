# Repository hooks

Swift-based hooks cache compiled binaries in the worktree's Git metadata.
`PreToolUse` command guards are text-based checks for accidental direct runs,
not sandboxes.

## Command guards (`PreToolUse`)

- `check_xcodebuild.sh` blocks direct `xcodebuild` commands (`make` still runs
  Xcode internally).
- `check_simctl.sh` blocks direct `xcrun simctl openurl`, `launch`, and `ui`
  commands (`make` still runs `simctl` internally).

```sh
/bin/sh .codex/hooks/check_xcodebuild.sh --test
/bin/sh .codex/hooks/check_simctl.sh --test
```

## UI test wait check (`Stop`)

Requires `rg` on `PATH`. Keep XCTest waits in `clinical-swiftUITests/ElementWaits.swift`
and add a state-first helper there when a new wait is needed. The check is
text-based and also scans comments and strings.

```sh
/bin/sh .codex/hooks/check_ui_waits.sh
/bin/sh .codex/hooks/test_ui_waits.sh
```

## Comment preservation check (`Stop`)

Requires the Xcode toolchain on macOS, or Swift 6.2+ (`swiftc` and
`swift-format`) on `PATH` on Linux. Missing or rewritten Swift comments fail the
hook. Restore or update comments that still apply; for intentional rewrites or
removals, record the reason:

```sh
/bin/sh .codex/hooks/check_swift.sh --review 'Explain each intentional change.'
/bin/sh .codex/hooks/check_swift.sh --check </dev/null
```

Reviews live in the worktree's Git metadata (not source files) and apply only to
that exact Swift snapshot; any later Swift edit requires review again.

```sh
/bin/sh .codex/hooks/test_comments.sh
```
