#!/bin/bash
set -euo pipefail
[[ "${CI_XCODEBUILD_ACTION:-}" == archive ]] || exit 0
cd "${CI_PRIMARY_REPOSITORY_PATH:?}"
# Xcode Cloud secrets provide only the isolated synthetic-check account.
: "${CLINICAL_BACKUP_CHECK_CREDENTIALS_BASE64:?Set the protected Drive check credential secret before distribution.}"
umask 077
credential_file="$(mktemp "${TMPDIR:-/tmp}/clinical-drive-check.XXXXXX")"
trap 'rm -f "$credential_file"' EXIT
printf '%s' "$CLINICAL_BACKUP_CHECK_CREDENTIALS_BASE64" | base64 --decode > "$credential_file"
unset CLINICAL_BACKUP_CHECK_CREDENTIALS_BASE64
simulator_id="$(xcrun simctl list devices available --json | /bin/sh scripts/select_simulator.sh cloud)"
xcrun simctl boot "$simulator_id" || true
make release-verify CONFIGURATION=Release SIMULATOR_ID="$simulator_id" CLINICAL_BACKUP_CHECK_CREDENTIALS="$credential_file" XCBEAUTIFY=cat
