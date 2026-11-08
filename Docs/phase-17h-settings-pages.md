# Phase 17h: Settings destination pages

Branch `feat/phase-17h-settings-pages`, based on `fix/auth-error-banners` at `d92ff91c`.
The patch series is under `build/commits/`. Apply `1.patch` through `11.patch` in numeric
order; `messages.txt` has the corresponding Conventional Commit subjects.

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
