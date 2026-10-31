#!/bin/sh
set -eu

repo_root=$(git rev-parse --show-toplevel)
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
/bin/sh "$repo_root/.codex/hooks/check_swift.sh" --check </dev/null >/dev/null
binary_path=$(git rev-parse --git-path codex-comment-hook/check-comments)
case "$binary_path" in /*) ;; *) binary_path="$repo_root/$binary_path" ;; esac
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/clinical-comment-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
compile_tests() {
    if [ "$(uname -s)" = Darwin ]; then
        xcrun swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" "$@"
    else
        swiftc "$@"
    fi
}
compile_tests -parse-as-library -D COMMENT_HOOK_TESTS \
    "$repo_root/.codex/hooks/check_comments.swift" "$repo_root/.codex/hooks/check_comments_tests.swift" \
    -o "$test_dir/tests"
"$test_dir/tests" "$binary_path"

# Check the first-run path in a separate checkout with no cached executable.
fresh_repo="$test_dir/fresh checkout"
mkdir -p "$fresh_repo/.codex/hooks"
cp "$repo_root/.codex/hooks/check_swift.sh" "$repo_root/.codex/hooks/check_comments.swift" "$fresh_repo/.codex/hooks/"
git -C "$fresh_repo" init -q
if [ "$(uname -s)" = Darwin ]; then
    test_path=/usr/bin:/bin:/usr/sbin:/sbin
else
    test_path=$PATH
fi
first_result=$(cd "$fresh_repo" && PATH="$test_path" /bin/sh .codex/hooks/check_swift.sh --check </dev/null)
test "$first_result" = '{}'
test -x "$fresh_repo/.git/codex-comment-hook/check-comments"
cached_result=$(cd "$fresh_repo" && PATH="$test_path" /bin/sh .codex/hooks/check_swift.sh --check </dev/null)
test "$cached_result" = '{}'
printf '%s\n' 'PASS First-run compilation and cached execution with the platform tool path'
