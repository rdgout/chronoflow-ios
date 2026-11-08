# Phase 17e: Settings home and sign-out

The Settings tab now shows the board account card, sync line, local readiness and
credit values, Settings links and Sign out. Destination links push the existing
Debug diagnostic and are hidden in Release; the Release account card is informational.
The native List, navigation stack and sheet own their safe-area/chrome behavior.
The sheet measures its content for the initial native detent and scrolls at the
system maximum; its pending items use the RN small category-swatch size.
Typography, colors and spacing use generated tokens. The root Dynamic Type cap is unchanged.

The four boards are copied byte-for-byte from RN commit
`e24872afd47ff671fbbab315665920f2805054df`. Import date and SHA-256 digests are in
`_design/canvas/rn-canvas.json`. Dutch catalog values use the exact RN English keys.

The sign-out model calls the existing session controller with a captured session.
It observes outbox changes and mirrors RN grouping: one displayed change per
settings section (and optional RN subsection), and the latest check-off per step,
independent of plan hash. The sheet title counts displayed changes. Native sleep
patches use their habitual-bed/wake keys in place of RN's bodyClockSection metadata.
All other changes keep RN's generic pending sentence. An empty queue dismisses the
sheet. Stay keeps the session; explicit Discard uses the existing D25 wipe and
publication to sign-in. Stale models cannot discard another session.

RN's toast failure behavior has no supplied board. The model retains failures for
retry without adding a new error surface. Notifications, Settings destination
editors and billing remain outside this task.

## Verification in this workspace

- `make lint`: passes.
- `sh Scripts/swiftpm.sh test ChronoFlowKit --skip realRedirectCookieHandlingIsDisabled`:
  all 453 Swift Testing tests and 6 XCTest cases pass, including 11 Settings tests.
  Only the known sandbox loopback-socket test is excluded (previously EPERM).
- `make token-tests asset-tests launch-resources-check`: all 17 generator tests and
  98 resource/runner fixtures pass, including all 76 runner fixtures.
- Direct Swift iOS 17 module compilation/type-checking passes for DataAccess, Settings, Sync,
  the app, AppTests and AppUITests, using the installed SDK and existing dependency
  modules. This verifies compilation, not linking or runtime behavior.
- No xcodebuild or simulator command was run. No snapshot references were recorded.

## Simulator acceptance for the user

Generate the project, record only the new references, review them, then compare:

```sh
make generate
SNAPSHOT_RECORD=1 make targeted DEVICES="17e" ONLY="AppTests/SettingsSnapshotTests"
make targeted DEVICES="17e" ONLY="AppTests/SettingsSnapshotTests AppUITests/SettingsTests AppUITests/AppTabsTests"
```

Settings snapshots include all seven profiles inside that one simulator, both
languages and appearances and both Large/xxLarge sizes. The profile host renders
SettingsHomeContent directly, with its drawn localized title and plain row labels,
and SignOutPendingContent. The first follow-up still hosted SettingsHomeView's
sheet modifier and navigation links/style, and SignOutPendingSheet's presentation
modifiers. Those now live only in the production wrappers; captures instantiate
no navigation links, navigation containers or presentation modifiers. Those hosted
transitions failed during teardown with
`InvalidTransition { phase: idle, targetPhase: failed(deinit) }`. Native tab and
presentation behavior belongs to the UI journeys. Required accessibility content,
visible ink and profile dimensions are checked before writing a reference; a blank
host is rejected even in record mode. Content checks reject horizontal overflow
into the Duo rail. The pending fixture is the board's check-off plus a
usual-sleep-times edit; the home fixture shows the board's two-minute sync age and local credit/readiness
badges.

The pending UI journey uses `CF_SETTINGS_TEST_PENDING=1`, behind the existing
UUID-scoped Auth UI test gate. The original seed selected the oldest trip, which
has a plan hash but no cached detail because it is completed. The optional read
then silently returned without enqueueing. The seed now waits for a successful
initial pull, scans for a cached actionable step, enqueues with the session permit,
and checks that its row remains. Seeding errors are surfaced as Debug assertions.
The UI test waits for the actual one-pending-change sync label before signing out.

Mock mutation sends persistently return offline in this scenario, including for
the next account, while reads and authentication remain usable. Sync keeps running;
real sign-out flush attempts retain the queue, and flushing cannot hide leaked
rows in the next account. A host regression uses the actual mock seed, FullPull,
local enqueue, OutboxFlusher and Settings model to verify both online success and
two offline confirmation attempts through Stay and Discard. Existing wipe coverage
also checks the deleted account directory and absence of old trips/settings/outbox.

The second account is the seeded `twofactor@example.com`, using password
`password` and challenge code `123456`; the mock deliberately returns a two-factor
challenge for it. Sign-out preserves the previous email in the sign-in model.
AuthUIFlow.signIn now deletes that retained value before entering the next email
and asserts the replacement, preventing `demo@example.comtwofactor@example.com`.
The journey reveals the code field and stops with a useful failure if no challenge
appears before proceeding to Today and the second account's Settings.

The normal commit gate remains `make check` outside this sandbox. Neither `make
matrix` nor `make duo` is required for this task.

## Patch delivery

Failure follow-up based on `25f52be`: `build/commits/1.patch` stabilizes the Settings
profile captures; `2.patch` fixes the pending seed and offline mutation scenario.
Each patch ticks its follow-up task in `plan.md`. `messages.txt` contains the
matching Conventional Commit subjects in order. Apply the patches in that order.
