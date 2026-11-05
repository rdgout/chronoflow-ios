SHELL := /bin/sh
.DEFAULT_GOAL := check
.NOTPARALLEL:

XCODEGEN ?= /opt/homebrew/bin/xcodegen
DESTINATION := platform=iOS Simulator,name=iPhone 17e,OS=27.2
XCODEBUILD := xcodebuild -project ChronoFlow.xcodeproj -derivedDataPath build/DerivedData -destination '$(DESTINATION)'
SWIFT_PATHS := App AppUITests PerfUITests Packages/ChronoFlowKit/Package.swift Packages/ChronoFlowKit/Sources Packages/ChronoFlowKit/Tests $(wildcard Tools/*/Package.swift Tools/*/Sources)
UI_SUITES := DesignSystemTests LaunchTests WelcomeTests

.PHONY: generate format lint test snapshots perf tokens fonts assets check

generate:
	$(XCODEGEN) generate

format:
	xcrun swift format format --in-place -r $(SWIFT_PATHS)

lint:
	xcrun swift format lint --strict -r $(SWIFT_PATHS)

test:
	$(XCODEBUILD) -scheme ChronoFlow $(addprefix -skip-testing:,$(UI_SUITES)) test

snapshots:
	$(XCODEBUILD) -scheme ChronoFlow $(addprefix -only-testing:,$(UI_SUITES)) test

perf:
	$(XCODEBUILD) -scheme Perf -configuration Release test

tokens:
	@test -f Tools/TokenGen/Package.swift || { echo 'TokenGen is scheduled for Phase 1.' >&2; exit 1; }
	xcrun swift run --package-path Tools/TokenGen TokenGen

fonts:
	@test -f Tools/fonts.sh || { echo 'Font generation is scheduled for Phase 1.' >&2; exit 1; }
	sh Tools/fonts.sh

assets:
	@test -f Tools/AssetGen/Package.swift || { echo 'AssetGen is scheduled for Phase 1.' >&2; exit 1; }
	xcrun swift run --package-path Tools/AssetGen AssetGen

check: lint test snapshots
