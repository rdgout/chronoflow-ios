# Auth acceptance gate — Phase 10b, task 2 (7 November 2026)

The user reports `make check` (17e) and `make duo` completely passing at 4a3e3ea. The
Two-factor side-by-side review is complete: code none/attempts/server and recovery attempts are
acceptable adaptations; fix round 4 corrects rejected-code copy and the missing recovery placeholder.
Task 2 is ticked under the user's explicit closeout instruction: only their updated simulator
reruns and intentional reference recording/comparison remain before pushing. No new runtime or
reference-comparison pass is claimed. Fix round 3's strengthened checks also need those reruns.
Phases 6–8 retain their accessibility, performance and physical-device gates.

Matrix A means all seven D1c profiles in Mac geometry tests and hosted captures inside **one 17e**,
plus 17e keyboard/routing/accessibility UI tests. It does not request seven simulator runtimes.
`make duo` is the opt-in runtime spot check. The full/compact profile split remains unchanged.

| Board / state | Native checks | Evidence / remaining acceptance |
| --- | --- | --- |
| AuthSignIn none / wrong→credentials / locked / server, light/dark | Generated tokens, native controls, layout, strict text ratios, 896 profile/board references and AX5 equality | User's Phase 10a results and eight-pair visual acceptance pass (8e2d542; `_design/frames/README.md`). Round-1 capture guards and profile comparisons pass. |
| AuthTwoFactor code none / field error / attempts / server, light/dark | Shared controls, max-six oneTimeCode, number-pad submit, field/banner mapping, profile captures | User's task-1 hosted comparisons pass; 1,792 code/recovery references committed at 0e92b6a. Round-1 guards, sessions and profile comparisons pass. Board review accepts none/attempts/server; fieldError copy is corrected in round 4 and needs intentional reference recording/comparison. Revised simulator checks remain the user’s run. |
| AuthTwoFactor recovery none / attempts / server, light/dark | Mode toggle, hint, recovery Return, consumed-code mock/model checks, profile captures | Board review accepts recovery attempts apart from the shared missing placeholder. Round 4 adds that placeholder to all recovery states; recovery-* needs intentional reference recording/comparison. Field-error snapshots retain the shared Field treatment and approved backend copy; there is no separate recovery-error board. |
| AuthStates / Field / Button | Designed banners, native input/button states, touch targets, color/typography/shadow guards | Previously accepted shared controls; round 4 uses the existing placeholder token and Field error treatment. |

The earlier minimized-keyboard results were withdrawn. OQ 32 was subsequently **settled** at
9505993: the user supplied visible-keyboard passes on 17e, SE and Duo for SignInKeyboardTests,
TwoFactorKeyboardTests, TwoFactorTests and SignInTests (plan.md records the correction/results).
The runner still writes `AutomaticMinimizationEnabled=false` on each booted destination before
any UI pass, including check, Duo, targeted/reused builds and Perf. Helpers require stable keyboard
frames with at least 100 × 100 points intersecting the window, focused-input/submit containment
above the keyboard and hittability. The user's round-1 check/Duo results confirm those keyboard
suites pass; the revised reveal helper still needs execution.

Auth captures now reject a wrong-size/scale raster, transparent pixels, missing measurements,
horizontal clipping and vertically clipped brand/heading. Brand and heading must contain rendered
ink: a sky gradient alone cannot pass the blank guard. Validation happens before comparison or
recording, including AX5 equality captures. Mac mutation tests cover missing/clipped/blank/gradient/
transparent captures and recording without writes on failure. Deliberately scrollable content may
extend below the initial viewport; AuthSnapshotGuardTests scrolls every Sign in and Two-factor
control fully into view on the board/all seven profiles and an extra four-inset Duo fixture,
en/nl, light/dark, default/xxLarge. The user's round-1 `make check` passes these hosted scroll checks.
Captures retain each profile's own scale and four insets, including Duo's side rail. No references were changed.

AuthSessionTests enters credentials through the native forms and asserts existing D17 routes:

- Verified demo → `.today`; two-factor code and recovery → `.today` only after proof.
- Unverified demo → `.verify`, both after sign-in and cold restore; no Today/verification screen is invented.
- Cold relaunch restores the persisted session; background/foreground retains the route without replaying
  splash/Welcome. A cold process still gets its one splash under D16.
- Wait for a real SQLite `synced_at` before relaunching with every mock source offline; restore `.today`
  and the cached marker. No `-cf.session`/stored-readiness override supplies a session or readiness.
- Tap the existing Debug route diagnostic to call the real controller's voluntary discard/sign-out/wipe;
  return directly to Sign in without splash/Welcome, then relaunch offline to Welcome with empty auth fields.
  AccountWipeTests separately verifies exact DB/WAL/SHM, Keychain and wipe-marker deletion; the UI seam
  cannot inspect files. The user's round-1 `make check` passes the hosted and UI session suites.

Each new session/audit launch uses a UUID-specific file-backed fake server/account root and Keychain service, retained
across relaunch. It uses the shared Debug mock scenario values from e6623a3, with verification and
walkthrough flags applied to the same seed for gate coverage. Default demo behavior stays unchanged.
Debug-only `CF_AUTH_TEST_ID` enables this isolation; `CF_AUTH_TEST_OFFLINE`,
`CF_AUTH_TEST_UNVERIFIED` and `CF_AUTH_TEST_WALKTHROUGH_SEEN` only apply within that namespace.
Offline state is installed in the mock constructor, before its first request. The existing route
text exposes cache/sync readiness diagnostics and the test-only tap; no token, account data or
new screen is shown. Release/Perf compile out the configuration, seed and route diagnostic.
Ordinary Release remains non-shipping while Today/terms/walkthrough/verify destinations are unbuilt
(D17/D27/OQ 24). Forgot/Sign up stay their existing seams.

AuthAuditTests audits Sign in and both Two-factor modes, en/nl × light/dark × default/xxLarge,
scrolling every back/passkey/input/submit/link/footer/mode-toggle control fully into the viewport
before auditing. Device appearance and session foreground tests run serially. The audit includes
contrast, text clipping, hit regions and traits; the dynamicType audit is excluded because the
intentional root xxLarge cap is separately checked by AX5-equality snapshots. Audit errors include
identifier, label, type, language/size, appearance and stage in logs/attachments, and do not stop the
remaining controls from being audited. **No new audit pass is claimed until execution.**

Only `(sign-in.guest, .contrast)` is unconditionally allow-listed (OQ 33), plus measured subtitle
contrast exception, user 2026-11-07. An exact `auth.subtitle` contrast issue from Sign in or
Two-factor may be ignored only when RenderedTextContrast measures every visible line ≥ 4.5:1
from the app screenshot in that same language, appearance, size and reveal stage. A missing line,
unavailable measurement or lower minimum fails. Source screenshots, per-line ratios and the measured
minimum are retained in attachments/failures. Nil/prefix/other identifiers and combined types stay
strict. The existing subtitle identifier is reused; there is no copy matching. Generated/native guards
retain accepted border/guest-pill values. At the board footer centre, text/pill remains 14.9260:1
light / 15.0953:1 dark, with its 90% opacity; the guest boundary/pill acceptance remains in OQ 33.
See [auth-subtitle-contrast.md](auth-subtitle-contrast.md) for measurement details and prior evidence.

Mac verification: `make quick`, runner selection/failure/skip/record-isolation fixtures, capture
mutation tests and mock scenario/offline/persistence tests pass. `make generate` includes the new UI
files through the AppUITests directory glob and compiles the shared scenario-values source into
that target. Direct Swift 6 iOS 17 Debug/Release app/module/SIL and hosted/UI test compilation is
checked without xcodebuild; compilation is not UIKit execution. Exact results/commands are in
Docs/tooling.md, Phase 10b task 2.

Pending user simulator acceptance: re-record the intentional **code-fieldError and recovery-***
changes on 17e (all existing profiles/categories, en/nl, light/dark), compare in a fresh process,
then `make check` and the previously requested opt-in `make duo`. The Two-factor board PNG review
is complete; regenerate browser PNGs with `make auth-board-pngs` to remove the export-only ghost-row
corruption. Focused AuthSnapshotGuardTests/AuthSessionTests/AuthAuditTests remain available for
diagnosis. Do not re-record to hide a guard, audit or comparison failure. Code none/attempts/server
and Sign in references have no intentional changes. No snapshot PNG is changed in this round.

Pending device-only checks: real AuthenticationServices passkeys require the confirmed Apple
team/bundle IDs (OQ 4), a team-signed DeviceSigned build, public HTTPS AASA and Apple CDN delivery;
the backend branch is not deployed. Mock assertions do not prove a real credential. Hardware
protection/locked-device behavior, VoiceOver and physical launch/status-bar/120 Hz/performance
proof remain in the original Phase 6–8/OQ 14 gates. Password-policy/reset/verification and real email
entry remain blocked/deferred under OQ 21/22/25/27 in their named later phases.

## Fix round 1 (historical; subtitle policy superseded below)

The user's 17e check and targeted rerun pass all suites except the recovery-session scroll query
and strict subtitle contrast audit. Pushed screens now have distinct scroll identifiers; shared
back queries use the current screen, and all auth reveal/keyboard helpers use the live window
safe-area rectangle, with the visible keyboard removed. Hosted guards use fixture insets, check
ink inside each revealed element and include the measured passkey button. Snapshot PNGs remain
unchanged. The hosted subtitle measurement covers the exact audit fixture and the board; the
per-line measurements and outstanding audit discrepancy are documented in
[auth-subtitle-contrast.md](auth-subtitle-contrast.md). Measured saved failure crops exceed 4.5:1;
no new board-design Open question or audit exemption is supported by those pixels.

The route diagnostic now reports cache and completed sync status separately. Online preparation
requires `cached:idle`; the offline relaunch requires `cached:failed-offline` from a real
`SessionSync.refreshNow()` result, in a fresh process. A cached `synced_at` alone cannot pass.
Hosted DataSourceFactoryHostedTests injects the same launch environment into both AppServices
factories and checks that only the offline flag produces DataFailure.offline from the mock.
This remains Debug-only diagnostic data, without a new visible UI or a Release flag.

Duo selects geometry, launch/Welcome hand-off, both auth keyboard suites and Sign in/Two-factor
UI only. No profiles, acceptance audit/session matrix, storage/service tests or Release readiness
are repeated there. Each test run is bounded at 600 seconds for `make duo` (1,200 otherwise,
overridable with `TEST_RUN_TIMEOUT`); timeout terminates xcodebuild's process group and fails the
destination without proceeding to another pass. Other check tiers retain their previous selection,
with the added hosted contrast diagnostic on 17e. Task 2 stays open for execution, the strict audit
discrepancy and the existing Two-factor visual review.

## Fix round 2

User decision 2026-11-07 adds the measured subtitle exception above. AuthAuditTests measures the
actual screenshot within each eligible issue handler and fails closed. Shared host mutations and
hosted subtitle diagnostics require ink from every visible line. No committed PNG changed.
The saved Duo mode-toggle recording and synthesized-event attachments establish a helper error:
all twelve `scroll.swipeUp()` gestures start at **(233, 439)** while the keyboard begins at **y=414**.
They touch the keyboard instead of the form. The current scroll element exposes full-window bounds;
its default swipe coordinates are unsuitable while the keyboard is visible. There is no evidence
of a short app bottom inset, so app padding/layout remain unchanged.

AuthUIFlow now waits for stable keyboard/scroll/target frames, then derives a bounded drag from the
live keyboard-safe viewport and target overflow. Both endpoints stay inside that viewport, including
Duo's side rail; final assertions retain full containment and hittability and now report the bounds.
Portable host tests pin the recorded Duo failure and upward/downward drags in short/asymmetric
viewports. TwoFactorLayoutTests adds Duo/SE fixtures with keyboard-height safe-area bottom insets
(Duo: visible intersection 678−414 = 264; SE: 218), en/nl, default/xxLarge and both modes. It asserts
sufficient maximum scroll offset and full last-control clearance with the generated field gap.
These inset fixtures prove content reachability without a real keyboard; the actual number-pad
focus/toggle interaction still needs the user's runtime run.

`make quick`, generation and direct Swift 6 iOS 17 compilation pass. No revised simulator pass is
claimed: CoreSimulator access is denied here. Pending: `make check` (including the new hosted test
and measured audit), `make duo`, and the existing Two-factor side-by-side board comparison.
Task 2 stays unticked because visual review also remains. Committed snapshot PNGs are untouched.

## Fix round 3 — test fidelity

Contrast now samples clean pixels inside each line and uses its worst background. A substantial
near-token ink fraction is required, so one opaque pixel cannot hide mostly dimmed text. The hosted
sky guard compares the subtitle's columns to the matching x/y pixels in its full-window reference.
The measured subtitle exception remains conditional on ≥ 4.5:1; unavailable measurements fail.
Portable fixtures cover local bright patches, missing backgrounds, partial dimming and antialiasing.

The Duo gesture regression now uses the same extracted viewport calculation as AuthUIFlow, with
window, safe area, scroll and visible keyboard inputs. It rejects the recorded (233, 439) start,
checks the no-keyboard case and moves the keyboard edge to verify the gesture follows it.

The runner forwards SIGINT/SIGTERM to all active test process groups, polls cancellation in worker
threads and kills unresponsive descendants after a one-second grace. The per-run timeout remains.
A real-subprocess fixture checks both signals against two simultaneous groups and their descendants,
including processes that ignore the forwarded signal; exit must occur within four seconds.

Validation: `make quick` passes; no committed snapshot PNG changes. Only the user's updated
simulator reruns and the separate Two-factor side-by-side board review remain for task 2.

## Fix round 4 — Two-factor board review

The user's seven-state side-by-side review is recorded in
[`_design/frames/README.md`](../_design/frames/README.md). Code none/attempts/server and recovery
attempts are acceptable adaptations. The red Field error border, 44-point controls/card shift,
empty native inputs and plain sky remain accepted.

Only the exact plain “The authentication code was not accepted. Try again.” key on the displayed
Two-factor `code` field maps to the board's 30-second/newest-code copy, in English and Dutch.
Raw typed failures remain unchanged. Required-input and recovery errors keep their existing mappings;
no expiry screen or message is invented. The current API and mock return this same generic rejection
for expired/exhausted code challenges, so those indistinguishable responses receive the same board
copy. Other backend keys retain their previous policy.

The recovery placeholder comes from the Auth String Catalog (`xxxx-xxxx` in en/nl,
`shouldTranslate: false`) and uses the generated `mutedForeground` token in both appearances.
The native input explicitly exposes entered text as its accessibility value, keeping an empty value
when the placeholder is shown and preserving the localized Recovery code label. Model/mapping tests
cover copy/localization, recovery errors and expired/exhausted generic responses. Hosted checks cover
placeholder/error/mode transitions in both languages/appearances; the UI flow checks empty/entered
accessibility values and the label separately from the placeholder. These UIKit checks await reruns.

The exporter strips inert event attributes before interpolation, fixing the raw function/template
leak in the ghost toggle. All 14 Two-factor HTML exports are regenerated and parse with clean
toggle labels/recovery placeholders and no event/template leakage. `make quick` passes. Direct
Swift 6 iOS 17 simulator compilation passes for the changed DesignSystem/Auth modules and hosted/UI
tests (`build/phase-10b-round4-typecheck.log`); this does not execute UIKit. The quick log is
`build/phase-10b-round4-quick.log`. No native reference PNG changed. Task 2's implementation/report is complete under the user's
instruction; their 17e recording/comparison and updated `make check` / `make duo` remain before push.
