#!/bin/sh
set -eu

repo_root=$(git rev-parse --show-toplevel)
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# Use Xcode on macOS and the installed Swift tools elsewhere.
# Compile only when the source or compiler changes.
cache_dir=$(git rev-parse --git-path codex-comment-hook)
case "$cache_dir" in /*) ;; *) cache_dir="$repo_root/$cache_dir" ;; esac
mkdir -p "$cache_dir"
source_path="$repo_root/.codex/hooks/check_comments.swift"
binary_path="$cache_dir/check-comments"
if [ "$(uname -s)" = Darwin ]; then
    compiler_path=$(xcrun --find swiftc)
else
    compiler_path=$(command -v swiftc)
fi
compile_checker() {
    if [ "$(uname -s)" = Darwin ]; then
        "$compiler_path" -sdk "$(xcrun --sdk macosx --show-sdk-path)" "$@"
    else
        "$compiler_path" "$@"
    fi
}
if [ ! -x "$binary_path" ] || [ "$source_path" -nt "$binary_path" ] || [ "$compiler_path" -nt "$binary_path" ]; then
    temporary_binary="$binary_path.$$"
    trap 'rm -f "$temporary_binary"' EXIT HUP INT TERM
    if ! compile_checker -parse-as-library "$source_path" -o "$temporary_binary" >&2; then
        printf '%s\n' '{"decision":"block","reason":"The comment checker could not compile. Check the Swift compiler diagnostics and rerun the hook before finishing."}'
        exit 0
    fi
    mv "$temporary_binary" "$binary_path"
fi

if [ "$#" -eq 0 ]; then
    # Keep formatting and the check in sequence so they inspect the same final source.
    if [ "$(uname -s)" = Darwin ]; then
        git diff --name-only -- '*.swift' | xargs -r xcrun swift-format format --in-place >&2 || true
    else
        git diff --name-only -- '*.swift' | xargs -r swift-format format --in-place >&2 || true
    fi
fi
exec "$binary_path" "$@"
