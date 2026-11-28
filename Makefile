SHELL := /bin/bash

SWIFT ?= swift
SWIFT_TEST_FLAGS ?=
ONLY_TESTING ?=
TEST_SELECTION = $(foreach selection,$(ONLY_TESTING),-only-testing:$(selection))
TEST_CLASSES := $(sort $(foreach selection,$(ONLY_TESTING),$(word 1,$(subst /, ,$(selection)))/$(word 2,$(subst /, ,$(selection)))))
# One class cannot use multiple runners. Keep bundle and multi-class runs parallel.
UI_TEST_WORKERS ?= 5
UI_TEST_PARALLEL_ENABLED := YES
ifeq ($(words $(TEST_CLASSES)),1)
ifneq ($(word 2,$(subst /, ,$(firstword $(ONLY_TESTING)))),)
UI_TEST_PARALLEL_ENABLED := NO
endif
endif
UI_TEST_PARALLEL_FLAGS = -parallel-testing-enabled $(UI_TEST_PARALLEL_ENABLED) $(if $(filter YES,$(UI_TEST_PARALLEL_ENABLED)),-parallel-testing-worker-count $(UI_TEST_WORKERS))
CI_LOCAL_WIDGET_PERF ?= 1

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
SIMULATOR_NAME ?=
DEVICE ?=
LAUNCH_ARGS ?=
APPEARANCE ?=
OUT ?= $(BUILD_DIR)/screenshot.png
SCREENSHOT_DELAY ?= 2
SIMULATOR_SCRIPT := $(CURDIR)/scripts/simulator.swift
DEVICE_SCRIPT := $(CURDIR)/scripts/device.swift
EXPLICIT_SIMULATOR_ID := $(if $(filter-out undefined,$(origin SIMULATOR_ID)),$(strip $(SIMULATOR_ID)),)
EXPLICIT_DESTINATION := $(if $(filter-out undefined,$(origin DESTINATION)),$(strip $(DESTINATION)),)
ifeq ($(origin SIMULATOR_ID), undefined)
# Skip CI simulators so manual make runs cannot touch CI data; check-simulator also rejects overrides.
# Use read-only resolve during expansion so make -n never creates a simulator; cache only when found.
SIMULATOR_ID = $(strip $(eval _sim_resolved := $$(shell DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" "$(SIMULATOR_BIN)" resolve --simulator "$(SIMULATOR)" --os "$(SIMULATOR_OS)" --name "$(SIMULATOR_NAME)" 2>/dev/null))$(if $(_sim_resolved),$(eval SIMULATOR_ID := $(_sim_resolved))$(_sim_resolved),))
endif
BUNDLE_ID := in.bitehaus.clinical
APP_NAME := Clinical
TEAM_ID := WM7GP7FBL7
ASC_KEY_ID := D7Q5V2XQ35
ASC_ISSUER_ID := 2b91f873-699b-498f-b1b6-5043a8d5f2ac
ASC_PRIVATE_KEYS_DIR ?= $(HOME)/.appstoreconnect/private_keys
XCODE_CLOUD_WORKFLOW_ID := 3EE75F71-B995-470A-9CB8-745EEEF77267

BUILD_DIR := $(CURDIR)/build
SIMULATOR_BIN := $(BUILD_DIR)/bin/simulator
PREBUILT ?= 1
# Skip building/embedding the widget extension for unit-test-only runs unless overridden.
ifeq ($(origin WITHOUT_WIDGET), undefined)
ifeq ($(filter-out app-test,$(MAKECMDGOALS)),)
ifneq ($(filter app-test,$(MAKECMDGOALS)),)
WITHOUT_WIDGET := 1
else
WITHOUT_WIDGET := 0
endif
else
WITHOUT_WIDGET := 0
endif
endif
PREBUILT_DEPS_SCRIPT := $(CURDIR)/scripts/prebuilt_deps.swift
PREBUILT_DEPS_BIN := $(BUILD_DIR)/bin/prebuilt-deps
PREBUILT_DEPS_DIR ?= $(BUILD_DIR)/PrebuiltDeps
ifeq ($(WITHOUT_WIDGET),1)
PREBUILT_PROJECT := $(PREBUILT_DEPS_DIR)/clinical-swift-prebuilt-nowidget.xcodeproj
PREBUILT_WIDGET_FLAG := --without-widget
WIDGET_SUFFIX := -NoWidget
else
PREBUILT_PROJECT := $(PREBUILT_DEPS_DIR)/clinical-swift-prebuilt.xcodeproj
PREBUILT_WIDGET_FLAG :=
WIDGET_SUFFIX :=
endif
DERIVED_DATA ?= $(BUILD_DIR)/DerivedData-$(CONFIGURATION)
PREBUILT_DERIVED_DATA := $(BUILD_DIR)/DerivedData-$(CONFIGURATION)-Prebuilt$(WIDGET_SUFFIX)
SOURCE_PACKAGES ?= $(BUILD_DIR)/SourcePackages
TMPDIR_PATH := $(BUILD_DIR)/tmp
LOG_DIR := $(BUILD_DIR)/logs
# Use prebuilt binary XCFrameworks for local Debug simulator builds unless PREBUILT=0.
USE_PREBUILT := 0
ifeq ($(CONFIGURATION),Debug)
ifeq ($(PREBUILT),1)
USE_PREBUILT := 1
endif
endif
ifeq ($(USE_PREBUILT),1)
BUILD_PROJECT := $(PREBUILT_PROJECT)
BUILD_DERIVED_DATA := $(PREBUILT_DERIVED_DATA)
# Keep test outputs separate so hosted test bundles do not bloat the installed app or bust app caches.
TEST_DERIVED_DATA ?= $(BUILD_DIR)/DerivedData-$(CONFIGURATION)-Tests-Prebuilt$(WIDGET_SUFFIX)
else
BUILD_PROJECT := $(PROJECT)
BUILD_DERIVED_DATA := $(DERIVED_DATA)
TEST_DERIVED_DATA ?= $(BUILD_DIR)/DerivedData-$(CONFIGURATION)-Tests
endif
APP_PATH := $(BUILD_DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphonesimulator/$(SCHEME).app
DEVICE_APP_PATH := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphoneos/$(SCHEME).app
ARCHIVE_DIR := $(BUILD_DIR)/Archives
EXPORT_DIR := $(BUILD_DIR)/Exports
LATEST_ARCHIVE_FILE := $(ARCHIVE_DIR)/.latest-archive
ARCHIVE_PATH := $(ARCHIVE_DIR)/$(APP_NAME)-$(BUILD_NUMBER).xcarchive
EXPORT_PATH := $(EXPORT_DIR)/$(APP_NAME)-$(BUILD_NUMBER)
TESTFLIGHT_EXPORT_OPTIONS := $(CURDIR)/TestFlightExportOptions.plist
APP_STORE_CONNECT_SCRIPT := $(CURDIR)/scripts/app_store_connect.swift

DESTINATION = platform=iOS Simulator,id=$(SIMULATOR_ID)
SIMULATOR_BUILD_DESTINATION := generic/platform=iOS Simulator
DEVICE_DESTINATION := generic/platform=iOS
ARCHIVE_DESTINATION := generic/platform=iOS
XCBEAUTIFY ?= xcbeautify -q --disable-logging
# Pin the xcodebuild environment so shell noise does not bust XCBuildData BuildDescription caches.
XCODEBUILD_ENV := env -i \
	HOME="$(HOME)" \
	USER="$(USER)" \
	LOGNAME="$(or $(LOGNAME),$(USER))" \
	LANG="en_US.UTF-8" \
	PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
	DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" \
	TMPDIR="$(TMPDIR_PATH)/"
RESOLVE_BUILD_NUMBER := env API_PRIVATE_KEYS_DIR="$(ASC_PRIVATE_KEYS_DIR)" $(SWIFT) "$(APP_STORE_CONNECT_SCRIPT)" next-build-number "$(BUNDLE_ID)" "$(ASC_KEY_ID)" "$(ASC_ISSUER_ID)"
TRIGGER_XCODE_CLOUD_BUILD := env API_PRIVATE_KEYS_DIR="$(ASC_PRIVATE_KEYS_DIR)" $(SWIFT) "$(APP_STORE_CONNECT_SCRIPT)" trigger-build "$(XCODE_CLOUD_WORKFLOW_ID)" "$(ASC_KEY_ID)" "$(ASC_ISSUER_ID)"
XCODEBUILD_APP_FLAGS = -project "$(BUILD_PROJECT)" \
	-configuration "$(CONFIGURATION)" \
	-destination "$(SIMULATOR_BUILD_DESTINATION)" \
	-destination-timeout 60 \
	-derivedDataPath "$(BUILD_DERIVED_DATA)" \
	-clonedSourcePackagesDirPath "$(SOURCE_PACKAGES)" \
	-disableAutomaticPackageResolution \
	-skipPackageUpdates
XCODEBUILD_TEST_BUILD_COMMON_FLAGS = -project "$(BUILD_PROJECT)" \
	-configuration "$(CONFIGURATION)" \
	-destination "$(SIMULATOR_BUILD_DESTINATION)" \
	-destination-timeout 60 \
	-derivedDataPath "$(TEST_DERIVED_DATA)" \
	-clonedSourcePackagesDirPath "$(SOURCE_PACKAGES)" \
	-disableAutomaticPackageResolution \
	-skipPackageUpdates
XCODEBUILD_TEST_RUN_COMMON_FLAGS = -project "$(BUILD_PROJECT)" \
	-configuration "$(CONFIGURATION)" \
	-destination "$(DESTINATION)" \
	-destination-timeout 60 \
	-derivedDataPath "$(TEST_DERIVED_DATA)"
NATIVE_ARCH := $(shell uname -m)
CLI_COMMON_BUILD_SETTINGS := COMPILER_INDEX_STORE_ENABLE=NO CLANG_ENABLE_CODE_COVERAGE=NO CLANG_COVERAGE_MAPPING=NO
# Skip preview thunks, debug dylib indirection, validation, asset/PNG compression, and loc emission on Debug simulator CLI builds.
DEBUG_SIM_FAST_BUILD_SETTINGS := \
	ENABLE_PREVIEWS=NO \
	ENABLE_DEBUG_DYLIB=NO \
	VALIDATE_PRODUCT=NO \
	ASSETCATALOG_COMPILER_OPTIMIZATION=time \
	COMPRESS_PNG_FILES=NO \
	SWIFT_EMIT_LOC_STRINGS=NO \
	STRING_CATALOG_GENERATE_SYMBOLS=NO
# Keep Release backup tests aligned with Release archives; skip only validation and loc/symbol extraction.
RELEASE_TEST_FAST_BUILD_SETTINGS := \
	VALIDATE_PRODUCT=NO \
	SWIFT_EMIT_LOC_STRINGS=NO \
	STRING_CATALOG_GENERATE_SYMBOLS=NO
# Skip dSYM, dead-code stripping, and loc emission during Debug CLI builds.
DEBUG_FAST_BUILD_SETTINGS := \
	DEBUG_INFORMATION_FORMAT=dwarf \
	DEAD_CODE_STRIPPING=NO \
	SWIFT_EMIT_LOC_STRINGS=NO \
	STRING_CATALOG_GENERATE_SYMBOLS=NO
SIMULATOR_BUILD_SETTINGS := ONLY_ACTIVE_ARCH=YES ARCHS=$(NATIVE_ARCH) $(CLI_COMMON_BUILD_SETTINGS)
DEVICE_BUILD_SETTINGS := $(CLI_COMMON_BUILD_SETTINGS)
DEBUG_TEST_BUILD_SETTINGS :=
ifeq ($(CONFIGURATION),Debug)
SIMULATOR_BUILD_SETTINGS += DEBUG_INFORMATION_FORMAT=dwarf DEAD_CODE_STRIPPING=NO $(DEBUG_SIM_FAST_BUILD_SETTINGS)
DEVICE_BUILD_SETTINGS += $(DEBUG_FAST_BUILD_SETTINGS) ONLY_ACTIVE_ARCH=YES ARCHS=arm64
DEBUG_TEST_BUILD_SETTINGS := DEAD_CODE_STRIPPING=NO $(DEBUG_SIM_FAST_BUILD_SETTINGS)
endif
TEST_BUILD_SETTINGS := ENABLE_TESTABILITY=YES DEBUG_INFORMATION_FORMAT=dwarf ONLY_ACTIVE_ARCH=YES ARCHS=$(NATIVE_ARCH) $(CLI_COMMON_BUILD_SETTINGS)
XCODEBUILD_FLAGS = $(XCODEBUILD_APP_FLAGS) -scheme "$(SCHEME)" $(SIMULATOR_BUILD_SETTINGS)
UNIT_TEST_BUILD_FLAGS = $(XCODEBUILD_TEST_BUILD_COMMON_FLAGS) -scheme "$(UNIT_TEST_SCHEME)" $(TEST_BUILD_SETTINGS) $(DEBUG_TEST_BUILD_SETTINGS) $(EXTRA_UNIT_TEST_FLAGS)
UNIT_TEST_RUN_FLAGS = $(XCODEBUILD_TEST_RUN_COMMON_FLAGS) -scheme "$(UNIT_TEST_SCHEME)" -parallel-testing-enabled NO
UI_TEST_BUILD_FLAGS = $(XCODEBUILD_TEST_BUILD_COMMON_FLAGS) -scheme "$(UI_TEST_SCHEME)" $(TEST_BUILD_SETTINGS) $(DEBUG_TEST_BUILD_SETTINGS)
UI_TEST_RUN_FLAGS = $(XCODEBUILD_TEST_RUN_COMMON_FLAGS) -scheme "$(UI_TEST_SCHEME)" $(UI_TEST_PARALLEL_FLAGS) -collect-test-diagnostics on-failure
BACKUP_TEST_BUILD_FLAGS = $(XCODEBUILD_TEST_BUILD_COMMON_FLAGS) -scheme "$(BACKUP_TEST_SCHEME)" $(TEST_BUILD_SETTINGS) $(if $(filter Debug,$(CONFIGURATION)),$(DEBUG_TEST_BUILD_SETTINGS),$(RELEASE_TEST_FAST_BUILD_SETTINGS)) $(EXTRA_BACKUP_TEST_FLAGS)
BACKUP_TEST_RUN_FLAGS = $(XCODEBUILD_TEST_RUN_COMMON_FLAGS) -scheme "$(BACKUP_TEST_SCHEME)" -parallel-testing-enabled NO
COMBINED_TEST_BUILD_FLAGS = $(XCODEBUILD_TEST_BUILD_COMMON_FLAGS) -scheme "$(SCHEME)" $(TEST_BUILD_SETTINGS) $(DEBUG_TEST_BUILD_SETTINGS)
COMBINED_TEST_RUN_FLAGS = $(XCODEBUILD_TEST_RUN_COMMON_FLAGS) -scheme "$(SCHEME)"

.DEFAULT_GOAL := build-and-run

.PHONY: data-test app-test
data-test:
	@$(SWIFT) test --disable-automatic-resolution --explicit-target-dependency-import-check error --disable-xctest $(SWIFT_TEST_FLAGS)

.PHONY: agent-monitor backup-test backup-test-build backup-test-without-building backup-drive-check backup-authorize backup-export-credentials release-verify help diagnose prepare check-tools check-simulator sim-id ensure-prebuilt check-device check-app-store-connect-tools check-build-number next-build-number xcode-cloud-build resolve-packages build build-device test app-test-without-building ui-test ui-test-without-building build-for-testing ci-local-sim widget-perf-test release-testflight archive archive-with-build-number upload-testflight upload-testflight-with-build-number remove-archive remove-archive-with-build-number boot install install-device validate-appearance require-appearance appearance run build-and-run screenshot snap uninstall clean

help:
	@printf "%s\n" \
		"Targets:" \
		"  make                  Build, install, and run on the selected non-CI iOS simulator" \
		"                        Pass SIMULATOR_NAME='<unique name>' (creates if missing) or SIMULATOR_ID='<udid>'" \
		"                        Accepts LAUNCH_ARGS='...' and APPEARANCE=light|dark" \
		"                        Falls back to $(SIMULATOR) (iOS $(SIMULATOR_OS)) when no simulator is booted" \
		"  make sim-id           Print the target simulator UDID (creates SIMULATOR_NAME if missing)" \
		"  make build            Build the app (Debug simulator uses prebuilt XCFrameworks; pass PREBUILT=0 to opt out)" \
		"  make build-device     Build the app for iOS devices" \
		"  make build-for-testing  Build Debug app, widget, unit tests, and UI tests once" \
		"  make test             Run unit tests" \
		"  make app-test         Run app unit tests without package tests (defaults to WITHOUT_WIDGET=1)" \
		"  make app-test-without-building  Run app unit tests from existing build-for-testing output" \
		"  make data-test        Run model and persistence tests without Xcode" \
		"  make backup-test      Run local backup safety tests (no network)" \
		"  make backup-test-build  Build backup tests without running them" \
		"  make backup-test-without-building  Run local backup safety tests from existing build output" \
		"  make backup-drive-check  Verify a synthetic backup through real Drive" \
		"  make release-verify   Run required Release backup and device checks" \
		"  make backup-authorize  Open internal Google test-account setup" \
		"  make backup-export-credentials  Save test credentials outside the repo" \
		"  make ui-test          Run UI tests" \
		"  make ui-test-without-building  Run UI tests from existing build-for-testing output" \
		"  make ci-local-sim     Run the full local CI sequence (Debug build, overlapped unit + Release backup build, backup tests, UI tests)" \
		"                        app-test and ui-test accept ONLY_TESTING='Bundle/Class[/method] ...'" \
		"                        UI filters for one class run in sequence; other UI runs use parallel runners" \
		"  make widget-perf-test Measure Daily Timeline widget tap latency on a physical device (requires DEVICE='<name|udid>')" \
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
		"  make install-device   Build and install on a physical iOS device (requires DEVICE='<name|udid>')" \
		"  make run              Relaunch the installed app (accepts LAUNCH_ARGS='...' and APPEARANCE=light|dark)" \
		"  make appearance       Set simulator appearance (requires APPEARANCE=light|dark)" \
		"  make screenshot       Relaunch the installed app and capture a PNG (OUT=$(OUT), APPEARANCE, LAUNCH_ARGS, SCREENSHOT_DELAY=$(SCREENSHOT_DELAY))" \
		"  make snap             Capture the current simulator screen without relaunching (OUT=$(OUT))" \
		"  make resolve-packages Resolve Swift package dependencies" \
		"  make diagnose         Print tool and project settings" \
		"  make agent-monitor    Open the live PR review and address loop monitor UI" \
		"  make uninstall        Remove the app from the selected iOS simulator" \
		"  make clean            Remove local build outputs"

$(SIMULATOR_BIN): $(SIMULATOR_SCRIPT)
	@mkdir -p "$(dir $@)"
	@tmp="$@.$$$$"; trap 'rm -f "$$tmp"' EXIT HUP INT TERM; \
	DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" xcrun swiftc \
		-sdk "$$(DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" xcrun --sdk macosx --show-sdk-path)" \
		"$(SIMULATOR_SCRIPT)" -o "$$tmp" && mv "$$tmp" "$@"

$(PREBUILT_DEPS_BIN): $(PREBUILT_DEPS_SCRIPT)
	@mkdir -p "$(dir $@)"
	@tmp="$@.$$$$"; trap 'rm -f "$$tmp"' EXIT HUP INT TERM; \
	DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" xcrun swiftc \
		-sdk "$$(DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" xcrun --sdk macosx --show-sdk-path)" \
		"$(PREBUILT_DEPS_SCRIPT)" -o "$$tmp" && mv "$$tmp" "$@"

diagnose: $(SIMULATOR_BIN)
	@target_id="$(EXPLICIT_SIMULATOR_ID)"; \
	if [[ -z "$$target_id" ]]; then \
		target_id="$$(DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" "$(SIMULATOR_BIN)" resolve --simulator "$(SIMULATOR)" --os "$(SIMULATOR_OS)" --name "$(SIMULATOR_NAME)" 2>/dev/null || true)"; \
	fi; \
	dest="$(if $(EXPLICIT_DESTINATION),$(EXPLICIT_DESTINATION),platform=iOS Simulator,id=$$target_id)"; \
	printf "Project:       %s\n" "$(BUILD_PROJECT)"; \
	printf "Prebuilt:      %s\n" "$(USE_PREBUILT)"; \
	printf "WithoutWidget: %s\n" "$(WITHOUT_WIDGET)"; \
	printf "Scheme:        %s\n" "$(SCHEME)"; \
	printf "Unit tests:    %s\n" "$(UNIT_TEST_SCHEME)"; \
	printf "UI tests:      %s\n" "$(UI_TEST_SCHEME)"; \
	printf "Configuration: %s\n" "$(CONFIGURATION)"; \
	printf "Xcode tools:   %s\n" "$(DEVELOPER_DIR)"; \
	printf "Fallback:      %s (iOS %s)\n" "$(SIMULATOR)" "$(SIMULATOR_OS)"; \
	printf "Target Name:   %s\n" "$(SIMULATOR_NAME)"; \
	printf "Target ID:     %s\n" "$$target_id"; \
	printf "Destination:   %s\n" "$$dest"; \
	printf "App path:      %s\n" "$(APP_PATH)"; \
	printf "Bundle ID:     %s\n" "$(BUNDLE_ID)"; \
	printf "ASC key ID:    %s\n" "$(ASC_KEY_ID)"; \
	printf "ASC issuer ID: %s\n" "$(ASC_ISSUER_ID)"; \
	printf "Cloud workflow: %s\n" "$(XCODE_CLOUD_WORKFLOW_ID)"; \
	printf "xcodebuild:    %s\n" "$$(xcrun --find xcodebuild)"; \
	printf "xcbeautify:    %s\n" "$$(command -v $(firstword $(XCBEAUTIFY)))"

prepare:
	@mkdir -p "$(DERIVED_DATA)" "$(BUILD_DERIVED_DATA)" "$(TEST_DERIVED_DATA)" "$(SOURCE_PACKAGES)" "$(TMPDIR_PATH)" "$(LOG_DIR)" "$(ARCHIVE_DIR)" "$(EXPORT_DIR)"

check-tools:
	@command -v xcodebuild >/dev/null
	@command -v xcrun >/dev/null
	@command -v $(firstword $(XCBEAUTIFY)) >/dev/null || { echo "xcbeautify is required. Install it with: brew install xcbeautify"; exit 1; }
	@test -d "$(DEVELOPER_DIR)" || { echo "Xcode developer directory not found: $(DEVELOPER_DIR)"; exit 1; }

check-simulator: $(SIMULATOR_BIN)
	@if [[ -n "$(EXPLICIT_SIMULATOR_ID)" || -n "$(EXPLICIT_DESTINATION)" || -z "$(SIMULATOR_ID)" ]]; then \
		"$(SIMULATOR_BIN)" ensure \
			--simulator "$(SIMULATOR)" \
			--os "$(SIMULATOR_OS)" \
			--name "$(SIMULATOR_NAME)" \
			--id "$(EXPLICIT_SIMULATOR_ID)" \
			--destination "$(EXPLICIT_DESTINATION)" >/dev/null; \
	fi

ifeq ($(USE_PREBUILT),1)
ensure-prebuilt: $(PREBUILT_DEPS_BIN) check-tools prepare
	@DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" "$(PREBUILT_DEPS_BIN)" ensure \
		--repo-root "$(CURDIR)" \
		--derived-data "$(DERIVED_DATA)" \
		--output-dir "$(PREBUILT_DEPS_DIR)" \
		--source-packages "$(SOURCE_PACKAGES)" \
		--developer-dir "$(XCODE_DEVELOPER_DIR)" \
		$(PREBUILT_WIDGET_FLAG)
else
ensure-prebuilt:
endif

sim-id: $(SIMULATOR_BIN)
	@"$(SIMULATOR_BIN)" ensure \
		--simulator "$(SIMULATOR)" \
		--os "$(SIMULATOR_OS)" \
		--name "$(SIMULATOR_NAME)" \
		--id "$(EXPLICIT_SIMULATOR_ID)" \
		--destination "$(EXPLICIT_DESTINATION)"

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

build: check-tools prepare ensure-prebuilt
	@set -o pipefail; \
	$(XCODEBUILD_ENV) xcodebuild \
		$(XCODEBUILD_FLAGS) $(EXTRA_BUILD_FLAGS) \
		build \
		2>&1 | tee "$(LOG_DIR)/build.log" | $(XCBEAUTIFY)

build-device: check-tools prepare
	@set -o pipefail; \
	$(XCODEBUILD_ENV) xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-destination "$(DEVICE_DESTINATION)" \
		-destination-timeout 60 \
		-derivedDataPath "$(DERIVED_DATA)" \
		-clonedSourcePackagesDirPath "$(SOURCE_PACKAGES)" \
		-disableAutomaticPackageResolution \
		-skipPackageUpdates \
		-allowProvisioningUpdates \
		DEVELOPMENT_TEAM="$(TEAM_ID)" \
		$(DEVICE_BUILD_SETTINGS) \
		$(EXTRA_BUILD_FLAGS) \
		build \
		2>&1 | tee "$(LOG_DIR)/build-device.log" | $(XCBEAUTIFY)

test: check-tools check-simulator prepare
	@$(MAKE) --no-print-directory data-test
	@$(MAKE) --no-print-directory app-test

app-test: check-tools check-simulator prepare ensure-prebuilt
	@set -o pipefail; \
	$(XCODEBUILD_ENV) xcodebuild \
		$(UNIT_TEST_BUILD_FLAGS) $(EXTRA_BUILD_FLAGS) \
		build-for-testing \
		2>&1 | tee "$(LOG_DIR)/test-build.log" | $(XCBEAUTIFY) && \
	$(XCODEBUILD_ENV) xcodebuild \
		$(UNIT_TEST_RUN_FLAGS) $(TEST_SELECTION) \
		test-without-building \
		2>&1 | tee "$(LOG_DIR)/test.log" | $(XCBEAUTIFY); \
	status=$$?; \
	if (( status != 0 )) && [[ -f "$(LOG_DIR)/test.log" ]]; then \
		awk '/recorded an issue/{ issue = 1 } issue { print } issue && /^✘ Test .* failed after/{ issue = 0 }' "$(LOG_DIR)/test.log"; \
	fi; \
	exit $$status

app-test-without-building: check-tools check-simulator prepare
	@set -o pipefail; \
	$(XCODEBUILD_ENV) xcodebuild \
		$(UNIT_TEST_RUN_FLAGS) $(TEST_SELECTION) \
		test-without-building \
		2>&1 | tee "$(LOG_DIR)/test.log" | $(XCBEAUTIFY)

backup-test-build: check-tools prepare ensure-prebuilt
	@set -o pipefail; \
	$(XCODEBUILD_ENV) xcodebuild \
		$(BACKUP_TEST_BUILD_FLAGS) $(EXTRA_BUILD_FLAGS) \
		build-for-testing \
		2>&1 | tee "$(LOG_DIR)/backup-test-build.log" | $(XCBEAUTIFY)

backup-test-without-building: check-tools check-simulator prepare
	@set -o pipefail; \
	$(XCODEBUILD_ENV) xcodebuild \
		$(BACKUP_TEST_RUN_FLAGS) \
		-collect-test-diagnostics never \
		-skip-testing:clinical-swiftBackupTests/BackupDriveTests \
		test-without-building \
		2>&1 | tee "$(LOG_DIR)/backup-test.log" | $(XCBEAUTIFY)

backup-test: check-tools check-simulator prepare ensure-prebuilt
	@set -o pipefail; \
	$(XCODEBUILD_ENV) xcodebuild \
		$(BACKUP_TEST_BUILD_FLAGS) $(EXTRA_BUILD_FLAGS) \
		build-for-testing \
		2>&1 | tee "$(LOG_DIR)/backup-test-build.log" | $(XCBEAUTIFY) && \
	$(XCODEBUILD_ENV) xcodebuild \
		$(BACKUP_TEST_RUN_FLAGS) \
		-collect-test-diagnostics never \
		-skip-testing:clinical-swiftBackupTests/BackupDriveTests \
		test-without-building \
		2>&1 | tee "$(LOG_DIR)/backup-test.log" | $(XCBEAUTIFY)

backup-drive-check: check-tools check-simulator prepare ensure-prebuilt
	@test -r "$(CLINICAL_BACKUP_CHECK_CREDENTIALS)" || { echo "Missing Drive check credentials. Run make backup-authorize, sign in, then make backup-export-credentials."; exit 1; }
	@set -o pipefail; \
	$(XCODEBUILD_ENV) xcodebuild \
		$(BACKUP_TEST_BUILD_FLAGS) $(EXTRA_BUILD_FLAGS) \
		build-for-testing \
		2>&1 | tee "$(LOG_DIR)/backup-drive-check-build.log" | $(XCBEAUTIFY) && \
	$(XCODEBUILD_ENV) xcodebuild \
		$(BACKUP_TEST_RUN_FLAGS) \
		CLINICAL_BACKUP_CHECK_CREDENTIALS="$(CLINICAL_BACKUP_CHECK_CREDENTIALS)" \
		-only-testing:clinical-swiftBackupTests/BackupDriveTests \
		test-without-building \
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

ui-test: check-tools check-simulator prepare ensure-prebuilt
	@set -o pipefail; \
	$(XCODEBUILD_ENV) xcodebuild \
		$(UI_TEST_BUILD_FLAGS) $(EXTRA_BUILD_FLAGS) \
		build-for-testing \
		2>&1 | tee "$(LOG_DIR)/ui-test-build.log" | $(XCBEAUTIFY) && \
	$(XCODEBUILD_ENV) xcodebuild \
		$(UI_TEST_RUN_FLAGS) $(TEST_SELECTION) \
		test-without-building \
		2>&1 | tee "$(LOG_DIR)/ui-test.log" | $(XCBEAUTIFY)

ui-test-without-building: check-tools check-simulator prepare
	@set -o pipefail; \
	$(XCODEBUILD_ENV) xcodebuild \
		$(UI_TEST_RUN_FLAGS) $(TEST_SELECTION) \
		test-without-building \
		2>&1 | tee "$(LOG_DIR)/ui-test.log" | $(XCBEAUTIFY)

build-for-testing: check-tools prepare ensure-prebuilt
	@set -o pipefail; \
	$(XCODEBUILD_ENV) xcodebuild \
		$(COMBINED_TEST_BUILD_FLAGS) $(EXTRA_BUILD_FLAGS) \
		build-for-testing \
		2>&1 | tee "$(LOG_DIR)/build-for-testing.log" | $(XCBEAUTIFY)

# Simulate the exact ios-tests-local CI pipeline on a local simulator.
ci-local-sim: check-tools check-simulator prepare ensure-prebuilt
	@set -o pipefail; \
	$(XCODEBUILD_ENV) xcodebuild \
		$(COMBINED_TEST_BUILD_FLAGS) $(EXTRA_BUILD_FLAGS) \
		build-for-testing \
		2>&1 | tee "$(LOG_DIR)/ci-debug-build.log" | $(XCBEAUTIFY) || exit $$?; \
	$(MAKE) --no-print-directory backup-test-build \
		CONFIGURATION=Release \
		SOURCE_PACKAGES="$(SOURCE_PACKAGES)" \
		XCODE_DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" \
		> "$(LOG_DIR)/ci-release-backup-build.log" 2>&1 & \
	backup_build_pid=$$!; \
	unit_status=0; \
	$(XCODEBUILD_ENV) xcodebuild \
		$(COMBINED_TEST_RUN_FLAGS) \
		-parallel-testing-enabled NO \
		-collect-test-diagnostics never \
		-only-testing:clinical-swiftTests \
		test-without-building \
		2>&1 | tee "$(LOG_DIR)/ci-debug-unit-test.log" | $(XCBEAUTIFY) || unit_status=$$?; \
	backup_build_status=0; \
	wait "$$backup_build_pid" || backup_build_status=$$?; \
	if (( unit_status != 0 )); then exit "$$unit_status"; fi; \
	if (( backup_build_status != 0 )); then cat "$(LOG_DIR)/ci-release-backup-build.log"; exit "$$backup_build_status"; fi; \
	$(MAKE) --no-print-directory backup-test-without-building \
		CONFIGURATION=Release \
		SIMULATOR_ID="$(SIMULATOR_ID)" \
		SIMULATOR_NAME= \
		SOURCE_PACKAGES="$(SOURCE_PACKAGES)" \
		XCODE_DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" || exit $$?; \
	$(XCODEBUILD_ENV) $(if $(filter 1,$(CI_LOCAL_WIDGET_PERF)),TEST_RUNNER_CLINICAL_WIDGET_PERF_TEST=1) xcodebuild \
		$(COMBINED_TEST_RUN_FLAGS) \
		$(UI_TEST_PARALLEL_FLAGS) \
		-collect-test-diagnostics on-failure \
		-test-timeouts-enabled YES \
		-default-test-execution-time-allowance 120 \
		$(if $(strip $(ONLY_TESTING)),$(TEST_SELECTION),-only-testing:clinical-swiftUITests) \
		test-without-building \
		2>&1 | tee "$(LOG_DIR)/ci-debug-ui-test.log" | $(XCBEAUTIFY)

WIDGET_PERF_MAX_LATENCY_MS ?= 350
WIDGET_PERF_MAX_TOTAL_MS ?= 1200
widget-perf-test: check-device check-tools prepare
	@set -o pipefail; \
	device_id="$$($(SWIFT) "$(DEVICE_SCRIPT)" resolve "$(DEVICE)")" || exit; \
	$(XCODEBUILD_ENV) xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(UI_TEST_SCHEME)" \
		-configuration Release \
		-destination "platform=iOS,id=$$device_id" \
		-destination-timeout 60 \
		-derivedDataPath "$(BUILD_DIR)/DerivedData-Release" \
		-clonedSourcePackagesDirPath "$(SOURCE_PACKAGES)" \
		-disableAutomaticPackageResolution \
		-skipPackageUpdates \
		-allowProvisioningUpdates \
		DEVELOPMENT_TEAM="$(TEAM_ID)" \
		COMPILER_INDEX_STORE_ENABLE=NO \
		CLANG_ENABLE_CODE_COVERAGE=NO \
		CLANG_COVERAGE_MAPPING=NO \
		build-for-testing \
		2>&1 | tee "$(LOG_DIR)/widget-perf-build.log" | $(XCBEAUTIFY) && \
	xcrun devicectl device install app --device "$$device_id" \
		"$(BUILD_DIR)/DerivedData-Release/Build/Products/Release-iphoneos/$(SCHEME).app" && \
	$(XCODEBUILD_ENV) \
		TEST_RUNNER_CLINICAL_WIDGET_PERF_TEST=1 \
		TEST_RUNNER_CLINICAL_WIDGET_MAX_LATENCY_MS="$(WIDGET_PERF_MAX_LATENCY_MS)" \
		TEST_RUNNER_CLINICAL_WIDGET_MAX_TOTAL_MS="$(WIDGET_PERF_MAX_TOTAL_MS)" \
		xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(UI_TEST_SCHEME)" \
		-configuration Release \
		-destination "platform=iOS,id=$$device_id" \
		-destination-timeout 60 \
		-derivedDataPath "$(BUILD_DIR)/DerivedData-Release" \
		-parallel-testing-enabled NO \
		-collect-test-diagnostics never \
		-only-testing:clinical-swiftUITests/DailyTimelineWidgetPerformanceUITests \
		test-without-building \
		2>&1 | tee "$(LOG_DIR)/widget-perf-test.log" | $(XCBEAUTIFY); \
	status=$$?; \
	grep -E "WIDGET_PERF" "$(LOG_DIR)/widget-perf-test.log" || true; \
	exit $$status

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
		COMPILER_INDEX_STORE_ENABLE=NO \
		CLANG_ENABLE_CODE_COVERAGE=NO \
		CLANG_COVERAGE_MAPPING=NO \
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

check-device:
	@test -n "$(DEVICE)" || { echo "DEVICE is required. Example: make install-device DEVICE='Corp iPhone'"; exit 2; }

install-device: check-device build-device
	@test -d "$(DEVICE_APP_PATH)" || { echo "Missing built app at $(DEVICE_APP_PATH)"; exit 1; }
	@xcrun devicectl device install app --device "$(DEVICE)" "$(DEVICE_APP_PATH)"

validate-appearance:
	@if [[ -n "$(APPEARANCE)" ]]; then \
		case "$(APPEARANCE)" in \
			light|dark) ;; \
			*) echo "APPEARANCE must be light or dark, got: $(APPEARANCE)" >&2; exit 2 ;; \
		esac; \
	fi

require-appearance:
	@case "$(APPEARANCE)" in \
		light|dark) ;; \
		*) echo "APPEARANCE=light or APPEARANCE=dark is required." >&2; exit 2 ;; \
	esac

appearance: require-appearance check-tools check-simulator boot
	@xcrun simctl ui "$(SIMULATOR_ID)" appearance "$(APPEARANCE)"

run: validate-appearance check-tools check-simulator boot
	@if [[ -n "$(APPEARANCE)" ]]; then xcrun simctl ui "$(SIMULATOR_ID)" appearance "$(APPEARANCE)"; fi
	@xcrun simctl launch --terminate-running-process "$(SIMULATOR_ID)" "$(BUNDLE_ID)" $(LAUNCH_ARGS)

build-and-run: validate-appearance install run

screenshot: run
	@if [[ -n "$(SCREENSHOT_DELAY)" && "$(SCREENSHOT_DELAY)" != "0" ]]; then sleep "$(SCREENSHOT_DELAY)"; fi
	@mkdir -p "$$(dirname "$(OUT)")"
	@xcrun simctl io "$(SIMULATOR_ID)" screenshot "$(OUT)"
	@printf "Saved screenshot: %s\n" "$(OUT)"

snap: check-tools check-simulator boot
	@mkdir -p "$$(dirname "$(OUT)")"
	@xcrun simctl io "$(SIMULATOR_ID)" screenshot "$(OUT)"
	@printf "Saved screenshot: %s\n" "$(OUT)"

uninstall: check-tools check-simulator boot
	@xcrun simctl uninstall "$(SIMULATOR_ID)" "$(BUNDLE_ID)" || true

clean:
	@rm -rf "$(BUILD_DIR)"

MONITOR_PORT ?= 4873
agent-monitor:
	@$(SWIFT) scripts/agent_monitor.swift --port "$(MONITOR_PORT)" --open
