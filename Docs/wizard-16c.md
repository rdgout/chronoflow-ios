# Phase 16c: Fine-tune, Ready and create

The member wizard continues through Fine-tune → Ready → Calculating → the new trip page. Fine-tune is skipped when the review suggests no extras; Ready's Extras row still opens its preparation/sleep controls. Guest and edit variants remain outside this phase.

Fine-tune renders the server's optional prompts, with required suggestions first and their scope attached to flight/stay labels. Native sheets cover seat side, room availability, late check-out, latest wake, busy intervals, free-day sleep, caffeinated drinks, light devices and blue-blocking glasses. Done applies only the prompt's declared fields. Cancel leaves the form alone. Drinks/rating validation matches RN, including comma decimal input. Preparation days and trip-only sleep overrides feed the same review input. Continue re-reviews changes with Checking… held on Fine-tune; unchanged input returns directly to Ready. Ready revisits similarly bypass later steps unless new blocking questions are required.

Ready displays the server's clock-shift summary, dates, itinerary/sleep/extras and price. Unlimited, free, one direction free, return, adjusted, no-credits and Checking variants share the screen. A checked-input fingerprint and review timestamp trigger re-checks at 30 minutes or after changes; recovery and foreground activation also re-check as specified. No-credits offers Close with no billing URL or purchase action (OQ 41).

Saving uses Phase 13's generation service and DataSource. Web `routes/api.php` and `Actions/Api/PresentMobileReview.php` confirm POST `/v1/trips/review` and POST `/v1/trips`; saving sends `draft_token`, `input_revision` and `review_revision`. The mock supplies scoped optional prompts and retains its existing create/receipt behavior. No replacement transport or outbox mutation was added.

Calculating hides Close/back, disables the native edge gesture and rejects navigation/duplicate saves in the model. A failed save returns to Ready with the designed offline/server banner; 429 uses a ceiling countdown and only enables manual retry at zero. Save failure does not schedule another save. Expired/no-credit responses clear the identity before re-checking on Ready. Interrupted Calculating resumes its one in-flight operation on recovery, per WizardSpec. The returned `savedTripId` is persisted to the fixed hidden recovery row before pull effects; a recovered ID bypasses creation. A lost HTTP response retries the same review identity and uses the server/mock receipt. Completion deletes the recovery record and dismisses onto `TripPageRoute(awaitingSync: true)`. OQ 43's first-trip reminders sheet is wired as described below.

The existing native discard alert remains available before save. My trips has its native plus/empty-state action and paired creation copy. Empty/completed Today now offers Plan a trip. Root Dynamic Type capping remains unchanged; content uses safe-area layout, the board's generated column width, and vertical Ready labels above xLarge.

## Verification today

The user's instruction prohibits **all test execution until tomorrow**. No host/package tests, simulator, UI tests, snapshot recording, readiness/performance run or matrix was executed. Token generation, formatting, strict lint and direct compiler/type checks are the only executable verification used.

Compiler checks use Swift 6, the installed iPhoneSimulator SDK and an iOS 17 target. They emit modules/type-check source; they do not build, link, install or launch an app/test process. Existing dependency products are read from the wizard worktree. Temporary Bundle accessors are used only for compiler checking, so resource loading is still a runtime acceptance item. Logs are under `build/wizard-16c-*`.

Verified without executing tests:

- Strict formatting lint: `build/wizard-16c-lint.log`.
- Generated board metrics: `build/wizard-16c-tokens.log`.
- Debug iOS 17 module compilation: `build/wizard-16c-compile-final.log` and the final app-only pass `build/wizard-16c-app-typecheck.log`.
- Release conditional source compilation: `build/wizard-16c-release-typecheck/` and `build/wizard-16c-release-compile.log`.
- All TripWizardTests/DataAccessTests/AppTests/AppUITests source type checks: `build/wizard-16c-test-typecheck.log`.
- `git diff --check HEAD`: clean. Git commit creation failed on the worktree lock; no commit, merge or push was created.

## Tomorrow

Run the host logic and normal commit gate when testing is permitted:

```sh
make quick
make generate
make targeted DEVICES="17e" ONLY="AppTests/WizardCompletionLayoutTests AppUITests/WizardCompletionScreenTests AppUITests/TripWizardTests"
```

The two new package suites are `WizardCompletionTests` and `WizardSaveRecoveryTests`. They include expiry boundaries, changed input, foreground credit refresh, scoped answers, save lockout, manual offline/429 retries, identity reset, a lost mock save response, durable saved-ID recovery and legacy recovery decoding. Existing API fixtures already pin the real endpoints and one-request failure behavior. New optional-prompt copy checks cover both languages.

New UI screen checks use the signed-in reseed path and auto-open the selected Debug board. They do not repeat the wizard journey or sign-in. `TripWizardTests` retains the single end-to-end mock journey and now reaches Fine-tune, Ready and the trip page. Hosted layout checks use SE/asymmetric Duo fixtures and resize the same model/window with an answer open. These tests are authored and type-checked, **not passed**.

For opt-in visual inspection on one 17e simulator:

```sh
make targeted DEVICES="17e" ONLY="AppTests/WizardCompletionProfileTests"
```

This attaches every new board state in all device profiles, both languages/appearances and the profile's prescribed type sizes. It does not create comparison references. `WizardBoardCaptureTests` also includes all new boards for its existing opt-in capture command. Review Fine-tune's longest list, every sheet (including invalid drinks/rating), sleep override, Ready with returns/price states, save errors and Calculating. Check the footer above the keyboard/home indicator, Dutch xxLarge, asymmetric insets, VoiceOver labels/focus and back/swipe lockout. No seven-simulator matrix is needed.

M2 remains open. After the user prepares local Valet and the four migrations, create an API-backed trip in English and Dutch, land on its page and inspect the timeline. Record that result separately. No local Valet or production acceptance is claimed.

## Delivery

Git commit creation was denied while creating the worktree's `index.lock`. Ordered patches and matching Conventional Commit subjects are in `build/commits/1.patch` onward and `build/commits/messages.txt`. They target the branch's original HEAD; the working tree already contains the implementation, so do not apply them again over those changes. No merge or push was attempted.

## First-trip reminders integration (2026-11-10)

RN queues an account-scoped pending offer in `ReadyStep.tsx` after successful save, then `WizardRemindersOffer` in the trip route consumes it before opening the existing sheet. It waits for reminder settings and permission, and shows only for undetermined permission with at least one enabled kind. Not now, an already-requested permission or disabled reminders consume the offer permanently for that account store.

Native save queues a private `wizardReminders` settings row before deleting wizard recovery. The trip destination consumes it transactionally after the full-screen wizard dismisses and the trip page mounts, including awaiting-sync pages. Full pulls preserve that private section; duplicate/recovered saved-ID completion cannot overwrite seen state. No new screen or copy is added. The existing Debug `-cf.firstTripReminders` seam remains for `RemindersTests`.

`FirstTripRemindersOfferTests` is registered in the runner. Package coverage includes the permission/enabled matrix, later trips, missing settings, concurrent consumption, account isolation, database reopen, save failure/manual success, and saved-ID recovery after the sheet was consumed. Existing frozen board seeds use synthetic review identities, so this change adds no separate UI seed just to exercise a save; the existing reminder UI checks remain intact. All tests are deliberately unrun under the current instruction; compile-only/lint results are recorded with delivery.

Verification for this integration: strict `make lint`, direct Swift 6/iOS 17 Debug and Release module compilation, and type checks of RemindersTests, TripWizardTests, AppTests and AppUITests pass. Runner syntax parses and `git diff --check` is clean. Logs: `build/r2-lint.log`, `build/r2-debug-compile.log`, `build/r2-release-compile.log`, `build/r2-package-source-typecheck.log` and `build/r2-app-source-typecheck.log`. No tests, simulators or snapshots were run.
