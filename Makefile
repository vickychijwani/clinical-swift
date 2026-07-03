SHELL := /bin/bash

PROJECT := clinical-swift.xcodeproj
SCHEME := clinical-swift
UNIT_TEST_TARGET := clinical-swiftTests
UI_TEST_TARGET := clinical-swiftUITests
CONFIGURATION ?= Debug
SIMULATOR ?= iPhone 17
BUNDLE_ID := in.bitehaus.clinical-swift

BUILD_DIR := $(CURDIR)/build
DERIVED_DATA := $(BUILD_DIR)/DerivedData
SOURCE_PACKAGES := $(BUILD_DIR)/SourcePackages
MODULE_CACHE := $(BUILD_DIR)/cache/modules
TMPDIR_PATH := $(BUILD_DIR)/tmp
LOG_DIR := $(BUILD_DIR)/logs
APP_PATH := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphonesimulator/$(SCHEME).app

DESTINATION := platform=iOS Simulator,name=$(SIMULATOR),OS=latest
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

.PHONY: help diagnose prepare check-tools resolve-packages build test ui-test boot install run build-and-run uninstall clean

help:
	@printf "%s\n" \
		"Targets:" \
		"  make                  Build, install, and run on $(SIMULATOR)" \
		"  make build            Build the app" \
		"  make test             Run unit tests" \
		"  make ui-test          Run UI tests" \
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
	@mkdir -p "$(DERIVED_DATA)" "$(SOURCE_PACKAGES)" "$(MODULE_CACHE)" "$(TMPDIR_PATH)" "$(LOG_DIR)"

check-tools:
	@command -v xcodebuild >/dev/null
	@command -v xcrun >/dev/null
	@command -v $(XCBEAUTIFY) >/dev/null || { echo "xcbeautify is required. Install it with: brew install xcbeautify"; exit 1; }

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
