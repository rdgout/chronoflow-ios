# Phase 19: local reminders

The RN reminder engine is the blueprint. `Reminders` is a platform-neutral SwiftPM engine with an injected notification center, plus the native `UNUserNotificationCenter` adapter. It observes the account database, never the network, and runs outside the main actor. `NativeSessionController` is created after the launch overlay's first commit.

Selection retains RN's kinds, actionable/check identities, optional filtering, if-you-can avoid-light rule, main-sleep wind-down rule, sleep deferral, 20-minute expiry, bounded 15-minute coalescing and core-first six-per-local-day cap. Scheduling retains the 36-hour lookback, five-second margin, 48-hour window and earliest 60 requests. Current downloaded plans only; completed/deleted trips and done/skipped steps are excluded. A future member of an elapsed group can still be selected, while a delivered merged group is suppressed by the ledger.

The account's SQLite settings table stores a private `reminderLedger` section. Full pulls leave it alone; account close clears it and cancellation drains the scheduling flight before erasing the database. The sign-out stop hook cancels reminders before the best-effort server logout. Stable request identifiers include account, trip, plan hash and member identities. Unchanged pending requests are retained; retimed/content changes replace the same identifier and stale requests are removed. Requests carry JSON-safe trip/step/hash/account metadata so `PendingLaunchIntent.capture` can retain a notification response.

The coordinator reruns after stored settings/check/plan changes, full sync, foreground, significant time and time-zone changes, and language changes. Provisional authorization counts as granted. Date triggers use UTC calendar components, so device-zone changes do not reinterpret their instants. Notification bodies use RN English/Dutch keys and the existing plan formatter for the account's 12/24-hour preference and per-member display zones. Foreground notifications show a banner/list without sound or badge changes.

Cold taps remain captured until the overlay has finished; readiness still chooses Today/terms/verify/walkthrough. Warm taps select Trips, open the trip, and open its step sheet once the matching plan hash is loaded. Repeated taps get a fresh navigation identity. Responses belonging to another account are ignored.

## Boards and scope

`rn-canvas.json` records the source commit and SHA-256 for SetReminders, DarkSetReminders, Ask, Blocked, WizardReminders, WizardRemindersDarkNL and their WizardSheet dependency. Existing identical wizard files remain unchanged.

- The supplied SetReminders page includes Live Activity and practice mode; those cards remain deferred. This phase builds the reminders card, including blocked instructions and the system Settings link.
- RN has a master switch over light/avoid/caffeine/winddown, rather than four separately drawn toggles. The native Toggle changes all four flags through the existing reminders settings outbox; the native Picker offers 15/30/60 minutes.
- SetHome links to Preferences and draws no separate Reminders section. After the 17h restack, Preferences contains Connectivity & reminders beside Replay walkthrough, as SetPreferences and RN draw. It pushes the same reusable page and displays the observed on/off state and lead time. Reading permission on entry/foreground never requests it.
- The board's additional “Each device has its own setting.” sentence and “Push reminders” label have paired Dutch translations; other copy uses RN's Dutch, then backend Dutch. The wizard sheet includes the bell, centered title/body, primary action and Not now.
- The sheet is reusable now. Phase 16c must offer it after the first successful saved trip; 16b/c's save implementation is absent from this base. Its offer/seen bookkeeping belongs to that wiring.

## Validation and rerun

`Tools/ReminderParity/export-selection.cjs` reads RN without changing it. It captures all 110 selection evaluations from every original selection test, including S1–S6, into the committed fixture. Swift compares every draft/member/date/priority against those outputs. A narrow test decoder handles RN's intentionally incomplete synthetic non-sleep params; production DTO decoding is unchanged.

Native scheduling tests cover the window/margin/cap, local-day/DST behavior, elapsed and merged-member suppression, check/undo, optional/if-you-can filtering, both languages/formats and mixed zones, city/IATA titles, ledger validation/pruning, permission states including provisional, UTC triggers, center failures/replacement/removal, concurrent reruns, current offline versions, account switching and real sign-out/wipe. Settings tests cover the reminders outbox, D24 pending protection, permission return, relaunch and revoked permits. Android notification channels and Android permission heuristics have no native iOS counterpart.

UI suites are registered without snapshots:

```
make targeted DEVICES="17e" ONLY="AppUITests/RemindersTests"
```

The tests use the mock account and `-cf.notificationAuthorization granted|blocked|undetermined|unsupported`. A valid isolated `CF_AUTH_TEST_ID` in Debug always injects a fake center, even without the authorization argument or with an invalid value (both default to undetermined). Normal launches keep the system center. The fake grants an undetermined request and retains blocked permission; it never drives the system alert. `-cf.firstTripReminders` exposes only the first-trip test seam. The UI suite covers toggle/relaunch persistence, blocked instructions and the reusable sheet's allow action.

No simulator, snapshot recording, matrix or Duo run was performed. UI execution and visual acceptance remain with the user. Build validation is recorded in the Phase 19 checklist in `plan.md`.

## 17e regression investigation (2026-11-09)

The saved `build/test-results/17e/Debug-compare.xcresult` reports seven failures. Its recording shows the reminders switch remains on after XCTest taps the center of its full-width accessibility row (the synthesized event is x=195, y=279). The switch is at the trailing edge. The persistence test now reveals the row and taps inside that switch, checking the changed value before relaunch.

The saved Settings sign-out test recording shows the initial moon screen, with no notification alert. SettingsPages also fails on a separate simulator clone before the reminders toggle fails, so a leftover permission alert is not established as the shared cause. The granted/blocked/undetermined reminder fixtures already select the existing fake, and the native Toggle calls only `setEnabled`, which cannot request authorization. Other Settings tests previously fell through to the real notification service; session activation/restore queries and cleans up that service before resolving launch readiness. Every isolated UI fixture now uses the fake, removing that system dependency from the test launch path. No alert-dismissal handler or larger timeout hides these failures.

The only production request call remains in `SystemReminderCenter.requestPermission`, reached from the Settings Ask action or the first-trip Enable action. Launch, scheduling, foreground refresh and notification delegate assignment do not request authorization. Host tests count requests across scheduling and permission states. Hosted regressions cover the factory defaults/explicit states and signed-out native launch/foreground with no reminder intent: Welcome, released splash, accessible root, unchanged navigation and zero requests. The existing delegate assignment, splash completion and intent consumption are unchanged.

The Preferences integration removes the temporary Settings-home section and updates all Reminders UI journeys to Settings → Preferences → Connectivity & reminders. Persistence also checks that Back returns to Preferences with the updated summary. Both new summary strings include RN Dutch translations in the same String Catalog change.

Follow-up validation: `make lint` passes. `make quick` and the final `make -k quick` fail only at the known `APICookieTests.realRedirectCookieHandlingIsDisabled` loopback-listener `EPERM`; the latter completes the other tiers: all remaining package tests, 10 TokenGen tests, 7 AssetGen tests and 102 resource/runner fixtures pass. Direct compiler checks pass for Reminders/Settings, Debug and Release app modules, changed hosted tests and all UI tests using the iOS 17 deployment target. Full Xcode build-for-testing is blocked by sandbox cache access; no simulator was run. Logs are under `build/reminder-investigation/`. The existing saved xcresult was inspected without running or changing its simulators.

Two follow-up patches against `7f94803` are exported as `build/commits/1.patch` and `2.patch`, with one Conventional Commit subject per line in `messages.txt`. The root branch is unchanged until those patches are committed. To verify runtime behavior on 17e, run:

```
make targeted DEVICES="17e" ONLY="AppTests/DataSourceBuildSettingTests AppTests/LaunchConnectionTests AppUITests/RemindersTests AppUITests/SettingsTests AppUITests/SettingsPagesTests"
```
