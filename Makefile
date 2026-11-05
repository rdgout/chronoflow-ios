SHELL := /bin/sh
.DEFAULT_GOAL := check
.NOTPARALLEL:

XCODEGEN ?= /opt/homebrew/bin/xcodegen
DESTINATION := platform=iOS Simulator,name=iPhone 17e,OS=27.2
XCODEBUILD := xcodebuild -project ChronoFlow.xcodeproj -derivedDataPath build/DerivedData -onlyUsePackageVersionsFromResolvedFile
SWIFT_PATHS := App AppUITests PerfUITests Packages/ChronoFlowKit/Package.swift Packages/ChronoFlowKit/Sources Packages/ChronoFlowKit/Tests $(wildcard Tools/*/Package.swift Tools/*/Sources Tools/*/Tests)
UI_SUITES := DesignSystemTests LaunchTests WelcomeTests

.PHONY: generate format lint test snapshots duo perf tokens fonts assets generators-check check

generate:
	$(XCODEGEN) generate
	mkdir -p ChronoFlow.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
	cp Packages/ChronoFlowKit/Package.resolved ChronoFlow.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved

format:
	xcrun swift format format --in-place -r $(SWIFT_PATHS)

lint:
	xcrun swift format lint --strict -r $(SWIFT_PATHS)

test:
	$(XCODEBUILD) -destination '$(DESTINATION)' -scheme ChronoFlow $(addprefix -skip-testing:,$(UI_SUITES)) test

snapshots:
	$(XCODEBUILD) -destination '$(DESTINATION)' -scheme ChronoFlow $(addprefix -only-testing:,$(UI_SUITES)) test

duo:
	@destination="$$(python3 Scripts/duo-destination.py)" && \
		$(XCODEBUILD) -destination "$$destination" -scheme ChronoFlow -only-testing:AppUITests/WindowTests test

perf:
	$(XCODEBUILD) -destination '$(DESTINATION)' -scheme Perf -configuration Release test

tokens:
	sh Scripts/swiftpm.sh run TokenGen TokenGen

fonts:
	@test -f Tools/fonts.sh || { echo 'Font generation is scheduled for Phase 1.' >&2; exit 1; }
	sh Tools/fonts.sh

assets:
	@test -f Tools/AssetGen/Package.swift || { echo 'AssetGen is scheduled for Phase 1.' >&2; exit 1; }
	xcrun swift run --package-path Tools/AssetGen AssetGen

generators-check:
	sh Scripts/swiftpm.sh test TokenGen

check: lint generators-check test snapshots
