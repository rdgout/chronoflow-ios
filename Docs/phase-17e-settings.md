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
- `make host-tests`: the known `APICookieTests.realRedirectCookieHandlingIsDisabled`
  loopback listener fails with sandbox `Operation not permitted`; the package suite
  passes when rerun excluding only that test. Generator and resource/runner fixtures pass.
- `sh Scripts/swiftpm.sh test ChronoFlowKit --skip realRedirectCookieHandlingIsDisabled`:
  all 453 Swift Testing tests and 6 XCTest cases pass, including 11 Settings tests.
  Only the known sandbox loopback-socket test is excluded (previously EPERM).
- `make token-tests asset-tests launch-resources-check`: all 17 generator tests and
  98 resource/runner fixtures pass, including all 76 runner fixtures.
- Direct Swift iOS 17 module compilation/type-checking passes for Settings in Debug/Release,
  the app, AppTests and AppUITests, using the installed SDK and existing dependency modules. This verifies compilation, not linking or runtime behavior.
- No xcodebuild or simulator command was run. No snapshot references were recorded.

## Simulator acceptance for the user

Generate the project, record only the new references, review them, then compare:

```sh
make generate
SNAPSHOT_RECORD=1 make targeted DEVICES="17e" ONLY="AppTests/SettingsSnapshotTests"
make targeted DEVICES="17e" ONLY="AppTests/SettingsSnapshotTests AppUITests/SettingsTests AppUITests/AuthSessionTests AppUITests/AppTabsTests"
```

Settings snapshots include all seven profiles inside that one simulator, both
languages and appearances and both Large/xxLarge sizes. The profile host renders
the shared SettingsProfileRow, SettingsSyncRow, SettingsDestinationRow and
SettingsSignOutButton in a ScrollView/VStack, with the board's localized title,
card grouping and generated tokens, plus SignOutPendingContent. Production retains
its native List, navigation and sheet. Captures instantiate no List, navigation
links, navigation containers or presentation modifiers. Native tab and
presentation behavior belongs to the passing UI journeys. Required accessibility content,
visible ink and profile dimensions are checked before writing a reference; a blank
host is rejected even in record mode. Content checks reject horizontal overflow
into the Duo rail. The pending fixture is the board's check-off plus a
usual-sleep-times edit; the home fixture shows the board's two-minute sync age and local credit/readiness
badges.

The third failure investigation read the existing 17e xcresult, including its
legacy ActionTestSummary. The associated error domain is
`Gestures.GesturePhaseQueue<()>.InvalidTransition` (omitting the private context
address). Its captured stack reaches `SnapshotContainer.close()` at
`window.rootViewController = nil`, through AuthTestHost.close and the test's defer.
This identifies a system gesture-queue teardown failure. Removing navigation and
sheet wrappers in the first two follow-ups did not resolve it.

Compared with the passing Today/Trips/TripPage suites, the remaining collection
lifecycle is SettingsHomeContent's List. Today and Trips use ScrollView; Trips even
retains refreshable and NavigationStack. Settings fixtures do not call model.start,
provide a database or start observation tasks. Their captured content has no task,
onAppear, animation, dismiss/openURL action, toolbar or presentation modifier.
The host retains both its controller and its window until close, and root
replacement retains each model through its view. The List is therefore the
remaining suspected trigger, rather than an established runtime bisect result.
The capture now reuses extracted production row components outside List; no row
copy, styling or action is duplicated. A hosted regression requires real content
and rejects UICollectionView/UITableView descendants. The existing blank-content
rejection and all profile variants remain. No simulator was run here; the user
must rerun the two commands above to confirm this workaround and review references.

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

Auth session diagnostics still enter through Settings' Account row. The shared
reveal helper now searches for the target's containing scroll, collection or table
view and accepts all three container types as fallbacks. This covers the native
Settings List, which XCUI exposes as a collection view, while retaining the
keyboard-safe viewport and gesture checks used by auth screens.

The normal commit gate remains `make check` outside this sandbox. Neither `make
matrix` nor `make duo` is required for this task.

## Patch delivery

Third snapshot failure follow-up based on `1a830ca`: `build/commits/1.patch` extracts
the shared production rows and captures them outside List, adds the collection-free
host regression and ticks the follow-up in `plan.md`. `build/commits/messages.txt`
contains its Conventional Commit subject without trailers.
