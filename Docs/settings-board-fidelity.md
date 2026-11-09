# Settings board fidelity — 2026-11-09

Base: `a8b9ac0`, `feat/phase-19-reminders` (PR #30). Delivery is stacked on that base;
there is no merge or push. The working branch's Git metadata is read-only in this
session, so the atomic commits are assembled in an isolated repository under
`build/` and exported as numbered patches plus `messages.txt`.

The complete verified audit at `chronoflow-ios-handoff/settings-fidelity.json` was
read before implementation. Finding numbers below follow each group's
`confirmed[]` order, starting at 1. The supplied boards and RN/web sources were
read only.

| Group | Findings addressed | Differences retained |
| --- | --- | --- |
| Account | Large title; 22 pt bordered row cards; icon circles, subtitles and destructive trash row; labelled Profile fields; field errors; quiet cloud-off saved status; missing-account heading and working retry. Language findings 9–10 are covered by Preferences below. | Findings 3, 5–6: data/policies and email-change/PasswordPromptEmail stay deferred. Finding 8: the email value is a selectable static field, and the filled save capsule keeps **Save changes** for the supported name-only edit; **Save and send link** would promise the deferred operation. Finding 4's presentation claim conflicts with SetDelete: that board explicitly shows a sheet over Account, which is retained and rebuilt. |
| Body clock | Findings 1–9 and 12–16: 26 pt cards, in-card Fraunces headings, visible pills/chronotype ChoiceCards and hints, time tiles, readiness/progress, missing-answer badges/highlights, bordered drink counters, labelled rating field, board health copy, captions and non-overlapping validation. | Findings 10–11: backend age bands and one combined light-device answer remain. Caffeine sensitivity remains boolean rather than drawing an unpersistable third answer. Readiness follows RN's seven required answers plus invalid sections; the board example counts nine. Unset times are not replaced with invented saved values. Time tiles reflow to one column when two cannot fit. |
| Preferences | All nine findings: appearance pills and eyebrow; category swatches with the hint above their card; two-line icon links; a single Reminders card; warning/info Notices; numbered steps with bold terms; full-width Ask/Settings capsules. Extra saved rows are removed; actual local-save failures stay visible. Language has ChoiceCards, all hints, **Nederlands**, and a floating saved toast. | The native lead-time Picker is explicitly allowed by 19a. Optional-items, Live Activity and practice-mode cards remain excluded by earlier decisions. |
| Security | Findings 1–2 and 4–11: bordered icon rows and status badges; labelled password fields and warning Notice; board mismatch copy; off/setup/on/manage surfaces; fixed white QR tile; inline setup-key Copy; two-column monospaced recovery codes and paired actions; lock hints; floating success toast; shared compact password sheet, spinner, reset alert, error ring/line and combined countdown. The four audited Dutch strings use the board wording. | Finding 3: passkey management stays deferred. Home's Account/Security subtitles now describe only available entries. Live dates and generated secrets/codes come from the account rather than the example values printed on the board. |
| Plan/delete | Findings 1–14: hero card and dawn eyebrow; Notices; inline Cancelled badge; muted date/description; skeleton loading; credits-only loose NoLink text; offline text without an extra retry row; content-sized destructive confirmation and the same password/reset/checking/error/countdown component as Security. | Finding 15: purchase/billing/cancel/resume controls stay deferred. Missing balance uses SetStatesMore's not-loaded state. Missing payment dates use the website instruction without inventing a date. |

## Shared values and native controls

`SettingsPage` uses the same `.large` navigation-title styler as Settings home,
with a ScrollView rather than a Form. Native navigation/scroll insets handle the
top and bottom; the existing four-edge page-safe-area environment supplies the
side rail. Compact sheets measure their actual content for a native height
detent, support scrolling at larger type, and retain the root xxLarge cap.

`Settings.source.json` and TokenGen read missing dimensions and type from the
Settings boards. Card spacing/radii come from generated PlanUITokens. Existing
AuthField/AuthNotice/AuthButton are reused; added button kinds and Notice tone
preserve their existing defaults. Popover/destructive foregrounds come from
tokens.json, warning mixes match the board, and the QR white comes from
Set2FASetup. Shadow-soft reuses the already-generated Auth shadow color and
light/dark geometry; it is the same design-system elevation, despite its name.
No design files, fixed device geometry, compatibility mode or per-view type caps
were added.

Native Toggle, lead-time Picker, time DatePicker, navigation, alert and sharing
retain their system appearance. The prompt explicitly draws a native secure
field; its fill uses the generated secondary surface. These controls and SF
Symbols follow the existing native implementation, while the surrounding cards,
choices, typography, buttons and notices follow the boards.

## Capture aid

`SettingsBoardCaptureTests` is Debug-only. It signs into the isolated mock and
navigates the real destinations in English/Dutch and light/dark. Every attachment
uses `XCUIScreen.main.screenshot()` and a board name plus language/appearance. It
captures Account/Profile/Language, all Body clock groups and readiness variants,
Preferences, Reminders on/ask/blocked/unsupported, Password validation, 2FA
intro/setup/fresh codes/manage/revealed codes, sensitive-action prompts including
wrong/locked/checking/reset alert, Plan variants and the delete confirmation.
Long pages also receive additional scrolled captures.

The few otherwise transient states use Debug-only, UUID-gated mock fixtures:
loading/not-loaded observation, plan/body seed values and delayed/throttled
security calls. No reference images, comparison or recording mode is involved.
Deferred email/data/passkey/purchase boards are intentionally excluded. The shared
Checking and Forgot states use the supported two-factor context; their email
wrapper examples remain deferred. Locked uses deletion, Wrong uses turning off
two-factor, and PasswordPromptNL uses the drawn new-codes/wrong state.

The runner classifies this suite under `capture`, accepts it only through an
explicit selector, and serializes its device-wide appearance changes. Runner
fixtures check both opt-in selection and exclusion from every default mode.
To run later on 17e:

```sh
make generate
make targeted DEVICES="17e" ONLY="AppUITests/SettingsBoardCaptureTests"
```

No simulator, captures, snapshot suite, Duo smoke or seven-device matrix was run
in this session. Runtime visual acceptance, keyboard/compact-sheet fit and UI
journey execution remain pending that run.

## Verification

- `make lint`: passes.
- `make quick`: the expected `APICookieTests.realRedirectCookieHandlingIsDisabled`
  loopback listener fails with sandbox `EPERM`; other package suites pass.
- Focused Settings/Reminders host tests: all 66 tests pass.
- Remaining quick tiers: all 17 token/asset tests and 101 resource/runner fixtures
  pass, including the capture runner policy.
- Direct iOS 17 Debug compiler checks: changed modules, app and all AppUITests
  pass. This includes SettingsPagesTests, SettingsTests, RemindersTests and the
  capture source; it does not claim those UI journeys executed. Direct iOS 17
  Release compilation also passes for every package module and the app.

Logs: `build/settings-fidelity-{lint,quick,settings-tests,remaining-quick,final-ios,release-ios}.log`.
The seven exported patches were applied in order to a fresh isolated index at the
base; their final tree matches the working changes. Each commit has a single
Conventional Commit subject and paired catalogs, with no trailers.
