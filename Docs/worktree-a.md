# Worktree A: native shell and day-to-day screens

Original stack: **15a → 17a → 17b → 15b**, now at `f438bd2`. Review round 1 fixes
all 14 verified findings on top of that HEAD. Git denied `index.lock`, so the four
ordered follow-up patches are `build/commits/1.patch` through `4.patch`, with one
Conventional Commit subject per line in `build/commits/messages.txt`. The patches
are checked sequentially against HEAD and reproduce the changed files. No references
were recorded and no simulator was launched.

The shell uses a system TabView. Its session-scoped gate observer keeps
verify → terms → walkthrough → Today precedence after acceptance and restoration.
Missing policies remain unresolved until loaded or the explicit first-load allowance;
that allowance preserves the account's walkthrough gate and never overrides verification.

PlanUI observes SQLite through TripsModel and TripPlanModel and ticks through PlanClock.
The sheet writes check-offs through the existing atomic local/outbox mutation, observes
pending marks across hash replacement, and uses the existing sync reconciler. Today
rows open that sheet; the trip card opens the trip destination. My trips follows RN's
section order and descending departure/id ordering. Pull-to-refresh uses the existing
session sync seam.

`App/TripPageDestination.swift` is the single integration point for worktree B. Both
Today and My trips push `TripPageRoute(tripID:dayID:blockID:awaitingSync:)` to it, passing
the native session for its account database and sync services. Replace the destination
body with the trip page; its implementation is deliberately absent here.

The reusable views are `StepSheet`, `LegendSheet`, `CategorySwatch`, `TodayStepRow`,
`TripSummaryCard`, `TodayScreen` and `TripsScreen`. Screen copy is paired en/nl in
`PlanUI/Resources/Screens.xcstrings`; planner sentences use the Phase 14 catalog.
PlanUI geometry/type/colors are generated. The small pattern input in
`Tools/TokenGen/PlanUI.source.json` pins the RN swatch pattern values; marked opacity
comes from TodayRowStates. Category glyphs use native symbols.

Host verification: `make quick` passes lint and all package tests except the known
`APICookieTests.realRedirectCookieHandlingIsDisabled` sandbox EPERM. Because Make stops
there, `make token-tests asset-tests launch-resources-check` was also run and passed.
Direct Swift 6 iOS 17 SDK compilation passed for app/package modules, AppTests and
AppUITests. Those compiler checks do not execute hosted tests or audits. Logs are
`build/final-quick.log`, `build/final-quick-remainder.log` and
`build/final-typecheck.log`, and `build/final-test-typecheck.log`. The explicit offline/429/408 check-off regressions pass in
`build/final-check-off.log`.

Run these hosted suites on 17e after generating the project. Each snapshot suite
contains SE, 17e and Duo geometry profiles, en/nl × light/dark at default size and one
en/light xxLarge reference per state. Row snapshots show running, done and skipped
together. Reference capture/review remains the user's task.

```sh
make generate
make targeted DEVICES="17e" ONLY="AppTests/StepSheetSnapshotTests AppTests/TodaySnapshotTests AppTests/TodayRowSnapshotTests AppTests/TripsSnapshotTests"
make targeted DEVICES="17e" ONLY="AppTests/StepSheetLayoutTests AppTests/TodayControlTests AppTests/TodayLayoutTests AppTests/TripsLayoutTests"
make targeted DEVICES="17e" ONLY="AppUITests/AppTabsTests AppUITests/TodayTests AppUITests/StepSheetTests AppUITests/LegendTests AppUITests/TripsTests AppUITests/PlanAuditTests AppUITests/AuthSessionTests"
```

PlanAuditTests has one en/light/default audit each for Today, the step sheet, legend
and My trips. Its methods use separate mock launches and the runner serializes their
system appearance changes. Legend presentation uses a Debug-only mock-test hook until
worktree B supplies its designed trip-page entry; Today has no added legend control. The UI flows use a terms-accepted, walkthrough-seen mock
account containing active, upcoming and completed trips.

Settings remains the D17 Debug seam. Trip-page UI remains in worktree B. Creation
controls stay hidden until 16c. Terms/walkthrough UI, the undesigned TripNotOnPhone
state, calendar and notifications remain deferred. The future note omits the RN
reminder promise while notifications are out of scope. Release remains non-shipping
while those required destinations and the existing shipping gates are unfinished.


## Review round 1 verification (2026-11-08)

The tab shell uses the dashboard grid and iOS 26 scroll minimization. Signed-out
publication routes away immediately and stops the home model. A session mutation
permit guards the complete SQLite check-off transaction and is revoked before
publication, including queued actions while logout is delayed.

Sheet badges, priority tag/key, full-width actions, step-gone state and VoiceOver
confirmation/focus follow the supplied boards and RN behavior. Today has a separate
future card, paired headings and spoken progress, catalog plural variations, inline
progress and the designed status/empty/hidden treatments. My trips has no-next-step
chevrons, dimmed completed cards and its own accessible loading layout.

`make quick`: strict lint passes; 437/438 package tests pass. The only failure is
the known `APICookieTests.realRedirectCookieHandlingIsDisabled` listener EPERM.
The remaining quick tiers pass: 10 TokenGen tests, 7 AssetGen tests and 98
signing/resource/runner fixtures. The newly added catalog suite is registered as
host-only; its initial classification failure was fixed and all 76 runner fixtures
pass on rerun. The delayed-logout, permit-revocation and en/nl catalog regressions
pass. Direct Swift 6 iOS 17 SDK checks pass for package/app modules, AppTests and
AppUITests; the final router/layout edits also pass focused module compilation.

Logs: `build/round1-quick.log`, `build/round1-quick-remainder.log`,
`build/round1-runner.log`, `build/round1-final-targeted.log`,
`build/round1-final-lint.log`, `build/round1-typecheck.log` and
`build/round1-final-{AppCore,PlanUI}-typecheck.log`.

Only host verification was run. Runtime layout, VoiceOver behavior and visual
reference acceptance remain for the user's simulator session.

## Tab snapshot capture repair (2026-11-08)

`AppTabsSnapshotTests` now uses `SystemTabsSnapshotHost` to capture the production
TabView with `drawHierarchy(afterScreenUpdates: true)` in a key, visible window.
The window supplies the profile's four native safe-area insets; UIKit inherits
the profile's display scale, compact/regular size classes, appearance and capped
Dynamic Type traits. The other screen suites keep their existing layer capture.
The shared Plan snapshot variants and reference naming remain unchanged: 15 tab
references across 17e, SE and Duo, with en/nl × light/dark and en/light xxLarge.

An isolated local account with a successful-sync marker and no trips reaches the
designed TripsEmpty screen. The test selects My trips through UITabBarController
and its existing delegate, waits for the empty screen's accessibility identifier
and stable tab-bar geometry, then captures. No production UI or test hook was added.
Before any reference can be written, throwing guards require a visible, attached
UITabBar with three symbol images and the selected My trips item, correct profile
geometry/traits, a successful hierarchy draw and visible ink in the tab-bar region.
The test also asserts all three localized item titles. Hosted rejection tests
exercise missing, hidden and incomplete bars, wrong selection and blank images.

Host verification: `make lint` passes. `make host-tests` passes all package tests
except the existing `APICookieTests.realRedirectCookieHandlingIsDisabled` loopback
listener EPERM. `make token-tests asset-tests launch-resources-check` passes the
remaining host tiers (10 TokenGen tests, 7 AssetGen tests, 98 resource/runner tests).
Direct Swift 6 iOS 17 SDK compilation checks the app and hosted test sources without
launching a simulator. Logs are `build/tabs-snapshot-{lint,host-tests,host-remainder,typecheck}.log`.
No simulator commands ran and no references were recorded. Runtime capture,
comparison and visual reference acceptance remain for the user's recording pass.
The repair is delivered as `build/commits/1.patch` against `a792f50`, with its
Conventional Commit subject in `build/commits/messages.txt`.

## Simulator failure repair (2026-11-08, base baf799d)

Read the user's failure list and the original `build/test-results/17e/Debug-compare.xcresult`
and `Debug-serial.xcresult`, including their saved audit screenshots. This work ran no
simulator, simulator build, recording, clean or device-matrix command. Direct Swift SDK
compilation only checks types; it does not establish runtime acceptance.

| Failure | Decision and repair |
| --- | --- |
| StepSheetLayoutTests/testStepActionsAndLegendScrollWithinEveryLeanProfile | Test bug. The native scroll frame underlaps the Duo rail. Bound actual accessible content against the window's left/right insets, require accessible content to be found, retain zero horizontal overflow, and diagnose the adjusted viewport using all four insets. |
| TodayLayoutTests/testEveryTodayStateScrollsWithinTheThreeProfilesAtXXLarge | Same test bug. The Duo window is 466 pt wide with a 19 pt right inset: the content limit is 447 pt (448 including the existing 1 pt tolerance). A full-width native scroll frame is not the content's frame. The shared helper now checks actual content. The user's passing TodayControlTests already verified row frames inside this same rail. |
| TripsLayoutTests/testListEmptyAndLoadingStayInsideEveryRailAtXXLarge | Same shared test bug. Check actual list/empty/loading accessibility frames against the supplied rail rather than requiring the native scroll frame to avoid it. |
| StepSheetTests/testTodayStepCanBeDoneUndoneSkippedAndReopened | App bug. Separate optional trip/block state and a presentation Boolean could mount an empty first sheet. One Identifiable selection now carries both IDs through sheet(item:). The UI flow also really dismisses/reopens after Skip, verifies the persisted Undo action, and taps the row's padded trailing edge. |
| PlanAuditTests/testStepSheetPrimaryState | Same app presentation bug, before any audit ran. The audit now reaches the item-backed sheet; presentation assertion failures include the app tree. |
| PlanAuditTests/testTodayPrimaryState | The saved activity log identifies the 80 × 4 progress indicator as the hit-region finding: an app accessibility bug. Keep the native visual progress bar and expose its row as one spoken done/skipped summary. Plain row/card labels also receive content shapes covering their padding. The two contrast findings are Flight and its time subtitle under the floating tab bar, not low-contrast token pairs. Uniquely identify each text by style/token and block context, match its reported frame, reveal that same text above native chrome, and require fresh passing pixels. Dynamic Type findings came from an unrestricted audit despite the settled root cap. |
| PlanAuditTests/testTripsPrimaryState | Test bugs: the three contrast findings are Los Angeles, Amsterdam and the interval of the lower upcoming card, beneath the floating tab bar. Trip/airport/interval identifiers retain identity through reveal and measurement. Apply the same strict pixel policy and root-cap audit selection. |
| PlanAuditTests/testLegendPrimaryState | Test bugs: the contrast finding is the native Close control's glass boundary; its saved text crop measures 19.7134:1 using RenderedTextContrast. Preserve native rendering, add legend.close, and accept only an exact control identity/frame with a fresh complete ≥ 4.5:1 measurement. The cropped failure image is a host regression fixture, not a new screen reference. The Close Dynamic Type finding follows the same root-cap policy. |

Plan audits use the already-settled `all.subtracting(.dynamicType)` type set, as Auth
and Welcome do (plan Phase 5 fix round 3). No per-view cap was added. The existing
xxLarge layout/profile suites remain; host tests verify that all plan text styles
are scalable, and UIKit font assertions compare large, xxLarge and AX5 at the cap.

Contrast exceptions require unique identifier/frame attribution before measurement,
the same label and unique live identifier after reveal, complete visible-line
measurements and a finite minimum ≥ 4.5:1. The reading viewport uses the window's four
safe-area insets plus the current navigation/tab bar frames. Neither clipping nor
being beneath glass grants an exception by itself. Native Close uses its own system
label ink and single-line control frame. Every other failure remains strict; disabled
buttons/switches require matching live identifier, label and frame and only qualify
for contrast/hit-region exceptions. Audit failures and retained attachments print
identifier, label, original/revealed frames, viewport, measured lines/ratios and the
exception decision. The original Close crop is exported attachment
`FEC19E96-DD4F-4F31-B15C-5A3099F846E1.png` from the user's legend audit.

Host verification: `make lint` passes. `make host-tests` reports 442/443 package tests
passing; the only failure is the existing
`APICookieTests.realRedirectCookieHandlingIsDisabled` loopback listener EPERM.
All five PlanLayoutEvidenceTests pass, including the saved native Close crop,
contrast pairs in both appearances (and actual dimmed completed-card pairs),
all seven device profiles/reversed insets, scalable fonts and fail-closed attribution.
The remaining host tiers pass separately: 10 TokenGen tests, 7 AssetGen tests and
98 signing/resource/runner fixtures. Direct Swift 6 iOS 17 SDK compilation checks
the package modules, app, AppTests and AppUITests without launching a simulator.

Logs: `build/plan-failures-lint-final.log`, `build/plan-failures-host-final.log`,
`build/plan-failures-host-remainder.log`, `build/plan-failures-evidence-final.log`,
`build/plan-failures-typecheck-final.log` and
`build/plan-failures-typecheck-tests-final.log`. Runtime presentation, audit reveal
behavior and snapshot comparison remain for the user's 17e run. No references changed.
Delivery: one atomic `build/commits/1.patch` against `baf799d`, with its Conventional
Commit subject in `build/commits/messages.txt`.


## Second simulator rerun repair (2026-11-08, base 229bcfd)

1. The UIKit accessibility walker returns no SwiftUI children on the supplied runtime.
   Layout tests now collect actual content/container/text frames with SwiftUI geometry
   callbacks through an optional environment observer (including across NavigationStack).
   They check both scroll extremes, including lazy content, and still fail on missing
   measurements, horizontal overflow or a rail violation. The new collector regression
   measures deliberately overflowing content, then reconfigures it and checks the new
   64 pt bounds instead of retaining stale frames. Native scroll-frame underlap remains
   valid; the four-inset viewport diagnostics are retained.
2. Sheet existence did not establish a finished presentation. The audit waits for
   stable sheet/title/time/footer/Skip/Done frames before taking its source screenshot.
   Clipping remains a strict failure, with no animation/clipping exemption.
3. The synthesized progress Other element still attracted hit-region audits at 14.7 pt.
   It now has a static Text accessibility representation and a generated 44 pt minimum
   for both the row and representation; the real-app tab flow checks its type and height.
   The saved log shows the Flight title originally at y=781.17 under the glass, then
   y=639.17 after reveal; the subsequent subtitle report is y=658.5 after that movement.
   Mutating scroll position in an audit callback invalidated later frame attribution.
   Findings and original text metadata are now frozen without scrolling during the
   audit. Each finding is then independently attributed and revealed; the complete
   per-line screenshot measurement must still reach 4.5:1. Missing identity, pixels,
   lines or a real contrast failure remains a failure. No token contrast exemption.
4. System bordered styles produced the filled Skip, while the inherited foreground
   overrode the primary label. Sheet actions now use the existing design-system
   AuthButton (native Button): outline Skip/Undo, primaryForeground on primary with
   the supplied check glyph, generated 48 pt size and existing busy/disabled treatment.
   Upcoming actions remain enabled, matching the current behavior and ItemDetail.
5. Remove AppTabsSnapshotTests/SystemTabsSnapshotHost and their runner snapshot entries.
   Their scene/account/tab-controller harness never reached trips.empty on the user's
   runtime. Production-app UI captures replace this unreliable harness.
6. AppTabsTests signs in through launchPlanAccount and retains full-screen screenshots
   named today-tabs, trips-tabs, settings-tabs, today-tabs-minimized,
   trips-tabs-minimized and both *-tabs-expanded captures. Separate iOS 26+ tests scroll
   Today and My trips, require actual content movement and no nested scroll view,
   wait for stable minimized geometry (or hidden non-selected items) with the selected
   tab still hittable, then scroll back and require all three items and the original
   expanded bar/item dimensions. The existing runner entry includes these methods.
   Production screens already have one direct ScrollView under each NavigationStack;
   no gesture interception or wrapper scroll view was added.

Strict make lint and direct iOS 17 app/AppTests/AppUITests source compilation pass.
The final make host-tests run has only the existing loopback-cookie listener EPERM;
remaining generator/resource/runner tiers pass separately (10 TokenGen, 7 AssetGen
and 98 resource/runner fixtures). Final verification logs are build/round2-lint-final.log,
build/round2-host-final.log, build/round2-host-remainder.log and
build/round2-typecheck-final.log. Direct Swift SDK compilation checks iOS 17 source
compatibility without launching CoreSimulator. No simulator, recording or reference
update is claimed. The changed progress height and sheet buttons need snapshot review.

Delivery is one atomic build/commits/1.patch against 229bcfd, with its Conventional
Commit subject in build/commits/messages.txt. To validate on the user's host:

```sh
make generate
make targeted DEVICES="17e" ONLY="AppTests/StepSheetLayoutTests AppTests/TodayLayoutTests AppTests/TripsLayoutTests AppTests/TodayControlTests"
make targeted DEVICES="17e" ONLY="AppUITests/PlanAuditTests AppUITests/AppTabsTests AppUITests/StepSheetTests"
make targeted DEVICES="17e" ONLY="AppTests/StepSheetSnapshotTests AppTests/TodaySnapshotTests AppTests/TripsSnapshotTests"
```

## Third simulator rerun repair (2026-11-08, base 10f539e)

1. The only rail failures in the supplied dump measure the padded outer stacks at
   x=0, width=466. Individual text measurements and the existing Today row-control
   checks do not report rail overflow. The Duo sheet reference also places its
   controls inside the rail. Move the Today, Trips, StepSheet and Legend container
   probes before decorative padding, measuring the inner layout that contains
   text and controls. Keep every individual text probe and both scroll extremes;
   do not intersect measurements with the safe frame or relax the 447 pt limit
   (448 pt with the existing tolerance). Backgrounds and scroll containers may
   fill the window. This changes measurement only, with no content-layout change.
2. Retain the user's leading-padding overflow correction from 10f539e. Extend that
   regression with an unmeasured padded full-width wrapper: deliberate leading
   padding must still exceed the rail, and reconfiguration must still produce
   exactly one fresh 64 x 64 measurement. This exercises the same distinction as
   the screen probes. Execution of this hosted test remains for the user's rerun.
3. Leave Today references and the user's 75 modified StepSheet PNGs untouched.
   Keep the visible progress row at its natural board height; no visible 44 pt
   frame is restored.
4. The failed AppTabs assertion read a Text element's 14.7 pt glyph frame. Replace
   the virtual Text with a labelled nontext accessibility container, creating its
   element after the representation's generated 44 pt frame. AppTabsTests queries
   that unique Other element, waits for stable frames, and checks its spoken
   summary and height. The supplied dump has no minimization-test failure, so
   those assertions stay unchanged.
5. Today audit: the virtual Text says "0 of 3 done", while the rendered row says
   "0/3 done" beside a track/checkmark. It is not rendered text whose clipping or
   contrast can be measured. The labelled container preserves the full spoken
   summary without claiming to be a drawn Text. Its height is asserted before
   the audit; no progress-specific audit exemption is introduced.

   Step-sheet audit: the saved `plan-audit-settled` screenshot shows a settled,
   legible inset medium sheet, not an animation. The reported title, time, body,
   footer and button heights all equal their layout heights times 374/390
   (for example, 48 becomes 46.030769 pt). This is consistent with the native
   partial-height sheet's inset scaling and explains the clipping reports for
   otherwise fully visible text. Apple describes the native inset partial-height
   presentation in [Explore the biggest updates from WWDC25](https://developer.apple.com/videos/play/meet-with-apple/201/?time=6289).
   The audit now drags the native grabber to the existing large detent, waits for
   all relevant frames, and requires full-window width and unscaled title height
   before running. Production presentation is unchanged. No clipping issue is
   ignored, and contrast attribution still requires the same original identity,
   frame, label and complete passing rendered-text measurement. The medium
   detent's Inspector clipping behavior is not claimed fixed; that presentation
   remains covered by the user's screenshots and interactive StepSheetTests.

Verification: `make lint` passes. `make host-tests` passes 442 of 443 package tests;
the only failure is the existing `APICookieTests.realRedirectCookieHandlingIsDisabled`
loopback-listener sandbox `EPERM`. All remaining host tiers pass separately:
10 TokenGen tests, 7 AssetGen tests and 98 resource/runner fixtures. Direct iOS 17 SDK
compilation passes for the package modules, app, AppTests and AppUITests without
running a simulator. Logs are
`build/round3-lint.log`, `build/round3-host-tests.log`,
`build/round3-host-remainder.log` and `build/round3-typecheck.log`.
Hosted layout tests, UI audits, progress representation geometry and snapshot
comparison require the user's simulator rerun; no runtime pass is claimed here.

Delivery: `build/commits/1.patch` against `10f539e`, with one Conventional Commit
subject in `build/commits/messages.txt`. No commits or PNG changes are included.
