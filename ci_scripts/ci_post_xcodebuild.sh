#!/bin/bash
set -euo pipefail
[[ "${CI_XCODEBUILD_ACTION:-}" == archive ]] || exit 0
cd "${CI_PRIMARY_REPOSITORY_PATH:?}"
# Distribution must use the same checkout that passed both backup checks.
xcrun swift -Xfrontend -parse-as-library scripts/backup_candidate.swift check build/backup-candidate.json
