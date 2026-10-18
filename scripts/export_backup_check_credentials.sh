#!/bin/bash
set -euo pipefail
# Tokens stay in protected files. Never print their contents.
simulator_id="${1:?Pass a simulator ID}"
destination="${CLINICAL_BACKUP_CHECK_CREDENTIALS:-$HOME/.config/clinical-backups/check-credentials.json}"
container="$(xcrun simctl get_app_container "$simulator_id" in.bitehaus.clinical data)"
source_file="$container/Documents/backup-check-credentials.json"
test -f "$source_file" || { echo 'Complete internal Google sign-in first.' >&2; exit 1; }
umask 077
mkdir -p "$(dirname "$destination")"
cp "$source_file" "$destination"
chmod 600 "$destination"
rm "$source_file"
echo 'Test credentials saved outside the repository.'
