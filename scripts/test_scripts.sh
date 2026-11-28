#!/bin/sh
set -eu

repo_root=$(git rev-parse --show-toplevel)
scripts_dir="$repo_root/scripts"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/clinical-script-tests.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

[ "$#" -gt 0 ] || set -- check_architecture check_comments simulator device prebuilt_deps app_store_connect agent_monitor agent_review_loop

for name in "$@"; do
    src="$scripts_dir/$name.swift"
    test_src="$scripts_dir/test_$name.swift"
    swiftc -parse-as-library -D SCRIPT_TESTS "$src" "$test_src" -o "$tmp_dir/$name-tests"
    if grep -q 'SCRIPT_CLI_BIN' "$test_src"; then
        swiftc "$src" -o "$tmp_dir/$name-cli"
        SCRIPT_CLI_BIN="$tmp_dir/$name-cli" "$tmp_dir/$name-tests" "$repo_root"
    else
        "$tmp_dir/$name-tests" "$repo_root"
    fi
done
