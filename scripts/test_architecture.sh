#!/bin/sh
set -eu
repo_root=$(git rev-parse --show-toplevel)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/clinical-architecture-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
swiftc -parse-as-library -D ARCHITECTURE_TESTS \
    "$repo_root/scripts/check_architecture.swift" "$repo_root/scripts/check_architecture_tests.swift" \
    -o "$test_dir/tests"
"$test_dir/tests" "$repo_root"
