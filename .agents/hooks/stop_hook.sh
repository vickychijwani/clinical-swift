#!/bin/sh
set -eu

if [ "$#" -lt 1 ]; then
    printf '%s\n' 'Usage: stop_hook.sh <codex-hook-script> [args...]' >&2
    exit 2
fi

target_script=$1
shift
input=$(cat)

# Only enforce Stop checks on normal turn completion (NO_TOOL_CALL) or manual runs without a reason.
if printf '%s' "$input" | grep -Eq '"terminationReason"[[:space:]]*:[[:space:]]*"'; then
    if ! printf '%s' "$input" | grep -Eq '"terminationReason"[[:space:]]*:[[:space:]]*"NO_TOOL_CALL"'; then
        printf '%s\n' '{}'
        exit 0
    fi
fi

# Include common Homebrew paths so ripgrep (rg) is found when launched from GUI apps.
for extra_dir in /opt/homebrew/bin /usr/local/bin; do
    if [ -d "$extra_dir" ]; then
        case ":$PATH:" in
            *":$extra_dir:"*) ;;
            *) PATH="$PATH:$extra_dir" ;;
        esac
    fi
done
export PATH

output=$(printf '%s' "$input" | /bin/sh "$target_script" "$@")
printf '%s\n' "$output" | sed 's/"decision"[[:space:]]*:[[:space:]]*"block"/"decision":"continue"/'
