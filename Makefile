SHELL := /bin/bash

SWIFT ?= swift
SWIFT_TEST_FLAGS ?=
ONLY_TESTING ?=
TEST_SELECTION = $(foreach selection,$(ONLY_TESTING),-only-testing:$(selection))

XCODE_DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR := $(XCODE_DEVELOPER_DIR)

PROJECT := clinical-swift.xcodeproj
SCHEME := clinical-swift
UNIT_TEST_SCHEME := clinical-swift-UnitTests
UI_TEST_SCHEME := clinical-swift-UITests
BACKUP_TEST_SCHEME := clinical-swift-Backups
CLINICAL_BACKUP_CHECK_CREDENTIALS ?= $(HOME)/.config/clinical-backups/check-credentials.json
CONFIGURATION ?= Debug
SIMULATOR ?= iPhone 17
SIMULATOR_OS ?= 27.0
ifeq ($(origin SIMULATOR_ID), undefined)
# Skip CI simulators so manual make runs cannot touch CI data; check-simulator also rejects overrides.
SIMULATOR_ID := $(shell DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" xcrun simctl list devices --json 2>/dev/null | python3 -c 'import json, sys; sim, os_ver = sys.argv[1], sys.argv[2]; is_ci = lambda n: any(k in n.strip().lower() for k in ("ci simulator", "clinical ci")); devices = json.load(sys.stdin)["devices"] if not is_ci(sim) else {}; ios = [d for k, items in sorted(devices.items()) if k.startswith("com.apple.CoreSimulator.SimRuntime.iOS-") for d in items if d.get("isAvailable", True) and not is_ci(d["name"])]; running = [d for d in ios if d.get("state") == "Booted"]; rt = "iOS-" + "-".join(os_ver.split(".")); fallback = [d for k, items in sorted(devices.items()) if k.endswith("." + rt) for d in items if d.get("isAvailable", True) and not is_ci(d["name"]) and d["name"] == sim]; choices = running or fallback; print(choices[0]["udid"] if choices else "")' "$(SIMULATOR)" "$(SIMULATOR_OS)" 2>/dev/null)
endif
BUNDLE_ID := in.bitehaus.clinical
APP_NAME := Clinical
TEAM_ID := WM7GP7FBL7
ASC_KEY_ID := 643N8M76NP
ASC_ISSUER_ID := 2b91f873-699b-498f-b1b6-5043a8d5f2ac
ASC_PRIVATE_KEYS_DIR ?= $(HOME)/.appstoreconnect/private_keys
XCODE_CLOUD_WORKFLOW_ID := 3EE75F71-B995-470A-9CB8-745EEEF77267

BUILD_DIR := $(CURDIR)/build
DERIVED_DATA := $(BUILD_DIR)/DerivedData-$(CONFIGURATION)
SOURCE_PACKAGES := $(BUILD_DIR)/SourcePackages
MODULE_CACHE := $(BUILD_DIR)/cache/modules
TMPDIR_PATH := $(BUILD_DIR)/tmp
LOG_DIR := $(BUILD_DIR)/logs
APP_PATH := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphonesimulator/$(SCHEME).app
ARCHIVE_DIR := $(BUILD_DIR)/Archives
EXPORT_DIR := $(BUILD_DIR)/Exports
LATEST_ARCHIVE_FILE := $(ARCHIVE_DIR)/.latest-archive
ARCHIVE_PATH := $(ARCHIVE_DIR)/$(APP_NAME)-$(BUILD_NUMBER).xcarchive
EXPORT_PATH := $(EXPORT_DIR)/$(APP_NAME)-$(BUILD_NUMBER)
TESTFLIGHT_EXPORT_OPTIONS := $(CURDIR)/TestFlightExportOptions.plist
APP_STORE_CONNECT_SCRIPT := $(CURDIR)/scripts/app_store_connect.swift

DESTINATION := platform=iOS Simulator,id=$(SIMULATOR_ID)
ARCHIVE_DESTINATION := generic/platform=iOS
XCBEAUTIFY := xcbeautify -q --disable-logging
XCODEBUILD_ENV := env CLANG_MODULE_CACHE_PATH="$(MODULE_CACHE)" SWIFT_MODULE_CACHE_PATH="$(MODULE_CACHE)" TMPDIR="$(TMPDIR_PATH)/"
RESOLVE_BUILD_NUMBER := env API_PRIVATE_KEYS_DIR="$(ASC_PRIVATE_KEYS_DIR)" $(SWIFT) "$(APP_STORE_CONNECT_SCRIPT)" next-build-number "$(BUNDLE_ID)" "$(ASC_KEY_ID)" "$(ASC_ISSUER_ID)"
TRIGGER_XCODE_CLOUD_BUILD := env API_PRIVATE_KEYS_DIR="$(ASC_PRIVATE_KEYS_DIR)" $(SWIFT) "$(APP_STORE_CONNECT_SCRIPT)" trigger-build "$(XCODE_CLOUD_WORKFLOW_ID)" "$(ASC_KEY_ID)" "$(ASC_ISSUER_ID)"
XCODEBUILD_COMMON_FLAGS := -project "$(PROJECT)" \
	-configuration "$(CONFIGURATION)" \
	-destination "$(DESTINATION)" \
	-destination-timeout 60 \
	-derivedDataPath "$(DERIVED_DATA)" \
	-clonedSourcePackagesDirPath "$(SOURCE_PACKAGES)" \
	-disableAutomaticPackageResolution \
	-skipPackageUpdates
NATIVE_ARCH := $(shell uname -m)
TEST_BUILD_SETTINGS := ENABLE_TESTABILITY=YES DEBUG_INFORMATION_FORMAT=dwarf ONLY_ACTIVE_ARCH=YES ARCHS=$(NATIVE_ARCH)
XCODEBUILD_FLAGS := $(XCODEBUILD_COMMON_FLAGS) -scheme "$(SCHEME)"
UNIT_TEST_FLAGS := $(XCODEBUILD_COMMON_FLAGS) -scheme "$(UNIT_TEST_SCHEME)" -parallel-testing-enabled NO $(TEST_BUILD_SETTINGS)
UI_TEST_FLAGS := $(XCODEBUILD_COMMON_FLAGS) -scheme "$(UI_TEST_SCHEME)" -parallel-testing-enabled YES $(TEST_BUILD_SETTINGS)
BACKUP_TEST_FLAGS := $(XCODEBUILD_COMMON_FLAGS) -scheme "$(BACKUP_TEST_SCHEME)" -parallel-testing-enabled NO $(TEST_BUILD_SETTINGS)

.DEFAULT_GOAL := build-and-run

.PHONY: data-test app-test
data-test:
	@$(SWIFT) test --disable-automatic-resolution --explicit-target-dependency-import-check error $(SWIFT_TEST_FLAGS)

.PHONY: backup-test backup-drive-check backup-authorize backup-export-credentials release-verify help diagnose prepare check-tools check-simulator check-app-store-connect-tools check-build-number next-build-number xcode-cloud-build resolve-packages build test ui-test release-testflight archive archive-with-build-number upload-testflight upload-testflight-with-build-number remove-archive remove-archive-with-build-number boot install run build-and-run uninstall clean

help:
	@printf "%s\n" \
		"Targets:" \
		"  make                  Build, install, and run on a running non-CI iOS simulator" \
		"                        Falls back to $(SIMULATOR) (iOS $(SIMULATOR_OS)) when none is running" \
		"  make build            Build the app" \
		"  make test             Run unit tests" \
		"  make app-test         Run app unit tests without package tests" \
		"  make data-test        Run model and persistence tests without Xcode" \
		"  make backup-test      Run local backup safety tests (no network)" \
		"  make backup-drive-check  Verify a synthetic backup through real Drive" \
		"  make release-verify   Run required Release backup and device checks" \
		"  make backup-authorize  Open internal Google test-account setup" \
		"  make backup-export-credentials  Save test credentials outside the repo" \
		"  make ui-test          Run UI tests" \
		"                        app-test and ui-test accept ONLY_TESTING='Bundle/Class[/method] ...'" \
		"" \
		"Xcode Cloud:" \
		"  make xcode-cloud-build  Start the configured workflow on its default branch" \
		"" \
		"TestFlight workflow:" \
		"  make release-testflight  Archive, upload, and remove locally" \
		"" \
		"Individual TestFlight steps:" \
		"  make next-build-number  Show the next App Store Connect build number" \
		"  make archive            Create a signed App Store archive" \
		"  make upload-testflight  Upload the latest existing archive only" \
		"  make remove-archive     Remove the latest local archive" \
		"  BUILD_NUMBER=N          Override automatic build-number selection" \
		"" \
		"Device Hub and maintenance:" \
		"  make install          Build and install on the selected iOS simulator" \
		"  make run              Launch the installed app" \
		"  make resolve-packages Resolve Swift package dependencies" \
		"  make diagnose         Print tool and project settings" \
		"  make uninstall        Remove the app from the selected iOS simulator" \
		"  make clean            Remove local build outputs"

diagnose:
	@printf "Project:       %s\n" "$(PROJECT)"
	@printf "Scheme:        %s\n" "$(SCHEME)"
	@printf "Unit tests:    %s\n" "$(UNIT_TEST_SCHEME)"
	@printf "UI tests:      %s\n" "$(UI_TEST_SCHEME)"
	@printf "Configuration: %s\n" "$(CONFIGURATION)"
	@printf "Xcode tools:   %s\n" "$(DEVELOPER_DIR)"
	@printf "Fallback:      %s (iOS %s)\n" "$(SIMULATOR)" "$(SIMULATOR_OS)"
	@printf "Target ID:     %s\n" "$(SIMULATOR_ID)"
	@printf "Destination:   %s\n" "$(DESTINATION)"
	@printf "App path:      %s\n" "$(APP_PATH)"
	@printf "Bundle ID:     %s\n" "$(BUNDLE_ID)"
	@printf "ASC key ID:    %s\n" "$(ASC_KEY_ID)"
	@printf "ASC issuer ID: %s\n" "$(ASC_ISSUER_ID)"
	@printf "Cloud workflow: %s\n" "$(XCODE_CLOUD_WORKFLOW_ID)"
	@printf "xcodebuild:    %s\n" "$$(xcrun --find xcodebuild)"
	@printf "xcbeautify:    %s\n" "$$(command -v $(firstword $(XCBEAUTIFY)))"

prepare:
	@mkdir -p "$(DERIVED_DATA)" "$(SOURCE_PACKAGES)" "$(MODULE_CACHE)" "$(TMPDIR_PATH)" "$(LOG_DIR)" "$(ARCHIVE_DIR)" "$(EXPORT_DIR)"

check-tools:
	@command -v xcodebuild >/dev/null
	@command -v xcrun >/dev/null
	@command -v $(firstword $(XCBEAUTIFY)) >/dev/null || { echo "xcbeautify is required. Install it with: brew install xcbeautify"; exit 1; }
	@test -d "$(DEVELOPER_DIR)" || { echo "Xcode developer directory not found: $(DEVELOPER_DIR)"; exit 1; }

check-simulator:
	@python3 -c 'import json, subprocess, sys; \
sim, os_ver, sim_id, dest = sys.argv[1:5]; \
is_ci = lambda n: any(k in n.strip().lower() for k in ("ci simulator", "clinical ci")); \
fail = lambda m: (print(m, file=sys.stderr), sys.exit(1)); \
is_ci(sim) and fail("Refusing to use simulator \"%s\": CI simulators are reserved for CI." % sim); \
fields = {k.strip().lower(): v.strip() for part in dest.split(",") if "=" in part for k, v in [part.split("=", 1)]}; \
[fail("Refusing to use destination \"%s\": CI simulators are reserved for CI." % dest) for k in ("name", "id") if is_ci(fields.get(k, ""))]; \
sim_id.strip() or fail("No running non-CI iOS simulator was found, and fallback %s (iOS %s) is unavailable." % (sim, os_ver)); \
is_ci(sim_id) and fail("Refusing to use simulator \"%s\": CI simulators are reserved for CI." % sim_id); \
proc = subprocess.run(["xcrun", "simctl", "list", "devices", "--json"], capture_output=True, text=True); \
proc.returncode == 0 or fail("Unable to inspect iOS simulators with xcrun simctl."); \
all_devs = [d for items in json.loads(proc.stdout)["devices"].values() for d in items]; \
match = lambda x: next((d for d in all_devs if (d["udid"].lower() == x.lower() or d["name"] == x) and is_ci(d["name"])), None); \
[fail("Refusing to use simulator \"%s\" (%s): CI simulators are reserved for CI." % (d["name"], d["udid"])) for target in (sim_id.strip(), fields.get("id", "")) if target for d in [match(target)] if d]' "$(SIMULATOR)" "$(SIMULATOR_OS)" "$(SIMULATOR_ID)" "$(DESTINATION)"

check-app-store-connect-tools:
	@command -v $(firstword $(SWIFT)) >/dev/null
	@command -v openssl >/dev/null
	@test -f "$(APP_STORE_CONNECT_SCRIPT)" || { echo "App Store Connect script is missing: $(APP_STORE_CONNECT_SCRIPT)"; exit 1; }

check-build-number:
	@test -n "$(BUILD_NUMBER)" || { echo "BUILD_NUMBER is required. Example: make upload-testflight BUILD_NUMBER=2"; exit 2; }
	@[[ "$(BUILD_NUMBER)" =~ ^[0-9]+(\.[0-9]+){0,2}$$ ]] || { echo "BUILD_NUMBER must contain one to three numeric components, for example 2 or 2.1"; exit 2; }

next-build-number: check-app-store-connect-tools
	@number="$$($(RESOLVE_BUILD_NUMBER))" || exit; \
	printf "Next App Store Connect build number: %s\n" "$$number"

xcode-cloud-build: check-app-store-connect-tools
	@$(TRIGGER_XCODE_CLOUD_BUILD)

resolve-packages: check-tools prepare
	@set -o pipefail; \
	$(XCODEBUILD_ENV) xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-clonedSourcePackagesDirPath "$(SOURCE_PACKAGES)" \
		-resolvePackageDependencies \
		2>&1 | tee "$(LOG_DIR)/resolve-packages.log" | $(XCBEAUTIFY)

build: check-tools check-simulator prepare
	@set -o pipefail; \
	$(XCODEBUILD_ENV) xcodebuild \
		$(XCODEBUILD_FLAGS) $(EXTRA_BUILD_FLAGS) \
		build \
		2>&1 | tee "$(LOG_DIR)/build.log" | $(XCBEAUTIFY)

test: check-tools check-simulator prepare
	@$(MAKE) --no-print-directory data-test
	@$(MAKE) --no-print-directory app-test

app-test: check-tools check-simulator prepare
	@set -o pipefail; \
	$(XCODEBUILD_ENV) xcodebuild \
		$(UNIT_TEST_FLAGS) $(TEST_SELECTION) \
		test \
		2>&1 | tee "$(LOG_DIR)/test.log" | $(XCBEAUTIFY); \
	status=$$?; \
	if (( status != 0 )); then \
		awk '/recorded an issue/{ issue = 1 } issue { print } issue && /^✘ Test .* failed after/{ issue = 0 }' "$(LOG_DIR)/test.log"; \
	fi; \
	exit $$status

backup-test: check-tools check-simulator prepare
	@set -o pipefail; $(XCODEBUILD_ENV) xcodebuild $(BACKUP_TEST_FLAGS) \
		-skip-testing:clinical-swiftBackupTests/BackupDriveTests test \
		2>&1 | tee "$(LOG_DIR)/backup-test.log" | $(XCBEAUTIFY)

backup-drive-check: check-tools check-simulator prepare
	@test -r "$(CLINICAL_BACKUP_CHECK_CREDENTIALS)" || { echo "Missing Drive check credentials. Run make backup-authorize, sign in, then make backup-export-credentials."; exit 1; }
	@set -o pipefail; $(XCODEBUILD_ENV) xcodebuild $(BACKUP_TEST_FLAGS) \
		CLINICAL_BACKUP_CHECK_CREDENTIALS="$(CLINICAL_BACKUP_CHECK_CREDENTIALS)" \
		-only-testing:clinical-swiftBackupTests/BackupDriveTests test \
		2>&1 | tee "$(LOG_DIR)/backup-drive-check.log" | $(XCBEAUTIFY)

backup-authorize: check-tools check-simulator prepare
	@$(MAKE) --no-print-directory build CONFIGURATION=Release EXTRA_BUILD_FLAGS='"CLINICAL_INTERNAL_CONDITIONS=INTERNAL_BACKUP_CHECK"'
	@xcrun simctl install "$(SIMULATOR_ID)" "$(DERIVED_DATA)/Build/Products/Release-iphonesimulator/$(SCHEME).app"
	@xcrun simctl terminate "$(SIMULATOR_ID)" "$(BUNDLE_ID)" >/dev/null 2>&1 || true
	@xcrun simctl launch "$(SIMULATOR_ID)" "$(BUNDLE_ID)" --backup-check-authorize

backup-export-credentials: check-simulator
	@CLINICAL_BACKUP_CHECK_CREDENTIALS="$(CLINICAL_BACKUP_CHECK_CREDENTIALS)" scripts/export_backup_check_credentials.sh "$(SIMULATOR_ID)"

# Keep the checks inside one recipe so make -j cannot run them concurrently.
release-verify: check-simulator prepare
	@python3 scripts/backup_candidate.py capture "$(BUILD_DIR)/backup-candidate.json"
	@$(MAKE) --no-print-directory backup-test CONFIGURATION=Release
	@$(MAKE) --no-print-directory backup-drive-check CONFIGURATION=Release
	@python3 scripts/backup_candidate.py check "$(BUILD_DIR)/backup-candidate.json"
	@python3 scripts/check_backup_device.py "$(CLINICAL_BACKUP_CHECK_CREDENTIALS)"

ui-test: check-tools check-simulator prepare
	@set -o pipefail; \
	$(XCODEBUILD_ENV) xcodebuild \
		$(UI_TEST_FLAGS) $(TEST_SELECTION) \
		test \
		2>&1 | tee "$(LOG_DIR)/ui-test.log" | $(XCBEAUTIFY)

archive: check-tools prepare
	@number="$(BUILD_NUMBER)"; \
	if [[ -z "$$number" ]]; then number="$$($(RESOLVE_BUILD_NUMBER))" || exit; fi; \
	$(MAKE) --no-print-directory archive-with-build-number BUILD_NUMBER="$$number"

archive-with-build-number: check-tools check-build-number prepare
	@available="$$(df -h "$(ARCHIVE_DIR)" | awk 'NR == 2 { print $$4 }')"; \
	archive_count="$$(find "$(ARCHIVE_DIR)" -maxdepth 1 -type d -name '*.xcarchive' | wc -l | tr -d '[:space:]')"; \
	printf "Archive storage: %s\nAvailable disk:  %s\nOld archives:    %s\n" "$(ARCHIVE_DIR)" "$$available" "$$archive_count"
	@if [[ -f "$(LATEST_ARCHIVE_FILE)" ]] && [[ "$$(< "$(LATEST_ARCHIVE_FILE)")" == "$(BUILD_NUMBER)" ]]; then rm -f "$(LATEST_ARCHIVE_FILE)"; fi
	@python3 scripts/backup_candidate.py capture "$(ARCHIVE_PATH).candidate.json"
	@rm -rf "$(ARCHIVE_PATH)"
	@set -o pipefail; \
	$(XCODEBUILD_ENV) xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration Release \
		-destination "$(ARCHIVE_DESTINATION)" \
		-archivePath "$(ARCHIVE_PATH)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-clonedSourcePackagesDirPath "$(SOURCE_PACKAGES)" \
		-allowProvisioningUpdates \
		DEVELOPMENT_TEAM="$(TEAM_ID)" \
		CURRENT_PROJECT_VERSION="$(BUILD_NUMBER)" \
		archive \
		2>&1 | tee "$(LOG_DIR)/archive-$(BUILD_NUMBER).log" | $(XCBEAUTIFY)
	@python3 scripts/backup_candidate.py attest "$(ARCHIVE_PATH)" "$(ARCHIVE_PATH).candidate.json"
	@printf '%s\n' "$(BUILD_NUMBER)" > "$(LATEST_ARCHIVE_FILE).tmp"
	@mv "$(LATEST_ARCHIVE_FILE).tmp" "$(LATEST_ARCHIVE_FILE)"

upload-testflight: check-tools prepare
	@number="$(BUILD_NUMBER)"; \
	if [[ -z "$$number" ]]; then \
		test -f "$(LATEST_ARCHIVE_FILE)" || { echo "No latest archive is recorded. Run make archive first or use make release-testflight."; exit 1; }; \
		number="$$(< "$(LATEST_ARCHIVE_FILE)")"; \
	fi; \
	$(MAKE) --no-print-directory upload-testflight-with-build-number BUILD_NUMBER="$$number"

upload-testflight-with-build-number: check-tools check-build-number prepare
	@test -d "$(ARCHIVE_PATH)" || { echo "Missing archive at $(ARCHIVE_PATH)"; exit 1; }
	@python3 scripts/backup_candidate.py verify-archive "$(ARCHIVE_PATH)"
	@$(MAKE) --no-print-directory release-verify CONFIGURATION=Release
	@python3 scripts/backup_candidate.py verify-archive "$(ARCHIVE_PATH)"
	@rm -rf "$(EXPORT_PATH)"
	@mkdir -p "$(EXPORT_PATH)"
	@set -o pipefail; \
	$(XCODEBUILD_ENV) xcodebuild \
		-exportArchive \
		-archivePath "$(ARCHIVE_PATH)" \
		-exportPath "$(EXPORT_PATH)" \
		-exportOptionsPlist "$(TESTFLIGHT_EXPORT_OPTIONS)" \
		-allowProvisioningUpdates \
		2>&1 | tee "$(LOG_DIR)/upload-testflight-$(BUILD_NUMBER).log" | $(XCBEAUTIFY)

remove-archive: prepare
	@number="$(BUILD_NUMBER)"; \
	if [[ -z "$$number" ]]; then \
		if [[ ! -f "$(LATEST_ARCHIVE_FILE)" ]]; then echo "No local archive to remove."; exit 0; fi; \
		number="$$(< "$(LATEST_ARCHIVE_FILE)")"; \
	fi; \
	$(MAKE) --no-print-directory remove-archive-with-build-number BUILD_NUMBER="$$number"

remove-archive-with-build-number: check-build-number prepare
	@if [[ -d "$(ARCHIVE_PATH)" ]]; then \
		rm -rf "$(ARCHIVE_PATH)"; \
		printf "Removed local archive: %s\n" "$(ARCHIVE_PATH)"; \
	else \
		printf "Local archive is already absent: %s\n" "$(ARCHIVE_PATH)"; \
	fi
	@if [[ -f "$(LATEST_ARCHIVE_FILE)" ]] && [[ "$$(< "$(LATEST_ARCHIVE_FILE)")" == "$(BUILD_NUMBER)" ]]; then rm -f "$(LATEST_ARCHIVE_FILE)"; fi

release-testflight: check-tools prepare
	@number="$(BUILD_NUMBER)"; \
	if [[ -z "$$number" ]]; then number="$$($(RESOLVE_BUILD_NUMBER))" || exit; fi; \
	$(MAKE) --no-print-directory archive-with-build-number BUILD_NUMBER="$$number" && \
	$(MAKE) --no-print-directory upload-testflight-with-build-number BUILD_NUMBER="$$number" && \
	$(MAKE) --no-print-directory remove-archive-with-build-number BUILD_NUMBER="$$number"

boot: check-tools check-simulator
	@xcrun simctl boot "$(SIMULATOR_ID)" >/dev/null 2>&1 || true
	@xcrun simctl bootstatus "$(SIMULATOR_ID)" -b

install: build boot
	@test -d "$(APP_PATH)" || { echo "Missing built app at $(APP_PATH)"; exit 1; }
	@xcrun simctl install "$(SIMULATOR_ID)" "$(APP_PATH)"

run: check-tools check-simulator boot
	@xcrun simctl launch "$(SIMULATOR_ID)" "$(BUNDLE_ID)"

build-and-run: install run

uninstall: check-tools check-simulator boot
	@xcrun simctl uninstall "$(SIMULATOR_ID)" "$(BUNDLE_ID)" || true

clean:
	@rm -rf "$(BUILD_DIR)"
