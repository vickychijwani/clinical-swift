#!/bin/sh
set -eu
repo_root=$(git rev-parse --show-toplevel)
cache_dir=$(git rev-parse --git-path clinical-simulator)
case "$cache_dir" in /*) ;; *) cache_dir="$repo_root/$cache_dir" ;; esac
mkdir -p "$cache_dir"
compiler=$(xcrun --find swiftc)
sdk=$(xcrun --sdk macosx --show-sdk-path)
source_path="$repo_root/scripts/select_simulator.swift"
fingerprint=$({ cat "$source_path"; "$compiler" --version 2>&1; printf '%s\n' "$compiler" "$sdk"; } | cksum)
binary="$cache_dir/select-simulator"
if [ ! -x "$binary" ] || [ "$(cat "$cache_dir/fingerprint" 2>/dev/null || true)" != "$fingerprint" ]; then
    temporary_binary="$binary.$$"
    trap 'rm -f "$temporary_binary"' EXIT HUP INT TERM
    "$compiler" -sdk "$sdk" -parse-as-library "$source_path" -o "$temporary_binary"
    mv "$temporary_binary" "$binary"
    printf '%s\n' "$fingerprint" > "$cache_dir/fingerprint"
fi
exec "$binary" "$@"
