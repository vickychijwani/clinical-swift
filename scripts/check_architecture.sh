#!/bin/sh
set -eu
repo_root=$(git rev-parse --show-toplevel)
cache_dir=$(git rev-parse --git-path clinical-architecture)
case "$cache_dir" in /*) ;; *) cache_dir="$repo_root/$cache_dir" ;; esac
mkdir -p "$cache_dir"
compiler=$(command -v swiftc)
source_path="$repo_root/scripts/check_architecture.swift"
# The compiler version also changes when an Xcode toolchain is replaced in place.
fingerprint=$({ cat "$source_path"; "$compiler" --version 2>&1; printf '%s\n' "$compiler"; } | cksum)
binary="$cache_dir/check-architecture"
if [ ! -x "$binary" ] || [ "$(cat "$cache_dir/fingerprint" 2>/dev/null || true)" != "$fingerprint" ]; then
    temporary_binary="$binary.$$"
    trap 'rm -f "$temporary_binary"' EXIT HUP INT TERM
    "$compiler" -parse-as-library "$source_path" -o "$temporary_binary"
    mv "$temporary_binary" "$binary"
    printf '%s\n' "$fingerprint" > "$cache_dir/fingerprint"
fi
exec "$binary" "$@"
