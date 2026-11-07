SHELL := /bin/sh
.DEFAULT_GOAL := check
.NOTPARALLEL:

XCODEGEN ?= /opt/homebrew/bin/xcodegen
SWIFT_PATHS := App AppTests AppUITests RenderTests PerfUITests Packages/ChronoFlowKit/Package.swift Packages/ChronoFlowKit/Sources Packages/ChronoFlowKit/Tests $(wildcard Tools/*/Package.swift Tools/*/Sources Tools/*/Tests)
SIM_CONCURRENCY ?=
SIM_RUNNER := SIM_CONCURRENCY=$(SIM_CONCURRENCY) python3 -I Scripts/launch-simulators.py

.PHONY: generate format lint test snapshots duo perf tokens fonts assets auth-board-pngs generators-check launch-resources-check check simulator-check matrix targeted quick host-tests package-tests token-tests asset-tests

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
	TEST_RUN_TIMEOUT=$(or $(TEST_RUN_TIMEOUT),600) $(SIM_RUNNER) --no-generate --devices duo --mode runtime

matrix:
	$(SIM_RUNNER) --matrix

targeted:
	$(SIM_RUNNER) --no-generate --devices $(DEVICES) --only $(foreach selector,$(ONLY),'$(selector)') $(if $(filter 1,$(REUSE_BUILD)),--reuse-build,)

perf:
	$(SIM_RUNNER) --no-generate --devices 17e --mode perf

tokens:
	sh Scripts/swiftpm.sh run TokenGen TokenGen

fonts:
	sh Tools/fonts.sh

assets:
	sh Scripts/swiftpm.sh run AssetGen AssetGen

auth-board-pngs:
	node Scripts/export-auth-boards.cjs
	sh Scripts/export-auth-pngs.sh

package-tests:
	sh Scripts/swiftpm.sh test ChronoFlowKit

token-tests:
	sh Scripts/swiftpm.sh test TokenGen

asset-tests:
	sh Scripts/swiftpm.sh test AssetGen

host-tests: package-tests token-tests asset-tests launch-resources-check

quick: lint host-tests

generators-check: token-tests asset-tests
	sh Tools/fonts.sh --check
	build/fonttools-venv/bin/python3 -I Tools/test_fonts.py

launch-resources-check:
	python3 -I Tests/test_auth_signing.py
	python3 -I Tests/test_launch_resources.py
	python3 -I Tests/test_launch_simulators.py

check: quick generators-check simulator-check
