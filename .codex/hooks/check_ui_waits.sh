#!/bin/sh
set -eu

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root/clinical-swiftUITests"

# Scan all UI test source, including untracked files. Only the shared helper can use XCTest waits.
pattern='\b(waitForExistence|waitForNonExistence|waitForExpectations|XCTWaiter|XCTNSPredicateExpectation)\b|\b(wait\s*\(\s*for|fulfillment\s*\(\s*of)\s*:'
if rg --no-config --hidden --no-ignore --multiline --line-number --with-filename \
    --glob '*.swift' --glob '!/ElementWaits.swift' "$pattern" . >&2; then
    printf '%s\n' '{"decision":"block","reason":"UI tests must use the ElementWaits helpers. Replace the direct XCTest waits listed above. If a new wait is needed, add a helper in clinical-swiftUITests/ElementWaits.swift that checks the current state before waiting."}'
else
    status=$?
    if [ "$status" -eq 1 ]; then
        printf '%s\n' '{}'
    else
        printf '%s\n' '{"decision":"block","reason":"The UI wait check could not run. Check the diagnostics and make sure ripgrep (rg) is on PATH, then rerun .codex/hooks/check_ui_waits.sh."}'
    fi
fi
