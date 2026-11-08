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
- `make package-tests`: the known loopback-socket test
  `APICookieTests.realRedirectCookieHandlingIsDisabled` fails with sandbox EPERM.
- `sh Scripts/swiftpm.sh test ChronoFlowKit --skip realRedirectCookieHandlingIsDisabled`:
  all 452 other host tests pass, including 10 new Settings tests.
- `python3 -I Tests/test_launch_simulators.py`: all 76 runner fixtures pass.
- Direct Swift iOS 17 module compilation/type-checking passes for Settings, Sync,
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
SettingsHomeView directly, with its drawn localized title, and SignOutPendingSheet
as content. There is no TabView, NavigationStack or live sheet transition in this
suite: those hosted transitions failed during teardown with
`InvalidTransition { phase: idle, targetPhase: failed(deinit) }`. Native tab and
presentation behavior belongs to the UI journeys. Required accessibility content,
visible ink and profile dimensions are checked before writing a reference; a blank
host is rejected even in record mode. Content checks reject horizontal overflow
into the Duo rail. The pending fixture is the board's check-off plus a
usual-sleep-times edit; the home fixture shows the board's two-minute sync age and local credit/readiness
badges.

The pending UI journey uses `CF_SETTINGS_TEST_PENDING=1`, behind the existing
UUID-scoped Auth UI test gate. It waits for the initial pull, stops sync and queues
one real plan check-off so both confirmation attempts retain it. The second
account is pulled and sync is stopped again before checking sign-out, so sync
cannot conceal leaked outbox rows. The host integration test independently checks
that the previous account directory is removed and the next account has no trips,
old settings or outbox rows.

The normal commit gate remains `make check` outside this sandbox. Neither `make
matrix` nor `make duo` is required for this task.

## Patch delivery

The worktree's Git directory is outside writable roots; creating its `index.lock`
returns Operation not permitted. `build/commits/1.patch` imports the boards and
ticks that task; `2.patch` implements Settings and sign-out and ticks their tasks.
`messages.txt` contains the matching Conventional Commit subjects in order.
