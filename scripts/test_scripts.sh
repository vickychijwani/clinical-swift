#!/bin/sh
set -eu

repo_root=$(git rev-parse --show-toplevel)
scripts_dir="$repo_root/scripts"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/clinical-script-tests.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

[ "$#" -gt 0 ] || set -- check_architecture check_comments simulator app_store_connect agent_monitor agent_review_loop

for name in "$@"; do
    src="$scripts_dir/$name.swift"
    swiftc -parse-as-library -D SCRIPT_TESTS "$src" "$scripts_dir/test_$name.swift" -o "$tmp_dir/$name-tests"
    swiftc "$src" -o "$tmp_dir/$name-cli"
    SCRIPT_CLI_BIN="$tmp_dir/$name-cli" "$tmp_dir/$name-tests" "$repo_root"
done
