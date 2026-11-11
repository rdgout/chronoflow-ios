# Wizard test harness rework (t6)

All wizard UI suites use `ScreenTestCase`, signed-in `ScreenTestApp` launches, and board reseeding. English/Dutch route checks and the four board-capture language/theme combinations have separate classes to keep launch settings constant within each class. No wizard UI test signs in through the form. Every wizard UI/hosted suite has a 60-second allowance, inherited by the profile/capture subclasses where applicable. UI waits use `UIWait` through `waitUntil` or explicit backoff conditions.

The live smoke starts at return choice, chooses One way, continues through Fine-tune/Ready, saves, and checks the trip page. `CF_WIZARD_BOARD_CAPTURE=WizardSaveJourney` is the only new seed: a DEBUG-only upcoming direct itinerary at return choice. It uses the real mock review/save service; frozen completion boards retain their existing synthetic review identities.

Combined past-flight/save banners and error labels explicitly carry the static-text trait. Fine-tune's optional rows have a `wizard.extras` container identifier, allowing an exact absence assertion for the no-extras board. Unused time-wheel journey helpers are removed.

Hosted checks retain all original profiles and vertical assertions: footer above the home indicator, errors within the scroll viewport above Continue, and Continue returning to the first error. `WizardLayoutTestSupport.assertVerticallyContained` explains the NavigationStack horizontal-inset limitation. No horizontal safe-inset containment assertion remains for wizard footers or viewports. The user's real Duo screenshots of ReadyAdjusted, FineTuneMulti, ReadyNoCredits and Outbound supply the rail-fit evidence; this change adds no Duo runtime behavior.

## Test inventory

This table covers every pre-existing wizard UI/hosted test. Names omit their `test` prefix. Existing SwiftPM wizard tests are retained, with one added regression for the longer flow removed from the UI smoke.

| Suite | Before | After | Reason |
| --- | --- | --- | --- |
| TripWizardTests (UI) | WhereWithStopTimesOneWaySleepFineTuneAndSave | Kept as OneWayReviewAndSaveOpensTripPage; longer flow moved to SwiftPM | One short navigation/save journey; logic does not need UI |
| TripWizardReviewTests | FlightHomeTimesContainsOnlyFlightCards | Kept | Seeded return-flight screen |
| TripWizardReviewTests | PastArrivalNoticeStaysOnTimes | Split into 2 | Separate outbound/return-flight seeds |
| TripWizardReviewTests | CheckOfflineScreenKeepsEditingAndGoesBack | Kept | Native discard alert and back navigation |
| WizardRouteScreenTests | StopRowsRemoveAndDirectClearsTheRoute | Kept | Route controls and search cancellation on one seeded route |
| WizardRouteScreenTests | DirectSameAndLimitScreens | Split into 3 | Direct, same-airport and limit each have their own seed |
| WizardRouteScreenTests | OneStopUsesDutchCopyAndTheNextSearchNamesItsEndpoints | Kept in WizardRouteDutchScreenTests | Dutch launch settings stay fixed within the class |
| WizardRouteScreenTests | HomeRouteLocksFromAndShowsItsStops | Split into 2 | Direct home route and home route with a stop |
| WizardRouteScreenTests | ThreeFlightsScrollWithContinuePinned | Kept | Real scroll interaction and pinned native control |
| WizardRouteScreenTests | BoardErrorAppearsOnlyUnderTheSecondFlight | Kept | Exact static-text queries for the seeded error screen |
| WizardRouteScreenTests | ContinueScrollsBackToTheOffscreenFirstError | Kept | Explicitly reveal the later error, then exercise Continue; works after reseeding |
| WizardRouteScreenTests | EmptyPillsAnnounceNotSetInDutch | Kept in WizardRouteDutchScreenTests | Exact departure/arrival queries; fixed class language |
| WizardRouteScreenTests | EmptyArrivalPickerStartsOnTheSetDepartureDate | Kept | Native Done commits the computed initial value; timing computation also has package coverage |
| WizardRouteScreenTests | EmptyAndFilledPickerShareTheSheetAndOnlyDoneWrites | Split into 4 | Empty/filled × Cancel/Done; one picker presentation per test |
| WizardCompletionScreenTests | FineTuneBoardsKeepControlsAndFooter | Split into 5 | One Fine-tune board per test |
| WizardCompletionScreenTests | ReadyPricesErrorsAndCheckingStayOnReady | Split into 9 | One Ready/save-error board per test |
| WizardCompletionScreenTests | NoCreditsOffersCloseWithoutBillingOrSaveAction | Kept | Seeded no-credits screen |
| WizardCompletionScreenTests | AllAnswerSheetsUseNativeDoneAndCancel | Split into 11 | One native answer sheet per test |
| WizardCompletionScreenTests | CalculatingHasNoExitAndSwipeDoesNothing | Kept | Native back/close/swipe behavior |
| WizardBoardCaptureTests | EnglishBoardsInLightAndDark | Split into 142 | 71 boards × two classes for light/dark; one capture per seeded test |
| WizardBoardCaptureTests | DutchBoardsInLightAndDark | Split into 142 | 71 boards × two Dutch classes for light/dark; one capture per seeded test |
| WizardErrorScrollTests | ErrorsScrollAboveContinueAcrossAllProfiles | Split into 8 | Board fixture plus seven D1c profiles; both directions/languages/sizes retained, vertical geometry only |
| WizardCompletionLayoutTests | WorstCaseFineTuneAndReadyKeepFooterInsideEveryInset | Split into 2 | SE/asymmetric Duo stress profiles; vertical footer checks only |
| WizardCompletionLayoutTests | NoCreditsCloseStaysInsideThePinnedFooterAboveTheHomeIndicator | Kept | Vertical Close/footer/home-indicator containment |
| WizardCompletionLayoutTests | DuoResizeKeepsFineTuneAndOpenAnswer | Kept | Hosted resize retains the step/open answer |
| WizardCompletionProfileTests | AllBoardStatesInEveryProfile | Split into 189 | 27 boards × seven profile classes; original language/appearance/type-size variants retained |
| WizardFlightPickerTests | CombinedPickerUsesGraphicalDateAndTimeInFixedZoneAcrossProfiles | Split into 8 | Board fixture plus seven D1c profiles, one native picker/profile |
| WizardFlightPickerTests | NativePickerKeepsTheAppLanguageAndPhoneHourCycle | Kept | Hosted native picker locale/hour-cycle integration |
| WizardFlightPickerTests | NativePickerReceivesOnlyTheAirportLocalLowerBound | Kept | Hosted UIDatePicker minimum/maximum/minute-interval integration |
| WizardReviewFlowTests (SwiftPM) | Longer UI journey logic | Added stopOneWayUnsureSleepAndScreeningReachFineTuneThenSave | Validates stop routing, times, One way, unsure sleep, screening, Fine-tune, identity reuse, save and recovery cleanup using controlled clocks |

No pre-existing test coverage is deleted. Horizontal hosted assertions are removed because that harness cannot exercise the claimed safe-area behavior.

## Runner

Added `WizardRouteDutchScreenTests` to the normal UI list. Added `WizardBoardCaptureDarkTests`, `WizardBoardCaptureDutchTests` and `WizardBoardCaptureDutchDarkTests` to the opt-in capture list. The original capture class is English/light. Combined the duplicate `capture` dictionary keys so the Settings entry no longer hides the wizard registrations.

Added `WizardCompletionSEProfileTests`, `WizardCompletion17ProfileTests`, `WizardCompletionAirProfileTests`, `WizardCompletion18ProProfileTests`, `WizardCompletion18ProMaxProfileTests` and `WizardCompletionDuoProfileTests` to both snapshot lists. The original completion profile class covers 17e. Each inherits the same 27 board tests. Capture/profile tests remain opt-in.

## Verification

No tests, simulators, builds-for-testing, or snapshots were run. Runtime correctness and duration budgets have not been measured in this change.

- `make lint`: passes (`build/t6-lint.log`).
- Swift 6/iOS 17 Debug and Release module compilation of TripWizardUI and ChronoFlow: passes (`build/t6-debug-compile.log`, `build/t6-release-compile.log`).
- Swift 6/iOS 17 source type checks of TripWizardTests, AppTests and AppUITests: pass (`build/t6-test-source-typecheck.log`).
- Runner AST syntax and source inventory/registration inspection: pass.
- `git diff --check`: clean.

The compiler checks only emit modules or type-check sources. Existing dependency products in the sibling wizard worktree are read-only; outputs and module caches are under this worktree's `build/`.

## Delivery

Git staging could not create `/Users/rickgout/Sites/chronoflow-ios/.git/worktrees/chronoflow-ios-16c/index.lock` (`Operation not permitted`). The final working tree is complete. Ordered atomic fallback patches are `build/commits/t6-1.patch` (seeded UI/native-control checks and package journey regression) and `build/commits/t6-2.patch` (hosted profiles, vertical containment and final inventory). Their Conventional Commit subjects are in `build/commits/t6-messages.txt`, separated by `---`. They apply to HEAD `65caabff` in order; do not apply them over the already-changed working tree.
