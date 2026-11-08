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
make targeted DEVICES="17e" ONLY="AppTests/AppTabsSnapshotTests AppTests/StepSheetSnapshotTests AppTests/TodaySnapshotTests AppTests/TodayRowSnapshotTests AppTests/TripsSnapshotTests"
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
