#!/bin/sh
set -eu

repo_root=$(git rev-parse --show-toplevel)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/clinical-ui-waits.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
git -C "$test_dir" init -q
mkdir -p "$test_dir/clinical-swiftUITests/Nested" "$test_dir/UnitTests"
checker="$repo_root/.codex/hooks/check_ui_waits.sh"
cd "$test_dir"

check_result() {
    result=$(/bin/sh "$checker" 2>"$test_dir/diagnostics")
    case "$1:$result" in
        'pass:{}'|block:*'"decision":"block"'*) ;;
        *) printf 'FAIL %s: %s\n' "$1" "$result"; exit 1 ;;
    esac
}

# The helper and files outside the UI test folder can use XCTest waits.
printf '%s\n' 'element.waitForExistence(timeout: 2)' > clinical-swiftUITests/ElementWaits.swift
printf '%s\n' 'XCTWaiter.wait(for: [], timeout: 2)' > UnitTests/Tests.swift
printf '%s\n' 'element.existsOrWait(timeout: 2)' 'element.hittableOrWait(timeout: 2)' \
    'element.valueContainsOrWait("Monday", timeout: 2)' > clinical-swiftUITests/Tests.swift
check_result pass

# All fixture files are untracked. Ignore rules must not hide a new test.
printf '%s\n' 'clinical-swiftUITests/Nested/' > .gitignore
for source in \
    'element.waitForExistence(timeout: 2)' \
    'element.waitForNonExistence(timeout: 2)' \
    'element.wait(for: \.isHittable, toEqual: true, timeout: 2)' \
    'XCTWaiter.wait(for: [], timeout: 2)' \
    'let waiter = XCTWaiter()' \
    'XCTNSPredicateExpectation(predicate: predicate, object: element)' \
    'waitForExpectations(timeout: 2)' \
    'wait(for: [], timeout: 2)' \
    'await fulfillment(of: [], timeout: 2)'; do
    printf '%s\n' "$source" > clinical-swiftUITests/Nested/Tests.swift
    check_result block
    test -s "$test_dir/diagnostics"
done

printf 'element.wait(\n for\n : \\.isHittable, toEqual: true, timeout: 2)\n' \
    > clinical-swiftUITests/Nested/Tests.swift
check_result block
rm clinical-swiftUITests/Nested/Tests.swift

# A second file with the helper name must not gain an exemption.
printf '%s\n' 'element.waitForExistence(timeout: 2)' > clinical-swiftUITests/Nested/ElementWaits.swift
check_result block
rm clinical-swiftUITests/Nested/ElementWaits.swift
check_result pass
printf '%s\n' 'PASS UI wait checks: helpers, direct waits, multiline calls, nested files, and ignored files'
