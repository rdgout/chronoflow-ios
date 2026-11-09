# Phase 17h: Settings destination pages

Branch `feat/phase-17h-settings-pages`, based on `fix/auth-error-banners` at `d92ff91c`.
The original series and first runtime follow-up are applied at `990ae04`.
The repeated-replay fix is `build/commits/1.patch`, based on that commit;
`messages.txt` contains its Conventional Commit subject.

## Built

- Account and Profile display the stored name/email. Name edits validate and commit
  with the existing `profile` outbox row. Pending names survive pulls and session
  restoration. Email stays read-only.
- Body clock contains the five RN groups: About you, Sleep, Caffeine, Light equipment
  and Health. Native menus, steppers and a native time picker validate section edits
  before automatic local saves. Complete section patches preserve incomplete/invalid
  source answers. D24 continues to protect pending local settings from server reads.
- Preferences saves time format and category visibility through the settings outbox.
  Theme and Language are persistent device choices. Walkthrough replay uses 17f's
  replay mode in the existing NavigationStack and returns to Preferences on either
  exit. The UI journey changes a preference again after replay.
- Security supports password changes and two-factor setup, QR/key, confirmation,
  recovery codes, reveal, regeneration and disable. Each protected action asks for
  the current password. The prompt supports wrong passwords, a retry countdown and
  the drawn reset-link confirmation. Successful confirmation retains the returned
  codes even before the subsequent account refresh. Only security status is stored
  in the account database. Secrets stay in memory and clear on departure; Copy uses
  the local expiring clipboard, and Download exports a named text document through
  the system share sheet from an in-memory Transferable.
- Plan & credits displays cached credits, unlimited/subscription information, payment
  status and the Loading, Offline and NoLink states. Refresh uses the existing sync
  path. No purchases, checkout or cancellation actions were added.
- Delete account follows SetDelete: Delete my account opens the password step;
  Keep my account and Cancel send no request. A successful server deletion uses the
  captured session's existing sign-out and local wipe path. Failed password, offline,
  throttle, billing and server responses keep the account available for retry.

All six Settings home destinations are available in Release. Unsupported leaf rows
are omitted. The package uses native Forms/Lists/navigation and generated design
values, paired English/Dutch catalog entries and the existing root Dynamic Type cap.
Screen identifiers use accessibility containment. Initializers/tasks are mounted on
real content or the designed background. The 42 imported non-Wide boards, including
password-prompt states, have SHA-256 provenance at RN `e24872a`.

## Backend support and deferrals

The new contract, API client and mock use the backend's actual mobile routes:

| Action | Method and path under `/api/v1` |
| --- | --- |
| Change password | `PUT account/password` |
| Start two-factor | `POST account/two-factor` |
| Confirm setup | `POST account/two-factor/confirmation` |
| Turn off | `DELETE account/two-factor` |
| Reveal codes | `POST account/two-factor/recovery-codes/reveal` |
| Replace codes | `POST account/two-factor/recovery-codes` |
| Delete account | `DELETE account`, body field `password` |

These actions run online through the active session's sync DataSource and epoch.
They never enter the outbox. The existing public forgot-password route sends reset
links. The three real two-factor 409 messages survive API error mapping.

The following remain deferred:

- Passkey list/add: the mobile API provides authentication options/login only. Web
  management requires a web session. Existing AuthenticationServices sign-in remains
  available; no replacement management API or hand-built passkey UI was invented.
- Your data & policies/download: `GET settings/data.json` requires web session auth;
  there is no bearer-authenticated mobile export route. The `data-export` outbox kind
  stays unsupported. The policy reader belongs to sibling 17g.
- Billing links: no mobile signed-in hand-off endpoint exists. NoLink is shown; there
  are no buy, invoice, payment-method, cancel or resume actions.
- Email changes: the online password-confirmation/email-changed flow is deferred;
  names use the requested outbox and email is displayed read-only.
- Reminders and notification delivery/permissions, purchases, paywall checkout and
  cancellation remain outside this phase. Optional timeline items remain excluded by
  the 5 Nov decision. The offline copy does not promise unbuilt reminder delivery.

## Validation

`make lint` passes. `make quick` was run and fails at the existing sandbox-blocked
`APICookieTests.realRedirectCookieHandlingIsDisabled` loopback listener (`EPERM`).

A complete package run excluding only that listener passes all 540 Swift Testing
tests and the three non-timing XCTest checks. The three existing timeline performance
checks exceeded their limits while compilers were active; their isolated rerun
passes with average times 0.073 s (30 days), 0.145 s (60 days) and 0.028 s (S3), below
0.1/0.2/0.04 s respectively. No timing limits were changed. All 17 token/asset host
tests and 100 runner/resource fixtures pass. Board hashes and paired catalog entries
were checked as well.

Direct iOS 17 compiler checks pass for changed package modules, the app, AppTests and
AppUITests. Settings and the app also compile with Release flags. These checks do not
link or execute an app. No simulator, snapshots or matrix was run.

Logs: `build/settings-{quick,host-final,performance-isolated,remaining-quick,lint-final}.log`,
`build/settings-final-debug-ios.log`, `build/settings-ui-ios.log`,
`build/settings-export-ios.log` and `build/settings-release-ios.log`.

Seven mock UI journeys are authored in `AppUITests/SettingsPagesTests.swift` and
registered alongside the new host suites. They cover Profile save, automatic body
clock save, preference changes/replay, app language, password/two-factor actions,
Plan/NoLink and deletion's Keep/wrong-password/success paths. Runtime and visual
acceptance remain pending under the user's simulator prohibition. To execute later:

```sh
make generate
make targeted DEVICES="17e" ONLY="AppUITests/SettingsPagesTests"
```

## 17e runtime follow-up

- Body clock already committed answers locally and queued settings patches. Its
  Saved feedback was after every question in a lazy Form, outside the accessibility
  tree while editing About you. The checkmark and paired Saved/Opgeslagen copy now
  sit beside each saved group's title, as drawn in SetBodyClock. The UI test queries
  the saved element by its group-specific identifier across accessibility types.
  A host regression selects Night owl through SettingsPagesModel, reopens SQLite
  and checks both the local answer and the pending settings patch.
- Replay uses the same Next/Done implementation as first run. Its test could reuse
  the still-existing Next control before the preceding page update settled. It now
  waits for each page counter and stable control frames, including page three and
  Done, before tapping. The existing replay Skip/Done model regression verifies no
  second walkthrough completion write.
- Two-factor setup already uses a native Form with keyboard avoidance. The reveal
  helper accepted the code field's frame inside the window safe area even when the
  tab bar covered it, leaving no scroll gesture to perform. Reveal now clips to
  native navigation/tab bars as well as the keyboard. The test waits for password
  sheet dismissal, targets the two-factor Form, and checks/reveals the focused field
  again after keyboard frames settle. A host regression reproduces the reported
  y=760.7, height=22 field with and without a keyboard.

Runtime verification of these follow-ups remains pending; no simulator or snapshot
execution was performed during this follow-up.

Follow-up validation: `make lint` passes. `make quick` reports the existing cookie
test's sandbox EPERM and one 60-day timeline timing failure (0.207 s / 0.2 s during
compiler activity). A package rerun excluding only that loopback test passes all
542 Swift Testing tests and all six XCTest checks, including the unchanged timeline
budgets. The remaining quick targets pass all 17 generator tests and 100 fixtures.
Direct iOS 17 compiler checks pass for Settings, the app, AppTests and AppUITests;
final Settings and UI-test edits were rechecked. Logs are
`build/settings-regressions-{lint,quick,host,remaining-quick,ios,ui-ios,final-ios}.log`.

## Repeated replay follow-up (2026-11-09)

The second 17e replay showed page one but its first Next did not advance. Replay's
navigation destination owned an `@State` model initialized with the view. Navigation
reuse could retain that model after Skip, including `completed == true`, which
disabled Next. The counter was already the real uppercase label, `1 OF 3`.

Preferences now creates a new model when Replay is tapped and owns the optional
presentation model. Skip, Done and navigation dismissal clear it. The destination
uses that model directly and its identity resets the walkthrough's view state.
Host regressions exercise the same Preferences actions twice after both Skip and
Done, assert fresh state and every page advance, and check that the saved preference
survives without another write. The UI journey checks the uppercase page counter
and waits for an enabled action before each tap.

Validation: `make lint` passes. `make quick` passes both repeat-replay cases and all
other package checks except the existing cookie-listener sandbox EPERM (543/544
Swift Testing tests and all XCTest checks pass). The remaining quick tiers pass
separately: 17 generator tests and 100 runner/resource fixtures. Direct iOS 17
compilation passes for Settings and AppUITests. No simulator or snapshots were run.
Logs: `build/settings-replay-{lint,quick,remaining-quick,ios}.log`.
