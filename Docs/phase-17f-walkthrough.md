# Walkthrough acceptance

Phase 17f replaces the D17 walkthrough seam with the three Walkthrough boards.
Skip and Done save the local flag and one existing walkthrough outbox row in a
single transaction. Account readiness observes that commit and opens Today;
completion never calls the network. SyncLifecycle already observes new outbox
IDs and schedules retries. Pending completion wins over stale session and identity
responses, including after reopening the database.

Walkthrough POST failures retain the row. A 401 from this optional POST ends that
sync flight as failed, before a full pull, and retries through the existing
backoff. Other authenticated requests keep their existing unauthorized-session
handling. Email verification and terms retain their gate precedence.

## Board interpretation

The 1 Nov canvas note settles Today after first run and Preferences after replay.
The boards implement Next/Done and Skip with decorative 24/8 pt pill indicators;
they do not specify swipe navigation. Native uses those controls instead of RN's
swipe pager. Both primary labels are 40 pt high as drawn by Button lg and the
explicit Done link; their hit targets are at least 44 pt. The timeline preview
keeps the supplied TimelineBlock component's compact icon-only breakpoint, with
its full localised copy on wide layouts. All art comes from existing category,
pattern and progress components. No image asset is missing.

Safe-area layout follows the RN rule: top inset + 8, horizontal insets + 16,
bottom max(inset, 32). The header and footer stay outside the vertically scrolling
content. Both appearances use generated tokens. Every copy entry has its exact
RN Dutch value; example times/flight number are language-neutral. The root's
xxLarge cap is unchanged. Reduce Motion disables indicator animation.

## Deferred

`WalkthroughModel.Mode.replay` invokes the caller's return action without writing
completion again. Preferences and its replay entry are deferred. Terms screens
and actual reminder activation/delivery remain outside this phase. The reminder
explanation remains the supplied board copy. MockDataSource already uses the
seed's default `walkthroughSeen: false`; this branch has no temporary override.

## Verification

Run the UI journeys later on one simulator:

```sh
make targeted DEVICES="17e" ONLY="AppUITests/WalkthroughTests"
```

The two journeys use UUID-scoped fresh accounts with mutation sends held offline:
demo Skip, and the second seeded account's Next/Next/Done in Dutch at xxLarge.
Both relaunch fully offline and require Today, proving an unsent completion does
not replay. Existing auth journeys now assert the real walkthrough title.

No simulator, profile snapshots or seven-device matrix was run for this task.
Host coverage uses the D1c Mac device table, including SE/17e/Duo/Pro Max, and
completion, retry, stale-session, relaunch, replay and bilingual-copy tests.

Validation in this workspace: strict `make lint`; 503 Swift Testing cases and 12
XCTest cases pass with only the existing sandbox-blocked loopback cookie test
excluded. `make quick` was run and fails at that test with EPERM. All 17 token/asset
tests and 100 resource/runner fixtures pass. An intermediate host run under
concurrent compiler load exceeded the existing S3 timeline performance budget;
the final isolated full host run passes. Direct iOS 17 SDK compilation covers the
app, PlanUI and hosted/UI test sources without simulator execution.

## Blank-destination follow-up

The initial 17e run passed AppTabsTests/AuthSessionTests but found both walkthrough
journeys blank and the Settings second-account journey timed out. An empty SwiftUI
Group never mounted the task that created its content. WalkthroughDestination now
hosts initialization on a ZStack with the generated background colour. Missing
session, database or mutation permit retries every 100 ms until ready or cancelled;
database identity and the session epoch are checked before creating the model.

Three hosted WalkthroughDestinationTests mount the actual destination and require
its counter, Skip and Next without user input, including a session and a database
that become available after mounting. They are registered in the simulator runner.
The hosted tests inspect accessibility elements; they do not record screenshots.

The seen override already applies to both seeded accounts. A Mac regression now
checks both values of that override for both accounts. Settings keeps the seen seed
and explicitly requires Today after the second account verifies, before opening
Settings and checking that no old queue remains. Skipping here would enqueue a new
pending completion and defeat the empty-queue assertion while mutations are offline.
SettingsTests and WalkthroughTests stop on their first failed assertion and have a
120 s execution allowance. The shared plan-account launcher throws after a missing
screen's 15 s wait and terminates the app, so its callers cannot continue tapping.

| UI suites checked | Walkthrough handling |
| --- | --- |
| AppTabsTests, TodayTests, TripsTests, StepSheetTests, TripPageStepTests, LegendTests, PlanAuditTests | Shared launcher seeds seen; startup waits now throw on failure. |
| SettingsTests | Seeds seen for both accounts; explicitly checks Today after second-account verification. |
| AuthSessionTests | Seeds seen for both accounts; already stops at the first failed bounded wait. |
| WalkthroughTests | Requires the real pages and completes via Skip or Done. |
| TwoFactorTests, ResetPasswordTests, VerifyEmailTests, AccountRecoveryTests | Successful verified sessions explicitly require the real walkthrough title with bounded waits. Other recovery journeys remain at Verify or sign-in. |
| AuthAuditTests, SignUpTests, SignInTests, SignInKeyboardTests, TwoFactorKeyboardTests, ForgotPasswordTests, ForgotPasswordKeyboardTests | Stop before the verified-session walkthrough gate. |
| ReadinessTests, LaunchSceneTests, LaunchSceneDarkTests, LaunchToWelcomeTests, WelcomeTests, WelcomeEnglishAccessibilityTests, WelcomeDutchAccessibilityTests, WelcomeLogicTests | Stub readiness or signed-out launch/Welcome coverage; no fresh native sign-in. |

PerfUITests were also checked: TimelinePerfTests uses the explicit seen timeline
fixture; LaunchPerfTests measures signed-out launch.

Follow-up validation: `make lint` passes. `make quick` runs all package tests and
reports only the existing APICookieTests loopback-listener EPERM. The new seed
regression passes. The remaining quick targets pass separately: 17 token/asset
tests and 100 resource/runner fixtures. The app and all hosted/UI sources compile
for iOS 17 using swiftc. No simulator was run; the three hosted destination tests
and the UI journeys still need execution. Logs are in
`build/walkthrough-fix-{lint,quick,remaining-quick,ios,tests-ios}.log`.

To execute the affected suites later on 17e:

```sh
make generate
make targeted DEVICES="17e" ONLY="AppTests/WalkthroughDestinationTests AppUITests/WalkthroughTests AppUITests/SettingsTests AppUITests/AppTabsTests AppUITests/TodayTests AppUITests/TripsTests AppUITests/StepSheetTests AppUITests/TripPageStepTests AppUITests/LegendTests AppUITests/PlanAuditTests"
```

Follow-up delivery: `build/commits/1.patch` and `build/commits/messages.txt`, one
atomic Conventional Commit based on `d06fd88`.
