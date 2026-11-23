#!/bin/sh
set -eu

repo_root=$(git rev-parse --show-toplevel)
agents_dir="$repo_root/.agents"
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/clinical-agy-hooks.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM

# Validate hooks.json is valid JSON.
/usr/bin/python3 -m json.tool "$agents_dir/hooks.json" >/dev/null

# Verify clean pass on NO_TOOL_CALL from .agents/ (Antigravity's hook working directory).
ui_pass=$(cd "$agents_dir" && printf '%s' '{"terminationReason":"NO_TOOL_CALL","cwd":"'"$repo_root"'"}' \
    | /bin/sh ./hooks/stop_hook.sh ../.codex/hooks/check_ui_waits.sh)
test "$ui_pass" = '{}'

swift_pass=$(cd "$agents_dir" && printf '%s' '{"terminationReason":"NO_TOOL_CALL","cwd":"'"$repo_root"'"}' \
    | /bin/sh ./hooks/stop_hook.sh ../.codex/hooks/check_swift.sh --check)
test "$swift_pass" = '{}'

# Verify non-NO_TOOL_CALL termination reasons allow stopping immediately.
for reason in USER_CANCELED ERROR MAX_INVOCATIONS MAX_FORCED_INVOCATIONS; do
    res=$(cd "$agents_dir" && printf '%s' '{"terminationReason":"'"$reason"'","cwd":"'"$repo_root"'"}' \
        | /bin/sh ./hooks/stop_hook.sh ../.codex/hooks/check_ui_waits.sh)
    test "$res" = '{}'
done

# Verify Codex "decision":"block" is translated to Antigravity "decision":"continue".
cat > "$test_dir/mock_block.sh" <<'EOF'
#!/bin/sh
cat >/dev/null
printf '%s\n' '{"decision":"block","reason":"Mock failure"}'
EOF

block_result=$(cd "$agents_dir" && printf '%s' '{"terminationReason":"NO_TOOL_CALL"}' \
    | /bin/sh ./hooks/stop_hook.sh "$test_dir/mock_block.sh")
case "$block_result" in
    *'"decision":"continue"'*'"reason":"Mock failure"'*) ;;
    *) printf 'FAIL expected continue decision, got: %s\n' "$block_result"; exit 1 ;;
esac

# Verify USER_CANCELED skips even a blocking hook.
cancel_result=$(cd "$agents_dir" && printf '%s' '{"terminationReason":"USER_CANCELED"}' \
    | /bin/sh ./hooks/stop_hook.sh "$test_dir/mock_block.sh")
test "$cancel_result" = '{}'

# Verify Stop hook formats changed Swift files from repo root even when invoked from .agents/.
format_repo="$test_dir/format repo"
mkdir -p "$format_repo/.agents/hooks" "$format_repo/.codex/hooks" "$format_repo/Sources"
cp "$agents_dir/hooks/stop_hook.sh" "$format_repo/.agents/hooks/"
cp "$repo_root/.codex/hooks/check_swift.sh" "$repo_root/.codex/hooks/check_comments.swift" "$format_repo/.codex/hooks/"
git -C "$format_repo" init -q
git -C "$format_repo" config user.email "test@example.com"
git -C "$format_repo" config user.name "Test"
printf 'let x = 1\n' > "$format_repo/Sources/Example.swift"
git -C "$format_repo" add Sources/Example.swift
git -C "$format_repo" commit -q -m "Initial"
printf 'let   x=2\n' > "$format_repo/Sources/Example.swift"
format_result=$(cd "$format_repo/.agents" && printf '%s' '{"terminationReason":"NO_TOOL_CALL","cwd":"'"$format_repo"'"}' \
    | /bin/sh ./hooks/stop_hook.sh ../.codex/hooks/check_swift.sh)
test "$format_result" = '{}'
test "$(cat "$format_repo/Sources/Example.swift")" = "let x = 2"

printf '%s\n' 'PASS Antigravity Stop hook adapter tests'
