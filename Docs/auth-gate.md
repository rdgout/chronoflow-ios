# Phase 10a auth gate — 6 November 2026

Implementation was originally stacked early on Phase 9b by user direction; this port integrates
Phase 9a–9d, the test tiers and recorded Launch/Welcome references.
The first task stays unticked for missing shared Dutch rows and browser PNG/visual acceptance;
password and passkey implementation tasks are ticked with their remaining acceptance limits.

Auth uses native TextField/SecureField, Buttons and ProgressView, generated board typography,
semantic Any/Dark colors, OKLab error mix, soft card shadow and template board SVG glyphs.
The shell scrolls in the keyboard-safe viewport with all four insets. Touch surfaces grow to 44 points,
footer to 48, and text grows through the existing root xxLarge cap. No patterns or explicit glass API
are added. Auth geometry and keyboard reveal use measured frames, with a pure overflow result;
there is no invented pinned action if a field/submit pair does not fit (OQ 32).

AuthSessionServices reuses the scene’s NativeSessionController. Its one SessionController accepts
sessions, restores credentials, owns sync and signs out/wipes. Post-accept routing reads the SQLite
readiness gate: verify through AppDelegate.verificationRequired, then current terms, walkthrough,
and today. Hosted integration tests cover acceptance, gate precedence, restore and sign-out. Forgot, Sign up and Two-factor are memory navigation seams with
Debug diagnostics; their UI belongs to later phases. Today and verify retain the existing root seams.
Release remains non-shipping while these destinations are unbuilt. Navigation does not replay launch.

Assumed defaults, not settled questions:

- **OQ 23:** no offline banner or disabled-offline submit. Typed failures remain tested.
- **OQ 24:** eligible verified success → `.today`; unverified → `.verify`.
- **OQ 28:** exact approved en/nl only. No machine translation, pending row or arbitrary server English.
- **OQ 30:** hidden/unknown field and passkey credential/challenge errors use the designed generic server
  banner; no hidden-field notice. Returned passkey fields/deadlines remain typed in the form model.

Shared Dutch rows still missing, omitted from the catalog and left open in the first task:

- Use both uppercase and lowercase letters.
- Use at least one letter.
- Use at least one number.
- Use at least one symbol.
- This password has appeared in a data leak. Choose a different password.
- This email verification link is invalid or has expired.

Later-phase Two-factor/Forgot/Reset/Verify prose remains blocked exactly as listed in plan.md.
Every introduced product string has its exact RN Dutch value; numeric field arguments use catalog
interpolation. Passkey-specific backend sentences classify failures, with only the approved generic
banner rendered; no new translation is needed for an undisplayed server sentence.

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
hosted frame/keyboard/audit checks, record once, then compare. There are no inherited auth contrast
exceptions. Token tests confirm the card/banner/action text pairs pass 4.5:1; the designed input
border remains below 3:1 in both appearances and needs design review. Commands are in
Docs/tooling.md. No seven-simulator run is required.
