# Wizard 16b.2 — route first, then times

Implemented against canvas `1794242613-8e6a`, including `PickerDateTime` and settled OQ 46.

Where edits the ordered route through `WizardForm.route` and `setRouteAirport`; each airport change derives the adjacent flight endpoints. Recovery keeps the existing leg payload as its durable encoding, avoiding two saved copies of the route. New stops split the last flight, with empty arrival and new-flight times; joining retains the first departure and last arrival. The 16-flight cap includes both directions.

The home route has its own navigation step and persisted confirmation. Its From is locked and follows the outbound destination; its To follows the origin until explicitly edited. Old `returnFlight` drafts without that confirmation recover to `returnRoute`, retaining their times. Checking sends airport errors to the route step and time errors to Times. The specified rejected-home-origin message uses the return Times banner.

Times shares one card implementation for both directions. Stops are informational there, Continue is pinned, and each failed Continue scrolls to the first card with an error. Each Departs/Arrives pill opens the same large native sheet with a graphical date-and-time picker in the fixed-zone calendar. Done commits and gives selection feedback; Cancel or interactive dismissal discards the sheet's local selection. Formatting uses the locale's hour-cycle template. Sheet titles reuse Departure/Arrival, with paired Dutch copy.

The obsolete compact picker continuity layout and assertions are removed. Host tests cover route mutation, locks/following, legacy recovery, validation and navigation. Hosted picker coverage checks native graphical date-and-time configuration, wall components and the fixed zone across device profiles. The seeded UI suite checks route states, removal/direct, home locking, scrolling/errors, Dutch next-stop search and picker commit/cancel. There is one mock journey: Where with a stop → Times → One way → Sleep → Checking, followed by the resulting Age question. The other review checks seed their screen directly. Board captures remain opt-in.

## Verification in this sandbox

- `make lint`: passed.
- `make quick`: attempted twice. The warm rerun passed the timeline performance budgets and failed only in the existing `APICookieTests.realRedirectCookieHandlingIsDisabled`, at listener creation (`APICookieTests.swift:9`, `POSIXErrorCode(1): Operation not permitted`). This sandbox cannot open its loopback listener. No test was disabled or changed to hide that failure.
- `sh Scripts/swiftpm.sh test ChronoFlowKit --skip APICookieTests`: passed, including all 94 wizard host tests.
- `make token-tests asset-tests launch-resources-check`: passed, including 79 runner fixtures.
- iOS SDK `swiftc -frontend -parse` for the wizard UI, seeds and tests: passed. This is syntax checking, not native type checking or runtime acceptance.
- No `xcodebuild`, simulator execution, matrix or snapshot recording was run.

## User-run acceptance

First run the native compilation and focused hosted/UI checks:

```sh
make generate
make targeted DEVICES="17e" ONLY="AppTests/WizardFlightPickerTests AppUITests/WizardRouteScreenTests AppUITests/TripWizardTests AppUITests/TripWizardReviewTests"
```

For the visual review, capture the member boards in English/Dutch and light/dark:

```sh
WIZARD_BOARD_CAPTURE=1 make targeted DEVICES="17e" ONLY="AppUITests/WizardBoardCaptureTests"
```

The capture list now includes Where with one/two stops, both home routes, second/home stop search, three flights, two errors and empty stop times. The seeded screen suite also checks the 16-flight limit. Check empty and filled picker presentation, Done/Cancel, error scrolling and the locked home row on the device. Run `make quick` outside this sandbox for its real loopback assertion, then `make check` for the normal all-size snapshot and commit gate. The seven-simulator matrix remains opt-in; no Duo-specific runtime behavior changed.
