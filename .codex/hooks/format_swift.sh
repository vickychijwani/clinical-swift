#!/bin/sh
set -eu

# Drain hook event input so callers never hit SIGPIPE.
cat >/dev/null

repo_root=$(git rev-parse --show-toplevel)
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

format_swift() {
    if [ "$(uname -s)" = Darwin ]; then
        xargs -0 -r xcrun swift-format format --in-place >&2 || true
    else
        xargs -0 -r swift-format format --in-place >&2 || true
    fi
}

(
    cd "$repo_root"
    if git rev-parse --verify HEAD >/dev/null 2>&1; then
        git diff HEAD --name-only --diff-filter=ACMR -z -- '*.swift' | format_swift
    else
        git diff --name-only --diff-filter=ACMR -z -- '*.swift' | format_swift
    fi
)

printf '%s\n' '{}'
