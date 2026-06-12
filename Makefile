SHELL := /bin/bash

.DEFAULT_GOAL := help

PROJECT ?= TextReader.xcodeproj
SCHEME ?= TextReader
CONFIGURATION ?= Debug
DERIVED_DATA_PATH ?= .build/DerivedData
APP_NAME ?= $(SCHEME)
APP_PATH ?= $(DERIVED_DATA_PATH)/Build/Products/$(CONFIGURATION)-iphoneos/$(APP_NAME).app
SIMULATOR_APP_PATH ?= $(DERIVED_DATA_PATH)/Build/Products/$(CONFIGURATION)-iphonesimulator/$(APP_NAME).app
DEVICE_FILTER ?= connectionProperties.pairingState == 'paired'
TEST_DESTINATION ?= platform=iOS Simulator,name=iPhone 17
XCODEBUILD_FLAGS ?= -allowProvisioningUpdates -allowProvisioningDeviceRegistration

.PHONY: help all build build-device build-for-testing install install-device install-simulator run-simulator test check list-devices list-simulators devices simulators clean

help: ## Show all available commands
	@printf "Targets:\n"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'
	@printf "\n"
	@printf "Overrides:\n"
	@printf "  DEVICE_NAME='My iPhone'         Build/install to a specific device name\n"
	@printf "  SIMULATOR_NAME='iPhone 17'      Install to a specific simulator name\n"
	@printf "  SIMULATOR_UDID='<UDID>'         Install to a specific simulator UDID\n"
	@printf "  TEST_DESTINATION='platform=...' Use a different xcodebuild test destination\n"
	@printf "  CONFIGURATION=Release           Use a different build configuration\n"

all: build ## Build the app for the first connected real device

list-devices: ## List connected iOS devices detected by devicectl
	@xcrun devicectl list devices --filter "$(DEVICE_FILTER)"

list-simulators: ## List available iOS simulators detected by simctl
	@xcrun simctl list devices available

devices: list-devices ## Alias for list-devices

simulators: list-simulators ## Alias for list-simulators

build: build-device ## Build the app for the first connected real device

build-device: ## Build the app for the first connected real device
	@set -euo pipefail; \
	device_name="$(DEVICE_NAME)"; \
	if [[ -z "$$device_name" ]]; then \
		device_name="$$(xcrun devicectl list devices --filter "$(DEVICE_FILTER)" --hide-default-columns --hide-headers --columns Name | sed 's/[[:space:]]*$$//' | awk 'NF && $$0 != "No devices found." { print; exit }')"; \
	fi; \
	if [[ -z "$$device_name" ]]; then \
		echo "No paired iOS device found. Run 'make list-devices' or pass DEVICE_NAME='...'" >&2; \
		exit 1; \
	fi; \
	echo "Building $(SCHEME) for $$device_name..."; \
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-destination "platform=iOS,name=$$device_name" \
		-derivedDataPath "$(DERIVED_DATA_PATH)" \
		$(XCODEBUILD_FLAGS) \
		build

install: install-device ## Build, install, and launch on the first connected real device

install-device: ## Build, install, and launch on the first connected real device
	@set -euo pipefail; \
	device_name="$(DEVICE_NAME)"; \
	if [[ -z "$$device_name" ]]; then \
		device_name="$$(xcrun devicectl list devices --filter "$(DEVICE_FILTER)" --hide-default-columns --hide-headers --columns Name | sed 's/[[:space:]]*$$//' | awk 'NF && $$0 != "No devices found." { print; exit }')"; \
	fi; \
	if [[ -z "$$device_name" ]]; then \
		echo "No paired iOS device found. Run 'make list-devices' or pass DEVICE_NAME='...'" >&2; \
		exit 1; \
	fi; \
	echo "Building $(SCHEME) for $$device_name..."; \
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-destination "platform=iOS,name=$$device_name" \
		-derivedDataPath "$(DERIVED_DATA_PATH)" \
		$(XCODEBUILD_FLAGS) \
		build; \
	if [[ ! -d "$(APP_PATH)" ]]; then \
		echo "Built app not found at $(APP_PATH)" >&2; \
		exit 1; \
	fi; \
	bundle_id="$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$(APP_PATH)/Info.plist" 2>/dev/null || true)"; \
	if [[ -z "$$bundle_id" ]]; then \
		echo "Unable to read CFBundleIdentifier from $(APP_PATH)/Info.plist" >&2; \
		exit 1; \
	fi; \
	echo "Installing $(APP_PATH) to $$device_name..."; \
	xcrun devicectl device install app --device "$$device_name" "$(APP_PATH)"; \
	echo "Launching $$bundle_id on $$device_name..."; \
	xcrun devicectl device process launch --device "$$device_name" --terminate-existing "$$bundle_id"

install-simulator: run-simulator ## Alias for run-simulator

run-simulator: ## Build, install, and launch on an iOS simulator
	@set -euo pipefail; \
	simulator_name="$(SIMULATOR_NAME)"; \
	simulator_udid="$(SIMULATOR_UDID)"; \
	if [[ -z "$$simulator_udid" && -n "$$simulator_name" ]]; then \
		simulator_udid="$$(xcrun simctl list devices available | sed -nE 's/^[[:space:]]*(.*) \(([0-9A-F-]+)\) \(([^)]+)\)[[:space:]]*$$/\1|\2|\3/p' | awk -F '|' -v target="$$simulator_name" '$$1 == target { print $$2; exit }')"; \
	fi; \
	if [[ -z "$$simulator_udid" ]]; then \
		simulator_udid="$$(xcrun simctl list devices | sed -nE 's/^[[:space:]]*(.*) \(([0-9A-F-]+)\) \(([^)]+)\)[[:space:]]*$$/\1|\2|\3/p' | awk -F '|' '$$3 == "Booted" { print $$2; exit }')"; \
	fi; \
	if [[ -z "$$simulator_udid" ]]; then \
		simulator_udid="$$(xcrun simctl list devices available | sed -nE 's/^[[:space:]]*(.*) \(([0-9A-F-]+)\) \(([^)]+)\)[[:space:]]*$$/\1|\2|\3/p' | awk -F '|' '$$1 ~ /^iPhone / { print $$2; exit }')"; \
	fi; \
	if [[ -z "$$simulator_udid" ]]; then \
		simulator_udid="$$(xcrun simctl list devices available | sed -nE 's/^[[:space:]]*(.*) \(([0-9A-F-]+)\) \(([^)]+)\)[[:space:]]*$$/\1|\2|\3/p' | awk -F '|' 'NF >= 2 { print $$2; exit }')"; \
	fi; \
	if [[ -z "$$simulator_udid" ]]; then \
		echo "No available iOS simulator found. Run 'make list-simulators' or pass SIMULATOR_NAME='...' / SIMULATOR_UDID='...'" >&2; \
		exit 1; \
	fi; \
	resolved_name="$$(xcrun simctl list devices | sed -nE 's/^[[:space:]]*(.*) \(([0-9A-F-]+)\) \(([^)]+)\)[[:space:]]*$$/\1|\2|\3/p' | awk -F '|' -v target="$$simulator_udid" '$$2 == target { print $$1; exit }')"; \
	simulator_state="$$(xcrun simctl list devices | sed -nE 's/^[[:space:]]*(.*) \(([0-9A-F-]+)\) \(([^)]+)\)[[:space:]]*$$/\1|\2|\3/p' | awk -F '|' -v target="$$simulator_udid" '$$2 == target { print $$3; exit }')"; \
	if [[ -z "$$resolved_name" ]]; then \
		echo "Unable to resolve simulator metadata for $$simulator_udid" >&2; \
		exit 1; \
	fi; \
	open -a Simulator --args -CurrentDeviceUDID "$$simulator_udid" >/dev/null 2>&1 || true; \
	if [[ "$$simulator_state" != "Booted" ]]; then \
		echo "Booting $$resolved_name..."; \
		xcrun simctl boot "$$simulator_udid"; \
	fi; \
	for _ in {1..60}; do \
		simulator_state="$$(xcrun simctl list devices | sed -nE 's/^[[:space:]]*(.*) \(([0-9A-F-]+)\) \(([^)]+)\)[[:space:]]*$$/\1|\2|\3/p' | awk -F '|' -v target="$$simulator_udid" '$$2 == target { print $$3; exit }')"; \
		if [[ "$$simulator_state" == "Booted" ]]; then \
			break; \
		fi; \
		sleep 1; \
	done; \
	if [[ "$$simulator_state" != "Booted" ]]; then \
		echo "Simulator $$resolved_name failed to reach Booted state" >&2; \
		exit 1; \
	fi; \
	sleep 3; \
	echo "Building $(SCHEME) for $$resolved_name..."; \
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-destination "platform=iOS Simulator,id=$$simulator_udid" \
		-derivedDataPath "$(DERIVED_DATA_PATH)" \
		$(XCODEBUILD_FLAGS) \
		build; \
	if [[ ! -d "$(SIMULATOR_APP_PATH)" ]]; then \
		echo "Built simulator app not found at $(SIMULATOR_APP_PATH)" >&2; \
		exit 1; \
	fi; \
	bundle_id="$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$(SIMULATOR_APP_PATH)/Info.plist" 2>/dev/null || true)"; \
	if [[ -z "$$bundle_id" ]]; then \
		echo "Unable to read CFBundleIdentifier from $(SIMULATOR_APP_PATH)/Info.plist" >&2; \
		exit 1; \
	fi; \
	echo "Installing $(SIMULATOR_APP_PATH) to $$resolved_name..."; \
	xcrun simctl install "$$simulator_udid" "$(SIMULATOR_APP_PATH)"; \
	echo "Launching $$bundle_id on $$resolved_name..."; \
	xcrun simctl launch --terminate-running-process "$$simulator_udid" "$$bundle_id"

build-for-testing: ## Build the app and unit test bundle without running tests
	@xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-destination "$(TEST_DESTINATION)" \
		-derivedDataPath "$(DERIVED_DATA_PATH)" \
		$(XCODEBUILD_FLAGS) \
		build-for-testing

test: ## Run the test suite on an iOS simulator
	@xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-destination "$(TEST_DESTINATION)" \
		-derivedDataPath "$(DERIVED_DATA_PATH)" \
		$(XCODEBUILD_FLAGS) \
		test

check: test ## Alias for test

clean: ## Remove derived data produced by this Makefile
	@rm -rf "$(DERIVED_DATA_PATH)"
	@build_dir="$$(dirname "$(DERIVED_DATA_PATH)")"; \
	if [[ -d "$$build_dir" ]]; then \
		rmdir "$$build_dir" 2>/dev/null || true; \
	fi
