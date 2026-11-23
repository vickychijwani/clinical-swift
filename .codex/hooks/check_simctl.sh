#!/bin/sh
set -eu

antigravity=0
for arg in "$@"; do
    if [ "$arg" = --antigravity ]; then
        antigravity=1
    fi
done

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
repo_root=$(git rev-parse --show-toplevel)
cache_dir=$(git rev-parse --git-path codex-command-hook)
case "$cache_dir" in /*) ;; *) cache_dir="$repo_root/$cache_dir" ;; esac
source_path="$repo_root/.codex/hooks/check_simctl.swift"
binary_path="$cache_dir/check-simctl"

# A hook error can allow execution. Return an explicit denial if setup fails.
deny_setup() {
    decision="block"
    if [ "$antigravity" -eq 1 ]; then
        decision="deny"
    fi
    printf '{"decision":"%s","reason":"The simulator command guard could not start. Repair .codex/hooks/check_simctl.sh before running shell commands."}\n' "$decision"
}
if ! mkdir -p "$cache_dir"; then deny_setup; exit 0; fi
if ! compiler_path=$(xcrun --find swiftc); then deny_setup; exit 0; fi
if [ ! -x "$binary_path" ] || [ "$source_path" -nt "$binary_path" ] || [ "$compiler_path" -nt "$binary_path" ]; then
    temporary_binary="$binary_path.$$"
    trap 'rm -f "$temporary_binary"' EXIT HUP INT TERM
    if ! "$compiler_path" -sdk "$(xcrun --sdk macosx --show-sdk-path)" "$source_path" -o "$temporary_binary"; then deny_setup; exit 0; fi
    if ! mv "$temporary_binary" "$binary_path"; then deny_setup; exit 0; fi
fi
if [ "${1:-}" = --test ]; then exec "$binary_path" "$@"; fi
if ! "$binary_path" "$@"; then deny_setup; fi
