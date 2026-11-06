SHELL := /bin/sh
.DEFAULT_GOAL := check
.NOTPARALLEL:

XCODEGEN ?= /opt/homebrew/bin/xcodegen
DESTINATION := platform=iOS Simulator,name=iPhone 17e,OS=27.2
XCODEBUILD := xcodebuild -project ChronoFlow.xcodeproj -derivedDataPath build/DerivedData -onlyUsePackageVersionsFromResolvedFile
SWIFT_PATHS := App AppTests AppUITests PerfUITests Packages/ChronoFlowKit/Package.swift Packages/ChronoFlowKit/Sources Packages/ChronoFlowKit/Tests $(wildcard Tools/*/Package.swift Tools/*/Sources Tools/*/Tests)
SIM_CONCURRENCY ?= 4
SIM_RUNNER := SIM_CONCURRENCY=$(SIM_CONCURRENCY) python3 -I Scripts/launch-simulators.py

.PHONY: generate format lint test snapshots duo perf tokens fonts assets generators-check launch-resources-check check simulator-check matrix targeted host-tests

generate:
	$(XCODEGEN) generate
	mkdir -p ChronoFlow.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
	cp Packages/ChronoFlowKit/Package.resolved ChronoFlow.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved

format:
	xcrun swift format format --in-place -r $(SWIFT_PATHS)

lint:
	xcrun swift format lint --strict -r $(SWIFT_PATHS)

test:
	$(SIM_RUNNER) --no-generate --devices 17e --mode test

snapshots:
	$(SIM_RUNNER) --no-generate --devices 17e --mode snapshots

simulator-check:
	$(SIM_RUNNER) --no-generate --devices 17e

duo:
	$(SIM_RUNNER) --no-generate --devices duo

matrix:
	$(SIM_RUNNER) --welcome

targeted:
	$(SIM_RUNNER) --no-generate --devices $(DEVICES) --only $(foreach selector,$(ONLY),'$(selector)') $(if $(filter 1,$(REUSE_BUILD)),--reuse-build,)

perf:
	$(XCODEBUILD) -destination '$(DESTINATION)' -scheme Perf -configuration Perf test

tokens:
	sh Scripts/swiftpm.sh run TokenGen TokenGen

fonts:
	sh Tools/fonts.sh

assets:
	sh Scripts/swiftpm.sh run AssetGen AssetGen

generators-check:
	sh Scripts/swiftpm.sh test TokenGen
	sh Tools/fonts.sh --check
	build/fonttools-venv/bin/python3 -I Tools/test_fonts.py
	sh Scripts/swiftpm.sh test AssetGen

launch-resources-check:
	python3 -I Tests/test_launch_resources.py
	python3 -I Tests/test_launch_simulators.py

host-tests:
	sh Scripts/host-tests.sh

check: lint generators-check launch-resources-check host-tests simulator-check
