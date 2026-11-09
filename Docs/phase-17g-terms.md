# Terms update

Phase 17g replaces the `.terms` seam with TermsUpdate and TermsFailed. The gate
order remains verify, terms, walkthrough, app. Accept writes the displayed current
version, acceptance timestamp and existing `settings:policies` outbox row in one
SQLite transaction, guarded by the active session's mutation permit. The observed
gate advances immediately, including offline. Repeated taps retain one row per
version. Sync still uses the existing `POST terms/acceptance` contract with
`accepted: true` and `version`.

Pending acceptance survives database reopening, login/session upserts, identity
and full pulls. Incoming policy versions continue updating while an acceptance
is pending; only the locally accepted version/time are overlaid. A genuinely
newer version therefore asks for acceptance again. A stale screen cannot accept
a version that changed before its transaction. Existing sync retry, refusal and
unauthorized-session rules still apply to this required policy mutation.

TermsDestination mounts on the designed background, retries session/database/
permit discovery, and observes policies from SQLite. The screen scrolls using
the window and all four safe-area insets, with the existing root type cap.
Terms-specific board values are generated from TermsUpdate; the brand asset is
generated from the supplied icon master. Both appearances use generated colors.
Sign out reuses SettingsHomeModel and the 17e SignOutPending sheet, including
Stay and explicit discard. Screen identifiers contain their accessible children.

## Board interpretation

- TermsFailed describes saving failure and offers Retry, reading and Sign out;
  it does not require synchronous server confirmation. RN also saves locally.
  The failure banner therefore represents a failed local transaction. A network
  outage after a successful local save leaves the acceptance queued and lets
  the user continue.
- The 1 Nov note keeps legal placeholders until legal supplies per-version
  effective dates and summaries. The current web `PolicyVersionsView` has only
  four version/acceptance fields. This screen retains the drawn placeholders,
  with paired Dutch catalog entries, rather than using RN's generic summary as
  an invented version changelog. Backend metadata support and final legal copy
  are deferred; no guessed payload fields or effective date are introduced.
- The board links PolicyReader, but that board is absent from this local export.
  The system browser opens `https://chronoflow.net/terms`, matching RN's combined
  terms/privacy link. An in-app legal reader is deferred.
- The footer uses RN's customer-facing “Your trips stay saved if you sign out.”
  The board's preceding description of onboarding order is treated as an
  annotation. All existing RN strings retain their RN Dutch translations.

## Verification

Host coverage includes gate order and both next destinations; acceptance and
failed sends offline; later delivery; pending-row relaunch, session upsert and
stale full-pull protection; newer versions and stale-screen refusal; rollback
when inserting the outbox row fails and a successful Retry; revoked session
permits; sign-out confirmation; paired copy and the D1c device table, including
asymmetric side insets.

The UI suite uses UUID-scoped mock accounts with unaccepted policies and mutation
sends held offline. It covers acceptance into walkthrough, offline relaunch both
before and after completing walkthrough, Dutch xxLarge acceptance into Today,
plain sign-out, and pending-change Stay/Discard. `CF_AUTH_TEST_TERMS_PENDING` seeds
both accounts with unaccepted policies. `CF_AUTH_TEST_TERMS_CHANGES_PENDING` adds
one preference edit for the confirmation journey; all overrides require the
existing UUID-scoped auth-test configuration.

No simulator, snapshot suite or device matrix is run in this task. Execute the
new UI journeys later on 17e:

```sh
make generate
make targeted DEVICES="17e" ONLY="AppUITests/TermsTests"
```

Validation:

- `make lint` passes. All eight new Terms host tests pass, including both
  parameterized next destinations. The full run passes 520/521 Swift Testing
  cases; the sole remaining failure is the existing
  `APICookieTests.realRedirectCookieHandlingIsDisabled` loopback-listener EPERM.
- `make quick` was run. Its full parallel host run also exceeded the existing
  three timeline timing limits. All three pass when executed in isolation after
  compilation, and the remaining nine XCTest cases pass. No budgets were changed.
- The remaining quick tiers pass separately: 17 TokenGen/AssetGen tests and 100
  resource/signing/generator/runner fixtures. TokenGen and AssetGen `--check`
  verify all 54/50 generated outputs. One initial runner-concurrency fixture
  timing failure passes on both subsequent full runner runs.
- Direct compilation against `arm64-apple-ios17.0-simulator` passes for the
  package modules, Debug/Release app and all UI test sources. This runs the
  compiler only. Runtime/visual acceptance of the new UI suite remains deferred.

Logs: `build/terms-lint.log`, `terms-quick-final.log`, `terms-focused.log`,
`terms-timeline-isolated.log`, `terms-remaining-quick.log`, `terms-token-check.log`,
`terms-asset-check.log`, and `terms-app-ios.log`, all under `build/`.

## Delivery

`build/commits/1.patch` and `messages.txt` contain one atomic Conventional Commit
based on `d92ff91` (`fix/auth-error-banners`). The worktree's Git metadata is
read-only, so the commit is assembled in an isolated packaging repository.
Shared-file edits are limited to the 17g plan section plus the requested Context
exclusion change, a separate Terms String Catalog, and the new runner entries.
