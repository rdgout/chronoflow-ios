# Checking failure repair (t10)

The user's t9 run failed before any field error appeared. The earlier conclusion of "no production stall" was unsupported and is withdrawn. No tests, app launches or simulators were run for this repair. The paths below are established by source inspection; the cause of the reported nine-second tick-zero capture remains unverified.

## Expected behavior and the mock

`_design/canvas/WizardSpec.dc.html` specifies a 30-second server failure and server errors use `WizardCheckServer.dc.html` / `Wizard.dc.html`'s existing failure screen with Try again. RN `src/trips/member-wizard.ts:109–120` retries `ReviewExpiredError` once; `wizardFailure` at line 315 treats a repeated expiry as a server failure. `src/components/trip-wizard/CheckingStep.tsx:257` leaves that failure visible until the user retries. Ordinary field errors return to the step that owns the field.

Web `app/Http/Requests/Api/V1/ReviewTripRequest.php:15` extends `TripJourneyRequest`. Its `legRules` at `TripJourneyRequest.php:166–167` uses `exists:airports,iata` for both endpoints; `messages` at line 108 supplies "Choose an airport from the search results." These are 422 field errors, not expired reviews. RN and web paths are relative to their read-only repositories.

At HEAD `23c8783f`, `MockTripGeneration.review` called `template` before `itinerary`. `template` checked only the first departure and threw `reviewExpired` if that airport was missing. With AMS → NRT, AMS passed that check, so the mock decoded/rebased a plan before destination validation. `wizardReview` did not filter airports first. `itinerary` then mislabeled a missing destination as `from_iata`. This does not establish that the t9 yield loop waited long enough for rebasing, or that it explains the UI capture.

The mock now computes the itinerary before plan generation and returns the correct endpoint's 422 error with the API copy. The airport catalog is unchanged; NRT remains absent from the mock. The existing regression awaits `model.checkTask` instead of counting yields and expects `legs.0.toIata`, Where, no ticks, one request and persisted field errors. A DataAccess unit test covers unknown departure and destination separately.

## Exact production-capable stall and restart path

Before this repair:

1. `MemberWizardReview.swift:167` awaits generation; `TripGenerationService.swift:145` propagates a request/effect `CancellationError`. A request can throw cancellation without the enclosing Checking task being cancelled, for example when a session mutation permit is invalidated (`SessionMutationPermit.swift:14`, through `TripGenerationEffects+Store.swift:15` and `TripGenerationService.swift:128`).
2. `WizardChecking.swift:55` swallowed every `CancellationError` without a terminal event. Its request child finished; `WizardChecking.swift:72–73` then cancelled the progress/timeout child. The 30-second fallback was gone too.
3. `MemberWizardReview.swift:179` cleared `checkTask` while leaving `.checking`, `failure == nil` and possibly tick zero. The user could remain on the spinner indefinitely.
4. A later Checking appearance (`MemberWizardCheckingView.swift:74`) or root task (`MemberWizardView.swift:91`) called `resumeChecking` (`MemberWizardReview.swift:129`). All its guards passed; `runCheck` at line 150 reset progress at line 152 and repeated the request. A persistent cancellation could repeat this sequence on subsequent appearances. No continuous appearance loop is asserted without runtime evidence.

The inline Ready variant awaited generation at `MemberWizardCompletion.swift:171` and swallowed cancellation at its old line 180. That left `reviewing = true` and `reviewTask` retained, so Ready's one-second refresh could never get past the `!reviewing` guard.

Both catches now distinguish the task's actual cancellation state. A request-thrown cancellation while the attempt is active becomes the existing server-failure/retry state; intentional model cancellation remains silent and stale check IDs remain ignored. `beginChecking` also rejects duplicate starts while an attempt is active, so they cannot cancel it and reset the ticks. Manual retries after a visible failure remain allowed.

## Repeated expiry, refresh and cleanup

`TripGenerationReview.swift:28–31` retries expiry exactly once, clearing the identity. A second expiry escapes to `WizardChecking.swift:55–57`, then `MemberWizardReview.swift:175` / `applyFailure` at line 228. It sets `checking.failure`; `resumeChecking` requires no failure and cannot restart it. There is no expiry-to-`beginChecking` callback in the Checking view.

The 30-minute refresh (`MemberWizardCompletion.swift:56–59`) runs only on Ready (`readyTick`, line 127). A failed inline refresh moves to Checking and sets the failure in the same MainActor turn. Save's `reReviewNeeded` branch at line 229 clears the identity and requests one Ready refresh; it does not retry save or loop through Checking. Existing per-attempt IDs keep asynchronous cancellation of a previous attempt from cancelling the next one.

New SwiftPM coverage asserts two server expiry responses, identity clearing for the second request, task/timer completion, a stable failure after appearance/resume and the refresh threshold, and successful manual retry. Separate unit cases cover duplicate starts, request cancellation in both Checking and Ready, and timer cleanup. The repeated-expiry case documents the intended bounded behavior; it is not presented as a reproduced expiry loop.

## Verification and delivery

Strict `make lint`, Debug and Release compilation of DataAccess/TripWizard at the iOS 17 deployment target, type checks of TripWizardTests/DataAccessTests, and `git diff --check` pass. Logs: `build/t10-lint.log`, `build/t10-debug-compile.log`, `build/t10-release-compile.log`, `build/t10-package-source-typecheck.log`. Compiler scripts only emit modules or type-check sources; they never invoke a test runner. Runtime/test acceptance remains with the user.

Git could not create the external worktree Git directory's `index.lock` (`Operation not permitted`). Ordered atomic changes are in `build/commits/t10-1.patch` and `t10-2.patch`, with subjects in `t10-messages.txt`. The working tree contains their final combined result.
