SHELL := /bin/bash

PROJECT := clinical-swift.xcodeproj
SCHEME := clinical-swift
UNIT_TEST_SCHEME := clinical-swift-UnitTests
UI_TEST_SCHEME := clinical-swift-UITests
CONFIGURATION ?= Debug
SIMULATOR ?= iPhone 17
BUNDLE_ID := in.bitehaus.clinical
APP_NAME := Clinical
TEAM_ID := WM7GP7FBL7
ASC_KEY_ID := 643N8M76NP
ASC_ISSUER_ID := 2b91f873-699b-498f-b1b6-5043a8d5f2ac
ASC_PRIVATE_KEYS_DIR ?= $(HOME)/.appstoreconnect/private_keys

BUILD_DIR := $(CURDIR)/build
DERIVED_DATA := $(BUILD_DIR)/DerivedData
SOURCE_PACKAGES := $(BUILD_DIR)/SourcePackages
MODULE_CACHE := $(BUILD_DIR)/cache/modules
TMPDIR_PATH := $(BUILD_DIR)/tmp
LOG_DIR := $(BUILD_DIR)/logs
APP_PATH := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphonesimulator/$(SCHEME).app
ARCHIVE_DIR := $(BUILD_DIR)/Archives
EXPORT_DIR := $(BUILD_DIR)/Exports
RELEASE_ASSETS_DIR := $(BUILD_DIR)/ReleaseAssets
LATEST_ARCHIVE_FILE := $(ARCHIVE_DIR)/.latest-archive
ARCHIVE_PATH := $(ARCHIVE_DIR)/$(APP_NAME)-$(BUILD_NUMBER).xcarchive
EXPORT_PATH := $(EXPORT_DIR)/$(APP_NAME)-$(BUILD_NUMBER)
TESTFLIGHT_EXPORT_OPTIONS := $(CURDIR)/TestFlightExportOptions.plist
BACKUP_ARCHIVE_SCRIPT := $(CURDIR)/scripts/backup_archive_to_github.sh
NEXT_BUILD_NUMBER_SCRIPT := $(CURDIR)/scripts/next_app_store_build_number.swift

DESTINATION := platform=iOS Simulator,name=$(SIMULATOR),OS=latest
ARCHIVE_DESTINATION := generic/platform=iOS
XCBEAUTIFY := xcbeautify -qq --disable-logging
XCODEBUILD_ENV := env CLANG_MODULE_CACHE_PATH="$(MODULE_CACHE)" SWIFT_MODULE_CACHE_PATH="$(MODULE_CACHE)" TMPDIR="$(TMPDIR_PATH)/"
RESOLVE_BUILD_NUMBER := env API_PRIVATE_KEYS_DIR="$(ASC_PRIVATE_KEYS_DIR)" xcrun swift "$(NEXT_BUILD_NUMBER_SCRIPT)" "$(BUNDLE_ID)" "$(ASC_KEY_ID)" "$(ASC_ISSUER_ID)"
XCODEBUILD_COMMON_FLAGS := -project "$(PROJECT)" \
	-configuration "$(CONFIGURATION)" \
	-destination "$(DESTINATION)" \
	-destination-timeout 60 \
	-derivedDataPath "$(DERIVED_DATA)" \
	-clonedSourcePackagesDirPath "$(SOURCE_PACKAGES)" \
	-disableAutomaticPackageResolution \
    -skipPackageUpdates \
	CODE_SIGNING_ALLOWED=NO
XCODEBUILD_FLAGS := $(XCODEBUILD_COMMON_FLAGS) -scheme "$(SCHEME)"
UNIT_TEST_FLAGS := $(XCODEBUILD_COMMON_FLAGS) -scheme "$(UNIT_TEST_SCHEME)" -parallel-testing-enabled NO
UI_TEST_FLAGS := $(XCODEBUILD_COMMON_FLAGS) -scheme "$(UI_TEST_SCHEME)"

.DEFAULT_GOAL := build-and-run

.PHONY: help diagnose prepare check-tools check-github-tools check-build-number next-build-number resolve-packages build test ui-test release-testflight archive archive-with-build-number upload-testflight upload-testflight-with-build-number backup-archive backup-archive-with-build-number remove-archive remove-archive-with-build-number boot install run build-and-run uninstall clean

help:
	@printf "%s\n" \
		"Targets:" \
		"  make                  Build, install, and run on $(SIMULATOR)" \
		"  make build            Build the app" \
		"  make test             Run unit tests" \
		"  make ui-test          Run UI tests" \
		"" \
		"TestFlight workflow:" \
		"  make release-testflight  Archive, upload, back up, and remove locally" \
		"" \
		"Individual TestFlight steps:" \
		"  make next-build-number  Show the next App Store Connect build number" \
		"  make archive            Create a signed App Store archive" \
		"  make upload-testflight  Upload the latest existing archive only" \
		"  make backup-archive     Back up the latest archive; preserve it locally" \
		"  make remove-archive     Remove the latest local archive" \
		"  BUILD_NUMBER=N          Override automatic build-number selection" \
		"" \
		"Simulator and maintenance:" \
		"  make install          Build and install on $(SIMULATOR)" \
		"  make run              Launch the installed app" \
		"  make resolve-packages Resolve Swift package dependencies" \
		"  make diagnose         Print tool and project settings" \
		"  make uninstall        Remove the app from the booted simulator" \
		"  make clean            Remove local build outputs"

diagnose:
	@printf "Project:       %s\n" "$(PROJECT)"
	@printf "Scheme:        %s\n" "$(SCHEME)"
	@printf "Unit tests:    %s\n" "$(UNIT_TEST_SCHEME)"
	@printf "UI tests:      %s\n" "$(UI_TEST_SCHEME)"
	@printf "Configuration: %s\n" "$(CONFIGURATION)"
	@printf "Simulator:     %s\n" "$(SIMULATOR)"
	@printf "Destination:   %s\n" "$(DESTINATION)"
	@printf "App path:      %s\n" "$(APP_PATH)"
	@printf "Bundle ID:     %s\n" "$(BUNDLE_ID)"
	@printf "ASC key ID:    %s\n" "$(ASC_KEY_ID)"
	@printf "ASC issuer ID: %s\n" "$(ASC_ISSUER_ID)"
	@printf "xcodebuild:    %s\n" "$$(xcrun --find xcodebuild)"
	@printf "xcbeautify:    %s\n" "$$(command -v $(XCBEAUTIFY))"

prepare:
	@mkdir -p "$(DERIVED_DATA)" "$(SOURCE_PACKAGES)" "$(MODULE_CACHE)" "$(TMPDIR_PATH)" "$(LOG_DIR)" "$(ARCHIVE_DIR)" "$(EXPORT_DIR)" "$(RELEASE_ASSETS_DIR)"

check-tools:
	@command -v xcodebuild >/dev/null
	@command -v xcrun >/dev/null
	@command -v $(XCBEAUTIFY) >/dev/null || { echo "xcbeautify is required. Install it with: brew install xcbeautify"; exit 1; }

check-github-tools:
	@command -v gh >/dev/null || { echo "GitHub CLI is required. Install it with: brew install gh"; exit 1; }
	@command -v ditto >/dev/null
	@command -v shasum >/dev/null
	@test -x "$(BACKUP_ARCHIVE_SCRIPT)" || { echo "Archive backup script is missing or not executable: $(BACKUP_ARCHIVE_SCRIPT)"; exit 1; }
	@gh auth status >/dev/null

check-build-number:
	@test -n "$(BUILD_NUMBER)" || { echo "BUILD_NUMBER is required. Example: make upload-testflight BUILD_NUMBER=2"; exit 2; }
	@[[ "$(BUILD_NUMBER)" =~ ^[0-9]+(\.[0-9]+){0,2}$$ ]] || { echo "BUILD_NUMBER must contain one to three numeric components, for example 2 or 2.1"; exit 2; }

next-build-number: check-tools
	@number="$$($(RESOLVE_BUILD_NUMBER))" || exit; \
	printf "Next App Store Connect build number: %s\n" "$$number"

resolve-packages: check-tools prepare
	@set -o pipefail; \
	$(XCODEBUILD_ENV) xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-clonedSourcePackagesDirPath "$(SOURCE_PACKAGES)" \
		-resolvePackageDependencies \
		2>&1 | tee "$(LOG_DIR)/resolve-packages.log" | $(XCBEAUTIFY)

build: check-tools prepare
	@set -o pipefail; \
	$(XCODEBUILD_ENV) xcodebuild \
		$(XCODEBUILD_FLAGS) \
		build \
		2>&1 | tee "$(LOG_DIR)/build.log" | $(XCBEAUTIFY)

test: check-tools prepare
	@set -o pipefail; \
	$(XCODEBUILD_ENV) xcodebuild \
		$(UNIT_TEST_FLAGS) \
		test \
		2>&1 | tee "$(LOG_DIR)/test.log" | $(XCBEAUTIFY); \
	status=$$?; \
	if (( status != 0 )); then \
		awk '/recorded an issue/{ issue = 1 } issue { print } issue && /^✘ Test .* failed after/{ issue = 0 }' "$(LOG_DIR)/test.log"; \
	fi; \
	exit $$status

ui-test: check-tools prepare
	@set -o pipefail; \
	$(XCODEBUILD_ENV) xcodebuild \
		$(UI_TEST_FLAGS) \
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
	@printf '%s\n' "$(BUILD_NUMBER)" > "$(LATEST_ARCHIVE_FILE).tmp"
	@mv "$(LATEST_ARCHIVE_FILE).tmp" "$(LATEST_ARCHIVE_FILE)"

backup-archive: check-github-tools prepare
	@number="$(BUILD_NUMBER)"; \
	if [[ -z "$$number" ]]; then \
		test -f "$(LATEST_ARCHIVE_FILE)" || { echo "No latest archive is recorded. Run make archive first or pass BUILD_NUMBER=N."; exit 1; }; \
		number="$$(< "$(LATEST_ARCHIVE_FILE)")"; \
	fi; \
	$(MAKE) --no-print-directory backup-archive-with-build-number BUILD_NUMBER="$$number"

backup-archive-with-build-number: check-github-tools check-build-number prepare
	@test -d "$(ARCHIVE_PATH)" || { echo "Missing archive at $(ARCHIVE_PATH)"; exit 1; }
	@archive_build="$$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$(ARCHIVE_PATH)/Info.plist")"; \
	[[ "$$archive_build" == "$(BUILD_NUMBER)" ]] || { echo "Archive contains build $$archive_build, expected $(BUILD_NUMBER)"; exit 1; }
	@"$(BACKUP_ARCHIVE_SCRIPT)" "$(ARCHIVE_PATH)" "$(RELEASE_ASSETS_DIR)"

upload-testflight: check-tools prepare
	@number="$(BUILD_NUMBER)"; \
	if [[ -z "$$number" ]]; then \
		test -f "$(LATEST_ARCHIVE_FILE)" || { echo "No latest archive is recorded. Run make archive first or use make release-testflight."; exit 1; }; \
		number="$$(< "$(LATEST_ARCHIVE_FILE)")"; \
	fi; \
	$(MAKE) --no-print-directory upload-testflight-with-build-number BUILD_NUMBER="$$number"

upload-testflight-with-build-number: check-tools check-build-number prepare
	@test -d "$(ARCHIVE_PATH)" || { echo "Missing archive at $(ARCHIVE_PATH)"; exit 1; }
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

release-testflight: check-tools check-github-tools prepare
	@number="$(BUILD_NUMBER)"; \
	if [[ -z "$$number" ]]; then number="$$($(RESOLVE_BUILD_NUMBER))" || exit; fi; \
	$(MAKE) --no-print-directory archive-with-build-number BUILD_NUMBER="$$number" && \
	$(MAKE) --no-print-directory upload-testflight-with-build-number BUILD_NUMBER="$$number" && \
	$(MAKE) --no-print-directory backup-archive-with-build-number BUILD_NUMBER="$$number" && \
	$(MAKE) --no-print-directory remove-archive-with-build-number BUILD_NUMBER="$$number"

boot: check-tools
	@xcrun simctl boot "$(SIMULATOR)" >/dev/null 2>&1 || true
	@xcrun simctl bootstatus "$(SIMULATOR)" -b
	@open -a Simulator

install: build boot
	@test -d "$(APP_PATH)" || { echo "Missing built app at $(APP_PATH)"; exit 1; }
	@xcrun simctl install booted "$(APP_PATH)"

run: check-tools boot
	@xcrun simctl launch booted "$(BUNDLE_ID)"

build-and-run: install run

uninstall: check-tools boot
	@xcrun simctl uninstall booted "$(BUNDLE_ID)" || true

clean:
	@rm -rf "$(BUILD_DIR)"
