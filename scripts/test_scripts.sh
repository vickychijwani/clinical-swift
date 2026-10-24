#!/bin/sh
set -eu
repo_root=$(git rev-parse --show-toplevel)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/clinical-script-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
xcrun swiftc -O -swift-version 6 -sdk "$(xcrun --sdk macosx --show-sdk-path)" -parse-as-library -D SCRIPT_TESTS \
    "$repo_root/scripts/backup_candidate.swift" \
    "$repo_root/scripts/check_backup_device.swift" \
    "$repo_root/scripts/select_simulator.swift" \
    "$repo_root/.codex/skills/my-screenshots/scripts/check_images.swift" \
    "$repo_root/scripts/script_tests.swift" -o "$test_dir/tests"
"$test_dir/tests"

# Exercise real command entry points in a separate checkout without Python on PATH.
fixture="$test_dir/fresh checkout"
mkdir -p "$fixture/scripts" "$fixture/clinical-swift" "$fixture/build/archive" "$test_dir/bin"
cp "$repo_root/Makefile" "$fixture/"
cp "$repo_root/scripts/backup_candidate.swift" "$repo_root/scripts/check_backup_device.swift" \
    "$repo_root/scripts/select_simulator.swift" "$repo_root/scripts/select_simulator.sh" "$fixture/scripts/"
git -C "$fixture" init -q
printf '%s\n' 'build/' > "$fixture/.gitignore"
printf '%s\n' 'archive fixture' > "$fixture/build/archive/App"
cat > "$fixture/clinical-swift/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>GoogleBackupClientID</key><string>synthetic-client</string><key>GoogleBackupCallbackScheme</key><string>synthetic-callback</string></dict></plist>
PLIST
printf '%s\n' '{"clientID":"synthetic-client","deviceCheck":{"releaseOnDevice":true,"clientID":"synthetic-client","callbackScheme":"synthetic-callback"}}' > "$fixture/build/credentials.json"
for tool in git xcrun mkdir cat cksum mv rm make; do
    tool_path="/usr/bin/$tool"
    [ -x "$tool_path" ] || tool_path="/bin/$tool"
    ln -s "$tool_path" "$test_dir/bin/$tool"
done
export PATH="$test_dir/bin"
if command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
    printf '%s\n' 'FAIL: Python is present on the test PATH' >&2
    exit 1
fi
cd "$fixture"
xcrun swift -Xfrontend -parse-as-library scripts/backup_candidate.swift capture build/candidate.json
xcrun swift -Xfrontend -parse-as-library scripts/backup_candidate.swift check build/candidate.json
xcrun swift -Xfrontend -parse-as-library scripts/backup_candidate.swift attest build/archive build/candidate.json
xcrun swift -Xfrontend -parse-as-library scripts/backup_candidate.swift verify-archive build/archive
xcrun swift -Xfrontend -parse-as-library scripts/check_backup_device.swift build/credentials.json
if xcrun swift -Xfrontend -parse-as-library scripts/check_backup_device.swift build/missing.json > build/device.log 2>&1; then
    printf '%s\n' 'FAIL: Missing device evidence passed' >&2
    exit 1
fi
printf '%s\n' '{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"name":"iPhone 17","state":"Booted","isAvailable":true,"udid":"fixture-id"}]}}' > build/simulators.json
test "$(/bin/sh scripts/select_simulator.sh cloud < build/simulators.json)" = fixture-id
first_fingerprint=$(cat .git/clinical-simulator/fingerprint)
first_binary=$(cksum .git/clinical-simulator/select-simulator)
test "$(/bin/sh scripts/select_simulator.sh local 'iPhone 17' 27.0 < build/simulators.json)" = fixture-id
test "$(cksum .git/clinical-simulator/select-simulator)" = "$first_binary"
printf '\n' >> scripts/select_simulator.swift
test "$(/bin/sh scripts/select_simulator.sh cloud < build/simulators.json)" = fixture-id
test "$(cat .git/clinical-simulator/fingerprint)" != "$first_fingerprint"

# Count simulator requests without depending on the host's installed runtimes.
rm "$test_dir/bin/xcrun"
cat > "$test_dir/bin/xcrun" <<'SH'
#!/bin/sh
if [ "$1" = simctl ]; then
    printf '%s\n' called >> build/simctl-calls
    cat build/simulators.json
else
    exec /usr/bin/xcrun "$@"
fi
SH
/bin/chmod +x "$test_dir/bin/xcrun"
cat > build/selection.mk <<'MAKE'
selection-test:
	@test "$(SIMULATOR_ID)" = "$(EXPECTED_ID)"
	@test "$(DESTINATION)" = "platform=iOS Simulator,id=$(EXPECTED_ID)"
MAKE
make -s -f Makefile -f build/selection.mk selection-test EXPECTED_ID=fixture-id
test "$(cat build/simctl-calls)" = called
rm build/simctl-calls
make -s -f Makefile -f build/selection.mk selection-test SIMULATOR_ID=explicit EXPECTED_ID=explicit
make -s help > build/help.log
make -s -n data-test > build/data-test.log
make -s -n clean > build/clean.log
test ! -e build/simctl-calls

# Mock only the expensive test commands; keep the release evidence checks real.
cat > build/nested-make <<'SH'
#!/bin/sh
printf '%s\n' "$2" >> build/release-order
SH
/bin/chmod +x build/nested-make
make -s -j4 release-verify MAKE=./build/nested-make CLINICAL_BACKUP_CHECK_CREDENTIALS="$fixture/build/credentials.json"
test "$(cat build/release-order)" = "$(printf 'backup-test\nbackup-drive-check')"

xcrun swift -O -Xfrontend -parse-as-library "$repo_root/.codex/skills/my-screenshots/scripts/check_images.swift" \
    "$repo_root/screenshots" --report "$fixture/build/images.json" > build/images.log
if xcrun swift -Xfrontend -parse-as-library "$repo_root/.codex/skills/my-screenshots/scripts/check_images.swift" \
    "$repo_root/screenshots" --size invalid > build/arguments.log 2>&1; then
    printf '%s\n' 'FAIL: Invalid screenshot arguments passed' >&2
    exit 1
else
    test "$?" -eq 2
fi
printf '%s\n' 'PASS Command entry points, first-run compilation, cache reuse, Make selection, and release ordering without Python'
