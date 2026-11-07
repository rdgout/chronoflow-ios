# Phase 10a auth gate — 6 November 2026

Implementation was originally stacked early on Phase 9b by user direction; this port integrates
Phase 9a–9d, the test tiers and recorded Launch/Welcome references.
The first task stays unticked for browser PNG/visual acceptance and hosted checks;
password and passkey implementation tasks are ticked with their remaining acceptance limits.

Auth uses native TextField/SecureField, Buttons and ProgressView, generated board typography,
semantic Any/Dark colors, OKLab error mix, soft card shadow and template board SVG glyphs.
The shell scrolls in the keyboard-safe viewport with all four insets. Touch surfaces grow to 44 points,
footer to 48, and text grows through the existing root xxLarge cap. No patterns or explicit glass API
are added. Auth geometry and keyboard reveal use measured frames, with a pure overflow result;
there is no invented pinned action if a field/submit pair does not fit (OQ 32).

OQ 32 correction (7 November 2026, Phase 10b fix round 3): the user verified that headless
simulators had hardware keyboards attached and `AutomaticMinimizationEnabled = 1`. The software
keyboard was minimized despite `app.keyboards.firstMatch.exists`. Duo's reported keyboard
`(0, 722, 466, 245)` below window/scroll `(0, 0, 466, 678)` is not evidence of a real visible
Duo keyboard layout. The b56c328 whole-window fallback is removed. Shared helpers now require
stable keyboard frames with at least 100 × 100 points intersecting the app window, then clip
the scroll/window viewport above the keyboard and check focus, full input/submit containment and
hittability. The runner disables automatic minimization per device after boot. Earlier SE/Duo
passes do not establish keyboard acceptance: **OQ 32 is reopened for Sign in**, pending the user's
SignInKeyboardTests, TwoFactorKeyboardTests and TwoFactorTests reruns on 17e, SE and Duo.
The user's SE experiment with minimization disabled passed `testDutchCodeServerAtXXLarge` with
a visible number pad. That single case does not settle the full acceptance gate.

AuthSessionServices reuses the scene’s NativeSessionController. Its one SessionController accepts
sessions, restores credentials, owns sync and signs out/wipes. Post-accept routing reads the SQLite
readiness gate: verify through AppDelegate.verificationRequired, then current terms, walkthrough,
and today. Hosted integration tests cover acceptance, gate precedence, restore and sign-out.
Forgot, Sign up and Two-factor are memory navigation seams with Debug diagnostics; their UI belongs to later phases. Today and verify retain the existing root seams.
Release remains non-shipping while these destinations are unbuilt. Navigation does not replay launch.

Assumed defaults, not settled questions:

- **OQ 23:** no offline banner or disabled-offline submit. Typed failures remain tested.
- **OQ 24:** eligible verified success → `.today`; unverified → `.verify`.
- **OQ 30:** hidden/unknown field and passkey credential/challenge errors use the designed generic server
  banner; no hidden-field notice. Returned passkey fields/deadlines remain typed in the form model.

OQ 28 is resolved by the user 2026-11-06: use RN Dutch for an exact English match, otherwise
backend `lang/nl.json` for the exact English key, otherwise write natural Dutch matching RN's
je/jij tone and terminology and the clock-shift copy rule. All 15 pending plan rows now have
source-tagged values. These six shared rows have exact backend values and now ship in the catalog
and displayed-field mapping, with en/nl regressions and the existing hidden-field fallback:

- Use both uppercase and lowercase letters.
- Use at least one letter.
- Use at least one number.
- Use at least one symbol.
- This password has appeared in a data leak. Choose a different password.
- This email verification link is invalid or has expired.

Later-phase Two-factor/Forgot/Reset/Verify translations are recorded in plan.md and ship with their
phases. OQ 21/22/25/27 still block the conflicting password-policy/reset/verification claims.
Numeric field arguments use catalog interpolation. Passkey-specific backend sentences classify failures, with only the approved generic
banner rendered; no new translation is needed for an undisplayed server sentence.

Existing Auth snapshots render none/credentials/locked/server, without these added field messages;
no existing references change or need re-recording in this decision round. Hosted comparison and
native control/layout/UI checks remain for the user; no simulator execution is claimed here.

Real passkeys use AuthenticationServices required user verification and serialize binary bytes as
unpadded base64url, including ID and clientDataJSON. Every retry fetches new options; cancellation
shows no banner. Mock never invokes AuthenticationServices: tests inject named fake-server accounts
and deterministic providers for verified, unverified, 2FA-bypass, cancellation, rejection and challenge
consumption. The app's unseeded mock has a deterministic unavailable provider; it cannot authenticate
a fabricated credential or prefill an account.

Associated domains are configured only for the app target's **DeviceSigned** configuration on iphoneos.
Normal Debug/Release and DeviceSigned simulator builds use no entitlement. The pre-build signing guard
rejects simulator, missing-team, ad-hoc and unsigned overrides if entitlements are requested.
**Open: device-only verification** requires confirmed team/bundle registrations, a team-signed build,
deployed public AASA and Apple CDN delivery. The backend branch is not deployed. Apple references:
[Supporting passkeys](https://developer.apple.com/documentation/authenticationservices/supporting-passkeys/),
[Supporting associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains).

Original early-stack host checks: 185 SwiftPM tests pass (21 Auth, 164 existing), strict formatting passes, 8 TokenGen,
4 AssetGen and 6 font/cache tests pass. Signing guards: 3 Python tests; resource checks: 9 tests;
runner checks: 22 tests. XcodeGen generation passes. SwiftPM builds every package/test target for
arm64 iOS 17 simulator; direct app/hosted/UI compilation checks are documented in tooling.md.
These checks do not execute UIKit or establish accessibility/keyboard/visual acceptance.

Auth hosted snapshots cover the zero-inset 375 × 812 board and all seven D1c profiles in one 17e,
none/wrong/locked/server × en/nl × light/dark using full/compact profile Dynamic Type categories,
plus AX5 equality. Native control and layout checks assert that the synthetic safe-area fixture
actually moves the brand/content. AuthTestHost uses SnapshotContainer with the shared profile device
table, exact four insets (Air top 68, Duo 0/0/0/19), reused windows and Welcome's CPU layer renderer.
The Auth host suites run in quick; controls/layout run as hosted logic, sign-in UI and the serial
device-appearance audit run in check, and snapshots use the profiles policy and SNAPSHOTS.
No Auth snapshot reference was recorded or added by this port.

Standalone board/component HTML exports are in `_design/frames/auth`; browser PNG export is open:
Chrome headless exits 134 in this sandbox. The orchestrator must review geometry/contrast, run the
hosted frame/keyboard/audit checks, record once, then compare. The second fix round allows only
`(sign-in.guest, .contrast)`, a confirmed board pair, following Welcome's explicit-pair policy.
Generated color/alpha/typography/ratio guards fail on drift; every other element/type still fails.
At the board footer centre, text/pill is 14.9260:1 light / 15.0953:1 dark and pill/sky is
2.3128:1 / 2.9450:1, including the 90% pill opacity. Native colors match the board exactly.
Input/outline-button borders, decorative dividers and the guest pill over the sky are accepted,
OQ 33 (user 2026-11-06), exactly as the board/tokens draw them. RN keeps these values; the web's
P8-D16 correction covers WCAG 1.4.3 text contrast only. Token source notes remain “Kept exact,
flagged.” The audit allow-list stays limited to the same pair, and text contrast checks stay strict.
Rendered visual review remains open. Commands are in Docs/tooling.md. No seven-simulator run is required.

Integrated-port verification: make quick passes (286 package host tests including 23 Auth,
10 TokenGen, 4 AssetGen, 3 signing guards, 10 resource checks and 53 runner fixtures).
Generator freshness, all 10 static fonts and 6 font/cache checks pass. All package/test targets
compile for iOS 17 simulator; the app and all hosted AppTests type-check in Debug/Release,
and all AppUITests type-check in Debug. The 16 native acceptance/gate/cancellation/restore/sign-out
scenarios are compiled but await hosted execution. See the integrated-port commands in tooling.md;
no Auth references, simulator results or new acceptance claims are included.
