# Auth acceptance gate — Phase 10b, task 2 (7 November 2026)

Implementation and Mac verification are complete. **Acceptance remains open** for the user's
simulator runs and Two-factor board review. No simulator, xcodebuild, physical device or live API
was used for this task. Phases 6–8 remain open; this gate does not close their accessibility,
performance or physical-device requirements. Phase 10b task 2 remains unticked until the pending
checks below have supplied results.

Matrix A means all seven D1c profiles in Mac geometry tests and hosted captures inside **one 17e**,
plus 17e keyboard/routing/accessibility UI tests. It does not request seven simulator runtimes.
`make duo` is the opt-in runtime spot check. The full/compact profile split remains unchanged.

| Board / state | Native checks | Evidence / remaining acceptance |
| --- | --- | --- |
| AuthSignIn none / wrong→credentials / locked / server, light/dark | Generated tokens, native controls, layout, strict text ratios, 896 profile/board references and AX5 equality | User's Phase 10a results and eight-pair visual acceptance pass (8e2d542; `_design/frames/README.md`). Compare again with the new capture guard. |
| AuthTwoFactor code none / field error / attempts / server, light/dark | Shared controls, max-six oneTimeCode, number-pad submit, field/banner mapping, profile captures | User's task-1 hosted comparisons pass; 1,792 code/recovery references committed at 0e92b6a. New guard/audit/session runs and side-by-side board review remain open. |
| AuthTwoFactor recovery none / attempts / server, light/dark | Mode toggle, hint, recovery Return, consumed-code mock/model checks, profile captures | Same task-1 evidence; review the recovery board exports and run the extended suites. Recovery field-error snapshots use the designed shared Field error treatment and approved backend copy; there is no separate recovery-error board. |
| AuthStates / Field / Button | Designed banners, native input/button states, touch targets, color/typography/shadow guards | Previously accepted shared controls; no new visual state, copy or token value in task 2. |

The earlier minimized-keyboard results were withdrawn. OQ 32 was subsequently **settled** at
9505993: the user supplied visible-keyboard passes on 17e, SE and Duo for SignInKeyboardTests,
TwoFactorKeyboardTests, TwoFactorTests and SignInTests (plan.md records the correction/results).
The runner still writes `AutomaticMinimizationEnabled=false` on each booted destination before
any UI pass, including check, Duo, targeted/reused builds and Perf. Helpers require stable keyboard
frames with at least 100 × 100 points intersecting the window, focused-input/submit containment
above the keyboard and hittability. The new tree still needs the user's check/Duo runs.

Auth captures now reject a wrong-size/scale raster, transparent pixels, missing measurements,
horizontal clipping and vertically clipped brand/heading. Brand and heading must contain rendered
ink: a sky gradient alone cannot pass the blank guard. Validation happens before comparison or
recording, including AX5 equality captures. Mac mutation tests cover missing/clipped/blank/gradient/
transparent captures and recording without writes on failure. Deliberately scrollable content may
extend below the initial viewport; AuthSnapshotGuardTests scrolls every Sign in and Two-factor
control fully into view on the board/all seven profiles and an extra four-inset Duo fixture,
en/nl, light/dark, default/xxLarge. These hosted scroll checks await execution. Captures retain each
profile's own scale and four insets, including Duo's side rail. No references were changed.

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
  cannot inspect files. Both hosted and UI execution are pending for this tree.

Each new session/audit launch uses a UUID-specific file-backed fake server/account root and Keychain service, retained
across relaunch. It uses the shared Debug mock scenario values from e6623a3, with verification and
walkthrough flags applied to the same seed for gate coverage. Default demo behavior stays unchanged.
Debug-only `CF_AUTH_TEST_ID` enables this isolation; `CF_AUTH_TEST_OFFLINE`,
`CF_AUTH_TEST_UNVERIFIED` and `CF_AUTH_TEST_WALKTHROUGH_SEEN` only apply within that namespace.
Offline state is installed in the mock constructor, before its first request. The existing route
text exposes only a `cached` readiness diagnostic and the test-only tap; no token, account data or
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

Only `(sign-in.guest, .contrast)` is allow-listed (OQ 33). Nil/prefix/other identifiers, combined
issue types and every Two-factor control still fail. Generated/native guards retain the accepted
border/guest-pill values and strict WCAG text contrast. The exemption adds no text-ratio waiver.
At the board footer centre, text/pill remains 14.9260:1 light / 15.0953:1 dark, with its 90% opacity;
the guest boundary/pill contrast acceptance is recorded in OQ 33.

Mac verification: `make quick`, runner selection/failure/skip/record-isolation fixtures, capture
mutation tests and mock scenario/offline/persistence tests pass. `make generate` includes the new UI
files through the AppUITests directory glob and compiles the shared scenario-values source into
that target. Direct Swift 6 iOS 17 Debug/Release app/module/SIL and hosted/UI test compilation is
checked without xcodebuild; compilation is not UIKit execution. Exact results/commands are in
Docs/tooling.md, Phase 10b task 2.

Pending simulator acceptance: `make check`; the explicitly requested opt-in `make duo`; focused
AuthSnapshotGuardTests/AuthSessionTests/AuthAuditTests if diagnosis is needed; and comparison of the
existing references against the Two-factor board PNG exports (`make auth-board-pngs`). This sandbox
has the Sign in board PNGs but no Two-factor browser PNG exports, so their side-by-side review is
still open. Do not re-record to hide a guard, audit or comparison failure. Record only intentional,
reviewed changes, serially on 17e, then compare in a fresh process.

Pending device-only checks: real AuthenticationServices passkeys require the confirmed Apple
team/bundle IDs (OQ 4), a team-signed DeviceSigned build, public HTTPS AASA and Apple CDN delivery;
the backend branch is not deployed. Mock assertions do not prove a real credential. Hardware
protection/locked-device behavior, VoiceOver and physical launch/status-bar/120 Hz/performance
proof remain in the original Phase 6–8/OQ 14 gates. Password-policy/reset/verification and real email
entry remain blocked/deferred under OQ 21/22/25/27 in their named later phases.
