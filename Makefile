SHELL := /bin/sh
.DEFAULT_GOAL := check
.NOTPARALLEL:

XCODEGEN ?= /opt/homebrew/bin/xcodegen
SWIFT_PATHS := App AppTests AppUITests RenderTests PerfUITests Packages/ChronoFlowKit/Package.swift Packages/ChronoFlowKit/Sources Packages/ChronoFlowKit/Tests $(wildcard Tools/*/Package.swift Tools/*/Sources Tools/*/Tests)
SIM_CONCURRENCY ?=
SIM_RUNNER := SIM_CONCURRENCY=$(SIM_CONCURRENCY) python3 -I Scripts/launch-simulators.py
ICON_EXISTING ?=

.PHONY: generate format lint test snapshots audits duo perf perf-timeline tokens fonts assets auth-board-pngs generators-check launch-resources-check check simulator-check matrix targeted quick contracts contracts-check plan-copy host-tests package-tests token-tests asset-tests icon-probe icon-audit

icon-probe:
	python3 -I Scripts/probe-app-icon.py $(if $(ICON_EXISTING),--existing "$(ICON_EXISTING)",)

icon-audit:
	python3 -I Scripts/check-app-icon.py build/DerivedData/Build/Products/Debug-iphonesimulator/ChronoFlow.app

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

audits:
	AUTH_AUDIT_FULL=$(or $(AUTH_AUDIT_FULL),1) TEST_RUN_TIMEOUT=$(or $(TEST_RUN_TIMEOUT),5400) $(SIM_RUNNER) --no-generate --devices 17e --only AppUITests/AuthAuditTests AppUITests/ForgotAuditTests AppUITests/ResetAuditTests AppUITests/SignUpAuditTests AppUITests/VerifyAuditTests $(if $(filter 1,$(REUSE_BUILD)),--reuse-build,)

simulator-check:
	$(SIM_RUNNER) --no-generate --devices 17e

duo:
	TEST_RUN_TIMEOUT=$(or $(TEST_RUN_TIMEOUT),600) $(SIM_RUNNER) --no-generate --devices duo --mode runtime

matrix:
	$(SIM_RUNNER) --matrix

targeted:
	$(SIM_RUNNER) --no-generate --devices $(DEVICES) --only $(foreach selector,$(ONLY),'$(selector)') $(if $(filter 1,$(REUSE_BUILD)),--reuse-build,)

perf:
	$(SIM_RUNNER) --no-generate --devices 17e --mode perf --only PerfUITests/LaunchPerfTests

perf-timeline:
	$(SIM_RUNNER) --devices 17e --mode perf --only PerfUITests/TimelinePerfTests

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
	python3 -I Tools/PlanCopyGen/generate.py --check
	python3 -I Tests/test_plan_copy_generator.py
	sh Tools/fonts.sh --check
	build/fonttools-venv/bin/python3 -I Tools/test_fonts.py

launch-resources-check:
	python3 -I Tests/test_app_icon.py
	python3 -I Tests/test_auth_signing.py
	python3 -I Tests/test_contracts_generator.py
	python3 -I Tests/test_launch_resources.py
	python3 -I Tests/test_launch_simulators.py

check: quick generators-check simulator-check

contracts:
	python3 -I Tools/contracts-gen/generate.py

contracts-check:
	Tools/contracts-check

plan-copy:
	python3 -I Tools/PlanCopyGen/generate.py
