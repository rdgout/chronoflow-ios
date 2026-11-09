# Auth acceptance gate — Phase 10b, task 2 (7 November 2026)

The user reports `make check` (17e) and `make duo` completely passing at 4a3e3ea. The
Two-factor side-by-side review is complete: code none/attempts/server and recovery attempts are
acceptable adaptations; fix round 4 corrects rejected-code copy and the missing recovery placeholder.
Task 2 is ticked under the user's explicit closeout instruction: only their updated simulator
reruns and intentional reference recording/comparison remain before pushing. No new runtime or
reference-comparison pass is claimed. Fix round 3's strengthened checks also need those reruns.
Phases 6–8 retain their accessibility, performance and physical-device gates.

Matrix A uses the **lean snapshot set, user 2026-11-07**, for every auth screen: every
implemented state on 17e/SE/Duo, en/nl × light/dark at default size, plus one xxLarge reference per
state (17e, en, light). Capture all profiles inside **one 17e**. All seven D1c sizes remain in Mac
geometry and hosted layout/guard tests; keyboard/routing/accessibility UI checks remain on 17e.
AX5 equals xxLarge in one pixel comparison per screen. `make duo` stays opt-in; seven simulator
runtimes run only when asked. Splash/Welcome retain their existing full/compact profile sets.

| Board / state | Native checks | Evidence / remaining acceptance |
| --- | --- | --- |
| AuthSignIn none / wrong→credentials / locked / server, light/dark | Generated tokens, native controls, layout, strict text ratios, 52 lean references and one AX5 equality comparison | User's Phase 10a results and eight-pair visual acceptance pass (8e2d542; `_design/frames/README.md`). Round-1 capture guards and profile comparisons pass. |
| AuthTwoFactor code none / field error / attempts / server, light/dark | Shared controls, max-six oneTimeCode, number-pad submit, field/banner mapping, profile captures | User's task-1 hosted comparisons pass; 104 code/recovery references survive the lean-set pruning (original full set committed at 0e92b6a). Round-1 guards, sessions and profile comparisons pass. Board review accepts none/attempts/server; fieldError copy is corrected in round 4 and needs intentional reference recording/comparison. Revised simulator checks remain the user’s run. |
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

## Phase 11a — Forgot password (2026-11-07)

Forgot now uses the shared AuthScreen, native email field, primary button, measured keyboard reveal,
request lock and catalog. The form calls `requestPasswordReset`; a 204 shows the same sent Notice
for existing and unknown accounts, interpolating the captured submitted address. It opens the
system `message://` URL; no handler leaves the Notice intact. Back returns to Sign in without
replaying launch. `AuthNavigation.forgot(email:)` prefills a fresh form for the future expired-link
entry. There is no client email validation, offline pre-check, session acceptance or inbox UI.

Server field messages stay under Email. Throttling uses AuthStates' “Too many requests.” / link
request body; server/hidden/unknown-field failures use the shared server banner. The kept OQ 23
offline behavior preserves the form and enabled submit without adding an undesigned banner.
Busy edits and duplicate tap/Return are ignored; leaving/cancellation rejects late results.
English and Dutch ship together, following the recorded OQ 28 source order.

The ten Forgot exports cover form/sent/Field error/AuthStates throttle/server in both appearances,
using AuthTwoFactor's Forgot variant and the component bundle. The field error comes from the
shared Field design; offline is visually the unchanged form. `make auth-board-pngs` generated the
HTML but Chrome exited 134 in this sandbox; the PNG export remains for the user's host.

Coverage added: eight portable model tests (including two cancellation cases); hosted native
control/focus/lock, D1c layout and six-state lean snapshots (78 references expected), root-cap equality,
and all-state/asymmetric-safe-area scroll/ink guards; ForgotPasswordTests and en/nl xxLarge
ForgotPasswordKeyboardTests; strict audits of all six states in both languages/appearances/sizes.
The existing subtitle exception remains limited to Sign in/Two-factor and requires a measured
passing minimum. Forgot adds no exception. Runner tiers, strict failure/skip handling, 17e-only
opt-in recording and per-device AutomaticMinimizationEnabled fixtures include the new suites.

`make quick` passes. Direct iOS 17 compilation/typechecking is recorded in
`build/phase-11a-typecheck.log`; it executes no UIKit, simulator or xcodebuild. No native PNG
reference was recorded here. Hosted/UI execution, SE/Duo visible-keyboard checks, reference
recording/comparison and visual board acceptance remain open for the user's exact outputs.
The commands are in `Docs/tooling.md`. Real mail receipt is not simulator acceptance.

OQ 21/22/25/27 and the four trips decisions are recorded in plan.md. Password-rule/copy amendments
ship with 11b/11c, and native reset/verify universal-link entry with 11b/11d. Real link opening also
requires server AASA with the confirmed team/bundle ID; team ID remains pending. Trips follow 11d.

## Phase 11a fix round 2 — lean coverage and bounded captures

The reference contract is 13 captures per state: three profiles × two languages × two appearances
at default size, plus 17e/en/light xxLarge. Exact inventories are **52 Sign in**, **104 Two-factor**
and **78 Forgot**. Obsolete PNGs are removed; surviving PNGs are unchanged. Forgot survivors were
already untracked and remain unaccepted. No references were recorded in this round.

Forgot uniquely snapshots a prefilled native email, whereas Sign in/Two-factor fixtures have empty
inputs. The existing SwiftUI range cap and font-size checks do not constrain every native layout
trait. `ContentSizeCap.apply` now clamps the UIKit root category and observes window preference
changes, shared by production and the hosted harness. The SwiftUI root also normalizes its environment to the concrete capped value; its range cap stays in place.
The SE regression compares form/sent element frames and native email bounds, text rect and font,
so failures identify the element. One SE/en/light AX5/xxLarge pixel comparison remains per screen;
Forgot’s comparison uses its prefilled field-error form.

Each AuthTestHost owns its window/controller; snapshot models use immediate mock requests, and
there is no shared auth host or static raster cache. CoreText registration is process-wide and runs
off the main actor; hosted auth registration now fails after 10 s. Settling replaces the unchecked
main-queue continuation with cancellable 10 ms yields and a 12-capture / 5 s limit. Failures include
the revision and capture context. XCTest’s 600 s per-test watchdog bounds synchronous UIKit/CoreText
stalls; the runner’s existing inactivity and process-group limits remain. Recorded guards/subtitle tests
took 452/506 s individually. The runner observes actual XCTest result-stream growth (and prints
progress on new events), covering buffered parallel stdout without treating timestamps as activity. Combined runtime success
cannot be claimed from this sandbox: CoreSimulator access is denied. Rerun commands are in
`Docs/tooling.md`; visual acceptance stays open.


## Phase 11a fix round 3 — capped input metrics and lean audits

The user's round-2 17e run passes Forgot controls, Auth/Two-factor snapshots, capture guards,
Auth layout and Forgot UI/keyboard tests without hangs. Forgot AX5/native-frame equality and the
oversized contrast/audit methods still fail; their revised simulator acceptance stays open.

Native auth inputs now derive their point size with `Typography.authBody.uiFont(compatibleWith:)`
from the root-capped environment and use a fixed-size SwiftUI custom font. This avoids a second
native scaling pass against the uncapped system preference. The SE regression also checks the
native font name, point size and line height against the field's capped UIKit traits.

Audits and subtitle checks now use five variants per state: en/nl × light/dark at default size,
plus en/light xxLarge. Each screen/Forgot state has a separate method. Every control is revealed;
identical scroll/keyboard positions share one audit or pixel measurement. The 600 s watchdog is
unchanged. Only back-button containment includes the navigation-bar region above the content safe
area, preserving horizontal insets and the visible-keyboard edge. Portable tests cover both keyboard
states with an offset window and asymmetric viewport.

The banner text region excludes generated padding and the glyph column. Its title and body use the
same generated 20-point/subheadline line-height grid, scaled through capped UIKit metrics. Both
hosted and UI tests measure that region with RenderedTextContrast. A missing/incomplete measurement,
non-finite minimum or ratio below 4.5:1 cannot exempt an issue. Only unattributed `.contrast` issues
(nil/empty identifier and nil/empty/ChronoFlow label) in Forgot server/throttle states qualify.
Named controls, named banner issues, other states and other issue types stay strict.

Read-only measurements of all eight default-size 17e server/throttle references give **14.8840:1
light / 12.4197:1 dark**, en/nl, with every text line measurable. Tokens are `cardForeground` and
`authErrorBackground`. These saved-image measurements are diagnostic evidence; the UI exception
requires its own current screenshot. All 78 re-recorded Forgot PNGs are retained unchanged and included
in the fresh patch series. Reference comparison/visual acceptance and new audit timings remain open.

Host verification: `make quick` is blocked only by the existing cookie redirect test's sandbox-denied
loopback listener (`Operation not permitted`). `make -k quick` confirms all other checks pass (333/334 package tests, 10 TokenGen, 4 AssetGen and
88 signing/resource/runner fixtures); details and
rerun commands are in Docs/tooling.md. No simulator tests are run here.

## Phase 11a fix round 4a — native input height

The user's round-3 AuthSubtitleContrastTests and ForgotPasswordControlTests pass. The SE native
email frame/text rect still differs by one pixel at AX5 (24.5 pt tall at y 474) versus xxLarge
(25 pt tall at y 473.5), despite identical capped font metrics. The fixed-size SwiftUI font alone
does not stabilize UIKit's intrinsic input height.

AuthField now gives the native field an explicit height of `ceil(font.lineHeight * displayScale) /
displayScale` before padding, using the capped UIKit font and the same clamped SwiftUI environment
inside the field. The SE regression pins the existing xxLarge rectangle and includes native category
and resolved-font diagnostics. References are untouched; default-size Sign in/Two-factor comparison
and Forgot AX5 equality still require the user's 17e rerun. Host verification is in Docs/tooling.md.

## Phase 11a fix round 4b — banner attribution in both languages

The user's round-3 Dutch server audits measure **14.8840:1 light / 12.4197:1 dark** but reject the
unattributed banner title because the old exception checks labels. The saved logs also contain the
previously accepted unattributed ChronoFlow wordmark issue. Neither path now checks copy.

The audit captures `auth.banner` and `auth.brand` frames in the current Forgot server/throttle
context. Only `.contrast` issues with finite, nonempty frames inside the banner and either its exact
identifier or a nil/empty identifier can qualify. The existing wordmark exception requires a nil/empty
identifier inside the identified brand frame. Both require the same current screenshot's complete,
finite banner-text minimum ≥ 4.5:1. Missing geometry/measurements, unrelated frames, other named
controls/states and other audit types fail. Diagnostics include issue/banner/brand frames and measured
line minima. This supersedes round 3's copy-based attribution rule; saved ratios never grant an exception.

Policy tests cover banner/title containment, wordmark matching, missing/invalid/overlapping/outside
frames, named-control rejection, wrong states/types and incomplete/non-finite/below-threshold minima.
Host compilation/type-checking passes, and `make -k quick` passes all checks except the known
APICookieTests sandbox listener EPERM. No simulator or reference recording runs here; the Dutch
server and both-language throttle audit reruns remain open. Exact commands are in Docs/tooling.md.

Round 5 (2026-11-08) supersedes round 4a's height pin: the user's 17e run passes Forgot controls and
unchanged default-size Auth/Two-factor references, but SE/en/light still yields native input/text rects
`(48, 474, 279, 24.5)` at AX5 versus `(48, 473.5, 279, 25)` at xxLarge, with the native category capped
to XXL and identical CFFigtree-400 19 pt metrics. This is UIKit's internal one-pixel rounding at @2x;
AuthField returns to natural sizing while retaining the clamped environment and diagnostics. Only the
Forgot AX5/xxLarge native input frame and text rect allow at most `1 / scale` pt per origin/size component;
their pixel comparison excludes only the union of both native input bounds expanded by one device
pixel. Every other pixel and all measured labels, buttons, banners, notices and other elements remain
exact, as do native font metrics. Default-size references remain byte-identical.
## Phases 11b–11d — native recovery acceptance (2026-11-08)

Implemented: Reset form/field/server/throttle/offline, expired editable-email recovery and done;
Sign up with a single native visibility Toggle and inline terms/privacy links; Verify waiting/failed,
resend deadlines/errors and explicit discard. Reset's approved copy promises no session and says other
devices are signed out. The production password policy is server-only; both new-password fields carry
matching iOS passwordRules. AuthField font and height logic is unchanged.

Backend contract was inspected read-only with `git show HEAD:…` at
`841be4bd84fe2136f9c00eb794506812385959db`. Reset is public POST auth/reset-password → 204;
registration is public POST auth/register → an unverified session; resend and signed verify are
bearer-authenticated POST email/verification-notification and email/verify; status uses GET users/me.
URLProtocol fixtures cover the encoded reset token/email and exact signed id/hash/expires/signature
body. Existing API suites cover public bearer exclusion, registration language/device fields and
204 results. Mock server journeys consume recipient/account-scoped mail data with no inbox UI or
external mail/network. Debug auth UI fixture IDs force the mock factory even with an API build setting.

Universal-link input is HTTPS app.chronoflow.net/reset-password/{token}?email=… or
/email/verify/{id}/{hash}?expires=…&signature=… . Native browsing-activity tests cover cold capture and
warm dispatch; malformed recognized links select expired/failed. Signed values are never re-signed.
Unauthenticated verification waits for sign-in. The DeviceSigned entitlement includes applinks and
webcredentials, using the configurable Local.xcconfig team; simulator/mock entry needs neither a team
nor an entitlement. These tests do not prove AASA deployment or physical email-app dispatch.

Verification writes are scoped to account/email/session epoch and share the session controller's
transition queue. The DB transaction checks the stored email and changes only the verified flag.
Older sync drains before the write; the normal sync request and gate route follow it. Delayed
unverified callbacks inspect the stored flag. Explicit discard also carries its captured session.
The maximum server deadline survives users/me's zero delay and foregrounding; no client cooldown is
invented. Failed resend respects the same deadline. Storage failure UI, inbox, toast, email-changed,
guest-claim recovery, terms reader and walkthrough remain outside these boards/phases.

Snapshot coverage is intentionally lean and unrecorded: Reset 8 states/104 references, Sign up 10/130,
Verify 10/130. Each state has en/nl × light/dark at default size on 17e, SE and Duo profiles, plus one
17e en/light xxLarge reference. Control/layout tests include native AutoFill and visibility semantics,
server error focus, all four safe insets and last-action reachability with keyboard insets. Each audit
method handles one state and five appearance/language/type variants, using the existing strict policy
and same-frame subtitle pixel measurement. No new unconditional contrast exceptions are added.
Runtime timing, real keyboard behavior, VoiceOver, board frames and visual acceptance await the user's
simulator run. Existing 78 Forgot references remain byte-identical; the AX5 font/height fix is separate.

Run the suites in Docs/tooling.md. Real AASA/team registration, physical links/passkeys, unbuilt gate
destinations and Phase 6–8 launch acceptance remain open; this work does not claim TestFlight readiness.

### Phases 11b–11d simulator fix round 2 (8 November 2026)

The user recorded 104 Reset, 130 SignUp and 130 Verify references and reports their
compare suites passing. The phase patches include those exact PNGs without rerecording.
The supplied controls/layout/link/session passes remain evidence for the previous build;
this round's changed flows and audits still need the focused simulator rerun below.

Native SwiftUI TextField/SecureField keep `.textContentType(.newPassword)`. SwiftUI exposes
no passwordRules API; the traits probe and unsupported assertions are removed under the
user's OQ 21 decision. The server enforces the full policy. Accessibility identifiers,
labels and hints attach to the input before decorative modifiers; the audit requires one
match for every scheduled identifier.

UI entry declines the system strong-password sheet using `GenerateStrongPasswordButton`
and `xmark`, checking the app and SpringBoard without localized labels. It checks native
field focus before typing and retries at most three times, including before confirmation.
The app's AutoFill traits stay enabled. Audits dismiss the keyboard, settle geometry and
reveal every scheduled control before checking it. Only contrast issues geometrically
inside a scheduled but clipped control wait for that control's visible audit; other issue
types and unrelated frames remain strict. Each distinct scroll position is audited once.

The unattributed wordmark exception now uses every current auth screen's unique
`auth.brand` geometry and rendered wordmark pixels (`skyTitle` over the sky), requiring a
complete finite minimum of at least 4.5:1. It retains the 0.01 pt Float/Double containment
tolerance. Banner pixels cannot exempt a wordmark, and named controls cannot use this
exception. Reset form/done do not expect Back. All 37 audit states keep en/nl × light/dark
plus en/light xxLarge, split into light, Dark and XXLarge test methods with at most two
launches per method. The XCTest 600-second watchdog is unchanged; measured per-method
runtime remains user-host acceptance.

Unbindable malformed verify URLs are ignored across authentication, as required by round
1's account binding. A separate structurally valid but tampered URL for the seeded
unverified demo account is retained until sign-in and produces the failed screen. Failed
Verify audits use that fixture, including an isolated Debug-only mock 429 for failed-state
resend. Sign-up/mail/relaunch and cross-account wipe flows continue through the shared
native AutoFill entry helper. No authentication/link-binding rule is relaxed.

### Phases 11b–11d audit policy fix round 4 (8 November 2026)

The user reports round-3 VerifyEmailTests and AccountRecoveryTests passing on 17e.
The default AuthAuditTests suite takes 1,287 seconds (21.5 minutes), accepted by the
user; the remaining reported failures concern contrast attribution and policy.

The user-approved measured text exception applies across all implemented auth screens,
including the `sign-up.back` footer. That footer requires its exact identifier and
matching button geometry, plus a complete finite rendered minimum ≥ 4.5:1 using
`skyCopy`/`skyCopyBackground`. Subtitle and unattributed wordmark exceptions retain
their identifier/geometry rules and the same minimum. Geometry attribution retains
the existing 0.01 pt Float/Double tolerance; localized copy never identifies an issue.

Each eligible contrast issue captures fresh control frames, labels, viewport and pixels
inside the audit handler. Frames are checked immediately before and after the screenshot;
changed geometry retries at most three times, then fails. Measurement consumes only that
capture's values, with no later element/frame reads or raster reused from an earlier
scroll position. Issue geometry must belong to the measured element. Missing, clipped,
unmeasurable or subthreshold text cannot receive the measured exception. Existing
scheduled-control reveal/defer checks and proactive footer/banner ratio checks remain.

Under the user's WCAG 1.4.3 decision, inactive UI components are exempt from contrast:
ignore only an exact `.contrast` issue whose element reports `isEnabled == false` in
the audit handler. This covers disabled `verify.resend` during countdown/throttle,
including failed verification. An enabled or missing element gets no disabled exception;
clipping, hit-region, trait and combined issue types remain strict. Diagnostics retain
the enabled state and exception decision.

This round uses host verification only. Revised simulator audits remain the user's run;
no updated runtime pass, recording or visual acceptance is claimed.

Host results: `make quick` passes strict lint and the new policy regressions, stopping
only at the known `APICookieTests.realRedirectCookieHandlingIsDisabled` loopback EPERM.
The remaining quick tiers pass separately: 10 TokenGen tests, 4 AssetGen tests and
90 signing/resource/runner fixtures. Static Swift 6 compilation against the iOS 17
simulator target passes for the app, hosted tests and all UI tests without executing a
simulator. Logs: `build/round4-quick.log`, `build/round4-quick-rest.log`,
`build/round4-final-fixtures.log` and `build/round4-typecheck.log` (the final fixture
run includes classification of the new host policy suite).
