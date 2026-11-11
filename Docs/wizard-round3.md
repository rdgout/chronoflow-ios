# Wizard round 3: cached offline checking

Based on `6d7fa57` on `feat/phase-16b-wizard`. The user reports that the 17e wizard journeys, TripWizardTests and TripsTests pass, while the cached-relaunch offline test twice stays on Checking with zero visible ticks.

## Static findings and change

`runCheck` previously awaited `cancellingCheck.value` before entering `WizardChecking.run`. Every cancellation also awaited its predecessor. A suspended cancellation could therefore prevent the request, progress ticks and thirty-second timeout from starting. Checking now starts immediately. Each request uses a unique attempt scope under the recovered draft's instance; cancellation targets that scope asynchronously. Late cleanup cannot cancel or deduplicate against a newer attempt, even with identical review input. The persisted draft instance and server review identity remain intact.

The old view also owned a separate `@State` navigation path, copied model changes into it, and interpreted shorter path updates as user Back actions. A delayed write from the question stack during its replacement by Checking could call `go`, cancel the new check and reset its event guard. The model now supplies the navigation path directly. The binding accepts only a shorter prefix of the currently presented model path, and rejects writes captured from an older path. Normal Back and swipe-back still update the model and cancel Checking.

The cancellation gate is a definite unbounded dependency, but static inspection does **not** establish that it caused this specific cold-launch failure: a newly recovered model starts without a pending cancellation, and the concrete `TripGenerationService.cancelReviews` only signals cancellation and removes entries; it does not await network work. `MemberWizardStore.recover` preserves the draft instance, questions, profile and identity. Both AppTabs entry paths construct a generation service before presenting the model. `CF_AUTH_TEST_OFFLINE` creates a mock source whose review throws `.offline` after its normal 300–800 ms delay. A missing service would produce `.server` inside the running checker, whose timer would still tick. The stale navigation feedback is consistent with a mounted Checking screen whose task was cancelled, but its exact UIKit callback order remains an inference until the 17e failure is rerun. No data-source or offline override behavior was changed.

## Regression coverage and dates

The package regression persists and recovers a draft at a blocking question, then answers it with a real `TripGenerationService` over an offline source. It runs both directly and while a previous review's cancellation is suspended indefinitely. At only 250 ms of injected time, the answer check reports `.offline`, without waiting for cancellation or the server timeout. The suspended cleanup is released only after assertions so the test leaves no stranded tasks. It also checks distinct attempt scopes and retained server identity/profile input.

A second package test supplies an obsolete question-stack pop after the answer starts Checking. The check stays active and reports offline; a subsequent Back from the current stack still returns to the last input.

Wizard UI tests now anchor each test to one `Date()` reading. Outbound uses days +30/+31, return uses +42, the chronology-error case uses +30/+29, and the Past journey uses −30/−29. Gregorian UTC day arithmetic and matching picker formatting handle month/year rollover consistently. The date-wheel helper selects day 1 before changing year/month to avoid intermediate invalid dates.

## Verification

- `make lint` passes (`build/wizard-round3-lint-final.log`).
- `make quick` runs the package suites, including all 66 wizard tests and both recovered-question cases. Its existing cookie-listener test fails with sandbox `EPERM`; this gate cannot be reported as passing here. The cookie test and sandbox restrictions are unchanged (`build/wizard-round3-quick-final.log`).
- iOS package/test compilation targets `arm64-apple-ios17.0-simulator`; direct Swift 6 app, AppTests and AppUITests compilation/type checks pass. These checks do not execute UIKit.
- The remaining quick tiers pass separately: 11 TokenGen tests, seven AssetGen tests and 101 resource/signing/contracts/runner fixtures (`build/wizard-round3-support.log`). The package-test failure stops Make before those tiers.
- No simulator, matrix, Duo or snapshot run/recording is performed. Re-run the reported failure and both ordinary journeys on 17e:

```sh
make generate
make targeted DEVICES="17e" ONLY="AppUITests/TripWizardTests AppUITests/TripWizardReviewTests"
```

Final logs are under `build/wizard-round3-*`. One atomic patch and its Conventional Commit subject are delivered as `build/commits/1.patch` and `build/commits/messages.txt`. An isolated index/object directory verifies replay against `6d7fa57`; the real Git index and branch refs are read-only in this environment and remain unchanged.
