SHELL := /bin/bash

PROJECT := clinical-swift.xcodeproj
SCHEME := clinical-swift
UNIT_TEST_TARGET := clinical-swiftTests
UI_TEST_TARGET := clinical-swiftUITests
CONFIGURATION ?= Debug
SIMULATOR ?= iPhone 17
BUNDLE_ID := in.bitehaus.clinical
APP_NAME := Clinical
TEAM_ID := WM7GP7FBL7

BUILD_DIR := $(CURDIR)/build
DERIVED_DATA := $(BUILD_DIR)/DerivedData
SOURCE_PACKAGES := $(BUILD_DIR)/SourcePackages
MODULE_CACHE := $(BUILD_DIR)/cache/modules
TMPDIR_PATH := $(BUILD_DIR)/tmp
LOG_DIR := $(BUILD_DIR)/logs
APP_PATH := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphonesimulator/$(SCHEME).app
ARCHIVE_DIR := $(BUILD_DIR)/Archives
EXPORT_DIR := $(BUILD_DIR)/Exports
ARCHIVE_PATH := $(ARCHIVE_DIR)/$(APP_NAME)-$(BUILD_NUMBER).xcarchive
EXPORT_PATH := $(EXPORT_DIR)/$(APP_NAME)-$(BUILD_NUMBER)
TESTFLIGHT_EXPORT_OPTIONS := $(CURDIR)/TestFlightExportOptions.plist

DESTINATION := platform=iOS Simulator,name=$(SIMULATOR),OS=latest
ARCHIVE_DESTINATION := generic/platform=iOS
XCBEAUTIFY := xcbeautify
XCODEBUILD_ENV := env CLANG_MODULE_CACHE_PATH="$(MODULE_CACHE)" SWIFT_MODULE_CACHE_PATH="$(MODULE_CACHE)" TMPDIR="$(TMPDIR_PATH)/"
XCODEBUILD_FLAGS := -project "$(PROJECT)" \
	-scheme "$(SCHEME)" \
	-configuration "$(CONFIGURATION)" \
	-destination "$(DESTINATION)" \
	-destination-timeout 60 \
	-derivedDataPath "$(DERIVED_DATA)" \
	-clonedSourcePackagesDirPath "$(SOURCE_PACKAGES)" \
	CODE_SIGNING_ALLOWED=NO

.DEFAULT_GOAL := build-and-run

.PHONY: help diagnose prepare check-tools check-build-number resolve-packages build test ui-test archive upload-testflight boot install run build-and-run uninstall clean

help:
	@printf "%s\n" \
		"Targets:" \
		"  make                  Build, install, and run on $(SIMULATOR)" \
		"  make build            Build the app" \
		"  make test             Run unit tests" \
		"  make ui-test          Run UI tests" \
		"  make archive BUILD_NUMBER=N" \
		"                        Create a signed App Store archive" \
		"  make upload-testflight BUILD_NUMBER=N" \
		"                        Archive and upload to App Store Connect" \
		"  make install          Build and install on $(SIMULATOR)" \
		"  make run              Launch the installed app" \
		"  make resolve-packages Resolve Swift package dependencies" \
		"  make diagnose         Print tool and project settings" \
		"  make uninstall        Remove the app from the booted simulator" \
		"  make clean            Remove local build outputs"

diagnose:
	@printf "Project:       %s\n" "$(PROJECT)"
	@printf "Scheme:        %s\n" "$(SCHEME)"
	@printf "Configuration: %s\n" "$(CONFIGURATION)"
	@printf "Simulator:     %s\n" "$(SIMULATOR)"
	@printf "Destination:   %s\n" "$(DESTINATION)"
	@printf "App path:      %s\n" "$(APP_PATH)"
	@printf "Bundle ID:     %s\n" "$(BUNDLE_ID)"
	@printf "xcodebuild:    %s\n" "$$(xcrun --find xcodebuild)"
	@printf "xcbeautify:    %s\n" "$$(command -v $(XCBEAUTIFY))"

prepare:
	@mkdir -p "$(DERIVED_DATA)" "$(SOURCE_PACKAGES)" "$(MODULE_CACHE)" "$(TMPDIR_PATH)" "$(LOG_DIR)" "$(ARCHIVE_DIR)" "$(EXPORT_DIR)"

check-tools:
	@command -v xcodebuild >/dev/null
	@command -v xcrun >/dev/null
	@command -v $(XCBEAUTIFY) >/dev/null || { echo "xcbeautify is required. Install it with: brew install xcbeautify"; exit 1; }

check-build-number:
	@test -n "$(BUILD_NUMBER)" || { echo "BUILD_NUMBER is required. Example: make upload-testflight BUILD_NUMBER=2"; exit 2; }
	@[[ "$(BUILD_NUMBER)" =~ ^[0-9]+(\.[0-9]+){0,2}$$ ]] || { echo "BUILD_NUMBER must contain one to three numeric components, for example 2 or 2.1"; exit 2; }

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
		$(XCODEBUILD_FLAGS) \
		test -only-testing:$(UNIT_TEST_TARGET) \
		2>&1 | tee "$(LOG_DIR)/test.log" | $(XCBEAUTIFY)

ui-test: check-tools prepare
	@set -o pipefail; \
	$(XCODEBUILD_ENV) xcodebuild \
		$(XCODEBUILD_FLAGS) \
		test -only-testing:$(UI_TEST_TARGET) \
		2>&1 | tee "$(LOG_DIR)/ui-test.log" | $(XCBEAUTIFY)

archive: check-tools check-build-number prepare
	@available="$$(df -h "$(ARCHIVE_DIR)" | awk 'NR == 2 { print $$4 }')"; \
	archive_count="$$(find "$(ARCHIVE_DIR)" -maxdepth 1 -type d -name '*.xcarchive' | wc -l | tr -d '[:space:]')"; \
	printf "Archive storage: %s\nAvailable disk:  %s\nOld archives:    %s\n" "$(ARCHIVE_DIR)" "$$available" "$$archive_count"
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

upload-testflight: archive
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
