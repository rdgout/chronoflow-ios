# Wizard 16b.2 — route first, then times

Implemented against canvas `1794242613-8e6a`, including `PickerDateTime` and settled OQ 46.

Where edits the ordered route through `WizardForm.route` and `setRouteAirport`; each airport change derives the adjacent flight endpoints. Recovery keeps the existing leg payload as its durable encoding, avoiding two saved copies of the route. New stops split the last flight, with empty arrival and new-flight times; joining retains the first departure and last arrival. The 16-flight cap includes both directions.

The home route has its own navigation step and persisted confirmation. Its From is locked and follows the outbound destination; its To follows the origin until explicitly edited. Old `returnFlight` drafts without that confirmation recover to `returnRoute`, retaining their times. Checking sends airport errors to the route step and time errors to Times. The specified rejected-home-origin message uses the return Times banner.

Times shares one card implementation for both directions. Stops are informational there, Continue is pinned, and each failed Continue scrolls to the first card with an error. Each Departs/Arrives pill opens the same large native sheet with a graphical date-and-time picker in the fixed-zone calendar. Done commits and gives selection feedback; Cancel or interactive dismissal discards the sheet's local selection. The app locale preserves the phone's hour-cycle override when resolving English or Dutch, so the pill and native picker follow the phone's 12/24-hour setting. Sheet titles reuse Departure/Arrival, with paired Dutch copy.

The obsolete compact picker continuity layout and assertions are removed. Host tests cover route mutation, locks/following, legacy recovery, validation and navigation. Hosted picker coverage checks native graphical date-and-time configuration, wall components and the fixed zone across device profiles. The seeded UI suite checks route states, removal/direct, home locking, scrolling/errors, Dutch next-stop search and picker commit/cancel. There is one mock journey: Where with a stop → Times → One way → Sleep → Checking, followed by the resulting Age question. The other review checks seed their screen directly. Board captures remain opt-in.

## Verification in this sandbox

- `make lint`: passed.
- `make quick`: attempted twice. The warm rerun passed the timeline performance budgets and failed only in the existing `APICookieTests.realRedirectCookieHandlingIsDisabled`, at listener creation (`APICookieTests.swift:9`, `POSIXErrorCode(1): Operation not permitted`). This sandbox cannot open its loopback listener. No test was disabled or changed to hide that failure.
- `sh Scripts/swiftpm.sh test ChronoFlowKit --skip APICookieTests`: passed, including all 94 wizard host tests.
- `make token-tests asset-tests launch-resources-check`: passed, including 79 runner fixtures.
- iOS SDK `swiftc -frontend -parse` for the wizard UI, seeds and tests: passed. This is syntax checking, not native type checking or runtime acceptance.
- No `xcodebuild`, simulator execution, matrix or snapshot recording was run.

## Adversarial review fixes (2026-11-09)

All 12 confirmed findings are addressed; rejected findings and plan checkboxes are unchanged.

The pill's full 44 pt target has an explicit content shape. Empty pills announce "not set" / "niet ingesteld" while keeping "Choose" as visible copy. Only the DatePicker receives dawn tint. App-language resolution retains the phone's hour cycle, with host tests covering both languages and explicit overrides opposite to regional defaults. A hosted configuration test checks that the underlying UIDatePicker receives that language and hour cycle.

Route errors cover the entire row, including the remove control, with rounded corners only at the card's outside corners. The remove circle uses the regenerated 36 pt token within a 44 pt target. The last-trip hint is hidden for equal From/To airports; its seeded screen now retains the prefill flag to exercise that condition. Search excludes adjacent airports when inserting/replacing stops or editing endpoints beside stops, and the model rejects the same choices without mutating the draft. Direct From/To choices still support the designed same-airport error.

Mixed server errors select the earliest editor in journey order. Host regressions cover mixed error dictionaries and model-level return-stop insertion, replacement and No, direct, with a nonzero return boundary and outbound/time/persistence checks. Both new host suites are registered with the runner.

`WizardOutboundTwoErrors` now matches its board: the first flight is valid and only the second arrival has the order error. A separate five-flight fixture tests scrolling, outside the capture list. The UI test reveals the last error and requires the first to be above the viewport and unhittable before Continue, then requires it to return fully into view. Five flights keep that precondition meaningful on larger phones too. Native compilation also caught the screen-content closure captured by ScrollViewReader; its declaration now permits escaping.

Verification:

- `make lint`: passed (`build/wizard-review-lint.log`).
- Full `make host-tests`: attempted; the existing `APICookieTests.realRedirectCookieHandlingIsDisabled` fails because this sandbox denies its loopback listener (`build/wizard-review-host-tests.log`). No test source was disabled or altered to hide it.
- `sh Scripts/swiftpm.sh test ChronoFlowKit --skip APICookieTests.realRedirectCookieHandlingIsDisabled`: passed, 611 Swift Testing tests plus the XCTest suites (`build/wizard-review-package-tests.log`).
- Token/asset tests, resource/signing/contracts fixtures and all 79 runner fixtures: passed. The runner initially reported the two new unregistered suites; registration and its rerun pass (`build/wizard-review-tooling-tests.log`, `build/wizard-review-runner-tests.log`). TokenGen freshness also passes for all 56 outputs (`build/wizard-review-tokens-check.log`).
- Package/test compilation for `arm64-apple-ios17.0-simulator`: passed (`build/wizard-review-ios-build.log`). Direct Swift 6 app-module compilation and all AppTests/AppUITests type checks pass (`build/wizard-review-typecheck/`). These are compile checks only; no simulator was started and no runtime tests or captures were executed.

## Chronological picker bounds and starting values (2026-11-09)

`WizardFlightTiming` is a pure model value over the form and airport metadata. `minimumLocal(for:)` converts the immediate predecessor through its airport's IANA zone into an absolute instant, then into the current airport's wall components in the fixed picker calendar. Arrival follows its departure; every later departure follows the previous arrival, including the first home flight. An unset predecessor leaves the picker unbounded. The native picker receives `in: minimum...` and no upper bound.

`initialLocal(for:now:)` retains filled values, even below a new bound. Empty fields search backwards for the nearest earlier set instant and convert it into the current airport's wall components. Without an earlier value they use airport-local now, clamped to the minimum and reduced to minute precision; the native picker's default interval is one minute. Opening/cancelling a sheet does not write to the draft. Connection validation now compares absolute instants through both airports' zones, and existing arrival validation still flags values below a changed bound.

Host regressions cover NRT→HNL, AKL→LAX, NRT→SFO, AMS→JFK and JFK→AMS, outbound/home chains, unset fields, missing airport metadata, fallback now, retained invalid values and persisted validation errors, plus airport DST gaps/folds and offset transitions. The existing `WizardOutboundStopNew` fixture supplies a departure of 12 October 2026 at 14:40 in Amsterdam with an empty Dubai arrival; the cheap seeded UI test opens arrival and accepts the untouched selection, requiring 12 October at 16:40. Hosted coverage also checks the native lower bound, absent upper bound and one-minute interval. The mock journey helper now navigates the calendar from the preceding flight's date.

Verification:

- `make quick`: strict lint passed; the package run hit the existing loopback-listener sandbox denial and one timeline performance sample over budget while the iOS compile was also running (`build/wizard-timing-quick.log`).
- `sh Scripts/swiftpm.sh test ChronoFlowKit --skip APICookieTests.realRedirectCookieHandlingIsDisabled`: passed, including all wizard regressions and the unchanged timeline performance budgets, in a standalone rerun (`build/wizard-timing-package-tests.log`). The denied test remains unchanged and still needs the unsandboxed host gate.
- `make token-tests asset-tests launch-resources-check`: passed, including all 79 runner fixtures (`build/wizard-timing-tooling-tests.log`).
- iOS 17 package/test compilation and direct Swift 6 app/AppTests/AppUITests type checking: passed (`build/wizard-timing-ios-build.log`, `build/wizard-timing-typecheck.log`). No simulator, runtime test, capture or matrix was run.

## User-run acceptance

### Deterministic error-scroll follow-up (2026-11-09)

The reported 17e rerun passed `WizardFlightPickerTests`, `TripWizardTests`, `TripWizardReviewTests` and the second-flight-only error check. The remaining offscreen-first-error check no longer calls the auth reveal helper or waits for offscreen accessibility frames to settle. Only `WizardOutboundScrollErrors`, with a valid `CF_AUTH_TEST_ID` in DEBUG, starts at the bottom through the native initial scroll anchor. Typed `staticTexts` queries verify the later error is hittable and wholly inside the scroll viewport above the identified pinned footer, then Continue must bring the first error into that same visible area.

Continue now centres the invalid flight's error-message group rather than aligning the whole card's top. The scroll runs on the next main-loop turn so newly inserted error anchors exist, and respects Reduce Motion. The error group and footer use the existing optional layout measurement hook. `WizardErrorScrollTests` renders the real outbound and home Times screens for the board and all seven device profiles, including Duo's side inset, in English/Dutch at default/xxLarge. It seeds errors, starts at the bottom without gestures and triggers the same scroll-request observer used by Continue without animation through its DEBUG request override; the UI screen check separately covers the actual button. It requires the first error to start above the viewport and end wholly inside it, clear of the full footer. This suite records no references and runs on one 17e simulator.

Verification:

- `make lint`: passed (`build/wizard-scroll-lint.log`).
- Full `make host-tests`: attempted and failed only at the unchanged `APICookieTests.realRedirectCookieHandlingIsDisabled` loopback listener (`Operation not permitted`, `build/wizard-scroll-host-tests.log`).
- Package tests excluding only that sandbox-denied listener, plus token/asset tests and resource/runner fixtures: passed (`build/wizard-scroll-package-tests.log`, `build/wizard-scroll-tooling-tests.log`).
- Direct Swift 6/iOS 17 compilation of the changed UI module and app, and AppTests/AppUITests type checks: passed (`build/wizard-scroll-typecheck.log`). Native SwiftPM build planning cannot resolve iOS destinations in this sandbox; the direct compiler checks use the installed simulator SDK and existing dependency modules.
- CoreSimulator's service connection is denied (`build/wizard-scroll-simulators.log`), so the new all-size hosted regression and corrected UI check still need the 17e run below. No runtime result, snapshot comparison or matrix run is claimed.
- The worktree's Git index is outside the writable sandbox, so `git add` is denied. A single Conventional Commit patch is prepared at `build/wizard-scroll-fix.patch`; the branch cannot be advanced here.

### Static-text visibility and bottom-seed readiness (2026-11-09)

The user's subsequent 17e run passes `WizardErrorScrollTests`, `WizardFlightPickerTests`, `TripWizardTests` and `TripWizardReviewTests`. The remaining `WizardRouteScreenTests.testContinueScrollsBackToTheOffscreenFirstError` failure comes from asking XCUI for a StaticText activation point before its frame is usable.

The visibility predicate now checks existence and a non-empty current frame fully inside the current viewport above the non-empty footer frame. It never asks error text for hittability; the first error's offscreen precondition uses existence and frame position, and only Continue needs hittability in this test. The five cards are built by an eager `VStack`. The UUID-gated DEBUG seed retains the native bottom initial anchor and exposes its footer identifier only after geometry confirms the padded content's bottom lies inside the scroll viewport, allowing one display pixel for rounding. Readiness stays latched when Continue scrolls back to the first error. Ordinary screens and Release builds do not install this geometry observer.

Verification:

- `make lint`: passed (`build/wizard-scroll-ready-lint.log`).
- Full `make host-tests`: attempted; the known loopback-listener sandbox denial and unchanged 30-day/S3 timeline timing limits fail while iOS compilation is running (`build/wizard-scroll-ready-host-tests.log`).
- Standalone package tests excluding only `APICookieTests.realRedirectCookieHandlingIsDisabled`: passed, including all 94 wizard host tests and every unchanged timeline performance budget (`build/wizard-scroll-ready-package-tests.log`).
- Token/asset host tests and all resource/runner fixtures: passed (`build/wizard-scroll-ready-tooling-tests.log`).
- Direct Swift 6/iOS 17 UI/app compilation and AppTests/AppUITests type checking: passed (`build/wizard-scroll-ready-typecheck.log`). No simulator or snapshot was run; the corrected 17e UI check remains pending.
- `git add` is denied at the worktree's external Git index. The atomic patch is `build/wizard-scroll-ready-fix.patch`, with subject `fix(wizard): await bottom seed before polling error frames`; the real branch remains at `5e851e3`.

Rerun the focused hosted/UI suites on 17e:

```sh
make generate
make targeted DEVICES="17e" ONLY="AppTests/WizardErrorScrollTests AppTests/WizardFlightPickerTests AppUITests/WizardRouteScreenTests AppUITests/TripWizardTests AppUITests/TripWizardReviewTests"
```

For the visual review, capture the member boards in English/Dutch and light/dark:

```sh
WIZARD_BOARD_CAPTURE=1 make targeted DEVICES="17e" ONLY="AppUITests/WizardBoardCaptureTests"
```

The capture list now includes Where with one/two stops, both home routes, second/home stop search, three flights, the second-flight error and empty stop times. The seeded screen suite also checks the 16-flight limit. Check empty and filled picker presentation, Done/Cancel, dawn tint, row error corners, remove-circle size, error scrolling and the locked home row on the device. Check both app languages with the phone set to 12-hour and 24-hour time. Run `make quick` outside this sandbox for its real loopback assertion, then `make check` for the normal all-size snapshot and commit gate. The seven-simulator matrix remains opt-in; no Duo-specific runtime behavior changed.
