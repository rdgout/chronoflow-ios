# Plan: native iOS ChronoFlow — launch, Welcome, authentication and offline store

## Context

ChronoFlow plans sleep, light and caffeine for each trip. Two apps exist, both read-only from here: the web app `/Users/rickgout/Sites/chronoflow-new` (product source of truth) and the Expo / React Native app `/Users/rickgout/Sites/chronoflow-mobile` (not feature complete). This plan builds the native iOS app in `/Users/rickgout/Sites/chronoflow-ios`; phases 0–5 establish launch and Welcome, and the 2026-11-06 extension plans authentication and an offline account store.

**Where the RN launch loses time** (read from code; never timed, `docs/plan-gate.md` perf items are open):
- The overlay starts only after Hermes loads the bundle, all imports run and React commits; startup parses ~190 KB of en/nl JSON.
- Fonts load at runtime (not embedded); the wordmark and status wait for them.
- Readiness is a sequential JS chain: SecureStore read → SQLite open → migrations → sync and reminder scheduling (twice) → live queries.
- Every hand-off point (1.5 / 2 / 2.3 / 8 s) is a JS `setTimeout`, so JS stalls push the hand-off later.
- Five full-screen SVG layers in the overlay; Welcome draws `SkyBackground` twice; per-frame bezier allocation in worklets.
- The moon landing depends on JS layout (`measureInWindow`), with a fixed fallback offset.

**This plan covers:** the system launch screen; animated splash and readiness; Welcome and its intro/moon landing; sign-in and two-factor; password recovery, account creation and email verification; a GRDB account store, mock and real API data sources, sessions and offline sync; English/Dutch, both appearances and accessibility. **Phases 6–8 stay in place and run later for the splash/Welcome slice**: the existing audit, RN comparison and launch verification are not auth acceptance. Phases 9–11 have their own tests and matrix gates.

**It deliberately does not cover:** the guest wizard, Today UI (boards exist; only the `.today` route seam is used), terms/walkthrough UI, notifications, production email deep-link delivery/universal links (server-side deferred; reset/verify input seams are covered), guest-draft recovery (OQ 17), email-change Settings flow, an in-app appearance setting, RN user migration (OQ 9), or Android. **Still not shippable to TestFlight:** unresolved auth copy/design/link OQs and unbuilt destinations must be settled first. Phase 4's Release signed-out-only restriction remains historical until Phase 9d replaces it; the `Perf` scheme retains an isolated signed-out launch path.

**Sources:** canvas boards `SplashSpec`, `SplashScreen`, `SplashSlow`, `SplashWelcome`, `Main`, `canvas.json`, `ds/chronoflow/tokens.json` (downloaded 2026-11-05, byte-identical to `chronoflow-mobile/_design/canvas/`); `cf-sky`, `cf-press` and token variables in `chronoflow-mobile/_design/canvas/theme.css`; `pattern-dots` in `ds/chronoflow/components/bundle.css`; settled rules in RN `plan.md` Phase 21. Auth extension: committed `AuthSignIn`, `AuthSignUp`, `AuthTwoFactor` (all eight `screen` variants), wrapper `Auth*.dc.html` boards and `AuthStates`; source verification recorded under the auth/store spec below (2026-11-06).

## Decisions

| # | Decision | Reason |
|---|---|---|
| D1 | Minimum iOS 17.0 (user, 5 Nov), Xcode 27.2 (installed), Swift 6.4, Swift 6 language mode. App/UI modules default `MainActor` isolation; core modules `nonisolated` + `Sendable`. No `#available` branches below 17. | Observation (`@Observable`), KeyframeAnimator, App Intents, scroll-position APIs; drops iPhone 8/8 Plus/X. |
| D1b | **Liquid Glass on iOS 26+.** Build with the latest SDK and never set `UIDesignRequiresCompatibility`, so system controls take Liquid Glass automatically. Explicit glass (`glassEffect`, `.buttonStyle(.glass)`, `GlassEffectContainer`) only behind `if #available(iOS 26, *)`, falling back to the plain system default, never a hand-drawn imitation. Designed surfaces (sky, cards, Welcome pills) stay as drawn; where glass could replace one, ask. | User, 5 Nov: designs may not draw the latest elements; earlier OSes show the normal default look. |
| D1c | **Every iPhone, iPhone Duo included.** All splash and Welcome geometry comes from the window size and safe-area insets (left/right too: Duo has a side rail and horizontal insets). No 390 × 844 constant reaches layout; the moon's landing is measured from Welcome. Device matrix for snapshots and UI checks: iPhone SE (3rd gen), 17e, 17, Air, 18 Pro, 18 Pro Max, **iPhone Duo** (all on iOS 27.2 simulators). **Duo runs on its own runtime** (`com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4`, build 24B91016s); the regular runtime (24B8117) has no Duo device type. `make duo` resolves an available device by type and runtime; name/OS matching fails. | User, 5 Nov: the RN splash is mispositioned on other screens (hard-coded 390 × 844 landing fallback and fixed offsets in `LaunchOverlay.tsx`). |
| D2 | UIKit scene life cycle (`SceneDelegate`) hosting SwiftUI via `UIHostingController`, not the SwiftUI `App` life cycle. | Only this gives control over ordering: the overlay window commits and flushes before the SwiftUI root exists (see D3). |
| D3 | The splash is one Core Animation layer tree in its own `UIWindow` (level `.normal + 1`) on the same scene, driven by a pure `LaunchTimeline`. The overlay window is shown and `CATransaction.flush()`ed in `scene(_:willConnectTo:)`; the main window and SwiftUI root are created in the next run-loop turn (`DispatchQueue.main.async`). `t0` is the media time of that first flush. | Committed animations play in the render server while the main thread works, which RN cannot do. Flushing first keeps frame 0 off the SwiftUI root's first layout; anchoring `t0` to the commit means no part of the opening is skipped. |
| D4 | Every element of one key path has **one** `CAKeyframeAnimation` (one animation key). When an ending becomes known, the track for that key path is rebuilt as opening + ending keys and re-added under the same key with the same `beginTime`. | Two non-additive animations on one key path: the later one wins, and with backwards fill it would freeze the opening from the moment it is added. A merged track has no such interaction. |
| D5 | Endings whose start is known in advance are committed ahead with their real begin time (ready known before 1500 → exit at 1500; slow status at 2000 committed when `hasStoredData == false` is known, removed if ready comes first; welcome flight at W). | The render server owns those moments; only readiness that arrives late needs a main-thread commit. |
| D6 | Welcome is plain SwiftUI. Its intro uses SwiftUI animations whose delays come from the shared `LaunchClock`. | Main thread is idle by 2.3 s; Welcome needs real Dynamic Type and accessibility. |
| D7 | System launch screen is `LaunchScreen.storyboard`: a `UIImageView` (content mode `center`) centred on the superview, background colour `LaunchSky`, image `LaunchMoon` (288 pt PNG with baked glow, @2x/@3x, Any/Dark). No text, so no localised variants. | Apple does not document how `UILaunchScreen`'s `UIImageName` is placed; the storyboard pins the geometry that frame 0 copies. Satisfies TN3208 / ITMS-90870. |
| D8 | The splash wordmark "ChronoFlow" is a baked image asset (`LaunchWordmark`, Fraunces 400 opsz 32, 32/40, −0.32 tracking, skyTitle, @2x/@3x, Any/Dark), rendered by `Tools/AssetGen` with CoreText. | Same in en and nl, fixed size, never wraps. It is in the layer tree at frame 0, so fonts and the main thread are off the splash's critical path. |
| D9 | XcodeGen (`project.yml` committed, `*.xcodeproj` ignored) + one local package `ChronoFlowKit`. `swift format` (toolchain). No SwiftLint. Signing via ignored `Local.xcconfig` (`DEVELOPMENT_TEAM`). | Text-reviewable project, no pbxproj conflicts. Fallback without xcodegen: Xcode project with synchronized folders (OQ 2). |
| D10 | `Tools/TokenGen` converts `tokens.json` OKLCH → Display P3 colour sets (Any/Dark), the `cf-sky` OKLab ramp and a Swift token file. Generated assets that the launch screen needs (`LaunchSky`, `LaunchMoon`, `LaunchWordmark`) are written to **both** `App/Assets.xcassets` and `DesignSystem/Resources`; a test fails if the copies differ. Output committed; a test fails when stale. Source PNGs are P3; sRGB compilation of the two launch images is accepted (5 Nov review): the palette's sRGB round trip, including 8-bit quantisation, stays within 1/255 per P3 channel, guarded by an AssetGen test. | Values only from tokens; colour sets and gradients retain P3. The launch-image exception accepts that bounded rounding rather than duplicate gamut renditions; it must be revisited if the palette changes. The storyboard can only use main-bundle assets, package tests have no app bundle. |
| D11 | Fonts: Figtree 400/500/600/700 and Fraunces 400/500 static TTFs (Fraunces cut at opsz 20, 32, 48). Registered with `CTFontManagerRegisterFontsForURLs(.process)` off the main thread right after the overlay flush. | Works in package tests. First font use is the status (2000 ms) or Welcome (2300 ms). |
| D12 | Readiness is a staged protocol in `AppCore` plus a pure reducer that owns the 1500/2000/8000 ms and "never cut short" rules on an injectable clock. | Rules testable without UI; the real store later implements the same protocol. |
| D13 | Snapshots: `LaunchTimeline.sample(at:)` evaluates every track with the same cubic-bezier solver as CA and sets model values; snapshots render those. Device and UI checks use the live tree frozen with `speed = 0` / `timeOffset`. No layer uses `mask`, `filters` or `shadow*`. | `CALayer.render(in:)` ignores running animations and mask layers; one source drives both paths, and a test proves they agree. |
| D14 | The overlay mounts only on the first scene connection of the process; the intro flag is process-level. | A scene reconnect or later sign-out must not replay the splash or intro. |
| D15 | Debug bundle ID `net.chronoflow.app.native`; no URL scheme registered in this slice. | Installs next to the RN app (`net.chronoflow.app`, scheme `chronoflow`) for measuring; two apps claiming one scheme route unpredictably. OQ 4, 15. |
| D16 | iPhone only, portrait only. | Matches RN; no board covers iPad or landscape. OQ 11. |
| D17 | Non-Welcome destinations go through a `Route` enum and `Navigator` protocol; UI tests assert the route. Debug-only route-name screen only if OQ 8 allows. | No board exists for stand-ins. |
| D18 | **GRDB, pinned SwiftPM dependency.** Add `LocalStore` to `Packages/ChronoFlowKit`, depending on `AppCore` and `GRDB` at **exact 7.8.0**; commit the resolver lockfile. One `DatabasePool` per active account at `Library/Application Support/ChronoFlow/Accounts/<accountId>/account-<accountId>.db`; accept only a validated UUID as the path component. Assert `journal_mode=WAL` for the file and `foreign_keys=ON` on every connection. `DatabaseMigrator` starts with native `v1`, equal to RN's final schema below; never replay its 0000–0014 migrations. | User chose GRDB on 6 Nov; explicit SQL parity, transactions and observation. [Pinned GRDB documentation](https://github.com/groue/GRDB.swift/blob/v7.8.0/README.md) covers Swift 6, pools, migrations and `ValueObservation`. RN user import remains OQ 9. |
| D19 | **Storage attributes.** Create the account directory and DB/WAL/SHM with `FileProtectionType.completeUntilFirstUserAuthentication`; verify protection on sidecars and after reopen. Exclude the whole account directory from backup using `URLResourceValues.isExcludedFromBackup`, including the outbox (proposed default, OQ 26). Use Application Support, never purgeable Caches. No custom encryption/key beside the existing session Keychain. | Supports offline reads after the first unlock; keeping WAL with the DB prevents mismatched copies. Backup exclusion trades restore of unsent changes for avoiding account-data restore without its device-only token; shipping decision remains open. |
| D20 | **One async `DataSource: Sendable` contract**, with `MockDataSource` and `APIDataSource`; domain failures/DTOs in `AppCore`, implementations in `DataAccess`. App-owned factory selects `CHRONOFLOW_DATA_SOURCE = mock` or `api` via an Info.plist build-setting substitution, validates it and rejects unknown values. Default **mock in Debug, simulator and tests**; API is an explicit build setting, usable in Debug or Release. `CHRONOFLOW_API_BASE_URL` defaults to `https://api.chronoflow.net/v1`; Release rejects non-HTTPS. No silent fallback from API to mock. | User chose both implementations, with no network in tests. Tests inject a source or an ephemeral URLSession with a deny-by-default URLProtocol; runtime UI cannot change source/account namespace. API uses the D18 directory and existing native Keychain service; mock uses `Library/Application Support/ChronoFlowMock/Accounts/…` and service `net.chronoflow.app.native.mock`. The preference `api.deviceId` remains device-scoped. |
| D21 | **Extend Phase 4 session storage**, do not create a second reader: `AppCore/StoredSession` and `SessionStore`, `App/Readiness/KeychainSessionStore.swift`, service `net.chronoflow.app.native`, account `session`, JSON `{token, accountId}`; `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. `SessionController.accept(_:)` opens/migrates off-main, upserts the session account, writes Keychain, then publishes signed-in state and requests sync. `restore()` uses the same reader, DB and observation. | Database/setup failure cannot publish an unusable session. Missing/malformed credentials sign out (malformed is deleted); temporary Keychain/protected-data failures retry after unlock/activation and **do not delete data**. RN key is `session`; `app:no-auth` does not exist. No refresh token; server owns the 90-day expiry/sliding renewal. |
| D22 | **Device identity:** `DeviceIdentityStore.identity() async throws` creates a UUIDv7 once, under device preference key `api.deviceId` outside account storage, persists off-main, and reuses it across sign-out. Inject clock/randomness for tests. Include `device_id` and a trimmed device/model name limited to 255 Unicode characters on login/register. Never use IDFA/IDFV as the ID. | Matches RN/backend token-per-device behavior without RN's synchronous kv-store access. Device identity, language and appearance preferences survive a wipe. RN identity import remains OQ 9. |
| D23 | **SyncEngine actor:** full pull (no cursors), flush outbox, identity, account, trip cards, `synced_at`, eviction, changed plan details. One flight per session epoch; coalesce concurrent requests into one rerun, debounce ordinary requests 1 s, expose immediate `refreshNow()`. Retry transient failures at `min(1 s × 2^n, 5 min)`, respecting a larger server retry-after deadline. Triggers: DB open/sign-in, scene active, NWPathMonitor reconnect, outbox commit and a future pull-to-refresh seam. | Mirrors RN's offline model. Connectivity is a hint; failed requests remain typed offline failures. An authenticated 401 for the current epoch invokes forced sign-out/wipe; 403 `email_unverified` switches to verify and suspends protected pulls, never wipes. Every awaited response checks epoch/account before applying. |
| D24 | **Outbox and reads:** SwiftUI observes only SQLite via repository value streams. A local mutation and its UUIDv7 outbox row commit together; FIFO `(created_at,id)`, dependency blocking, pending-value protection, retry and final refusal rules below. Passwords, bearer tokens, two-factor codes and link secrets are never written to outbox/DB/logs. | Offline check-offs/settings/walkthrough and cached trips remain usable after initial pull. Auth, wizard and trip deletion stay online-only. Unsupported server mutations are deferred, not acknowledged as successful. |
| D25 | **Sign-out wipe:** voluntary sign-out attempts a flush, returns `.needsConfirmation(pendingCount:)` if work remains, and only discards after explicit caller intent. Forced 401 bypasses flush/confirmation/logout. Capture the old session token for logout only, invalidate epoch, cancel and await sync/observers/requests, best-effort logout (3 s bound), detach account UI and route `.signIn`, close all DB connections, delete the account directory including DB/WAL/SHM, clear account secrets/session and in-memory caches. Keep `api.deviceId` and device preferences. Idempotent and serialized; a wipe marker retries incomplete deletion before another account opens. | Prevents late writes and cross-account data leaks. There is no sign-out confirmation board: Phase 9 implements the result seam only (OQ 29). Verify's explicit Back/different-email action discards its unverified session's queue as RN does. |
| D26 | **I/O ordering extends D3/D11/D12:** the overlay is shown and `CATransaction.flush()` completes **before** constructing services that touch disk/Keychain, registering fonts, opening SQLite, migrations, preference/mock-state loads or URL cache work. Run all these on non-MainActor workers/actors; GRDB uses async reads/writes and background fetching for observation. MainActor receives immutable values and navigation only. | An `async` declaration alone does not move synchronous work off-main. No eager singleton/static initializer performs I/O. Add ordering and executor assertions with a suspended store to retain the 500 ms stall proof and first-commit budget. The DB opens after the overlay commits, not after overlay teardown. |
| D27 | **Auth follows D1c and the 6 Nov plain-sky decision.** One native Auth shell and controls from the boards; no dot pattern. All four insets, scrolling, root xxLarge cap, en/nl and both appearances are required. Today/terms/walkthrough stay D17 seams; email-update (`changed`) is designed but out of scope. | No invented loading, offline, sync-failure, confirmation or inbox screen. Defaults in new OQs are proposals unless explicitly described as authorized decisions; a blocking OQ must be settled before its sub-phase begins. |

### Test speed (user decision 2026-11-06)

Tooling work, outside the phase sequence: build Debug and isolated ReadinessRelease once per run,
then use up to four concurrent D1c destinations (`SIM_CONCURRENCY=4`) without cleaning/rebooting.
Logic runs on 17e; running-window, scale, geometry, screenshot and audit suites run on all seven.
SE, 17e, Duo and Pro Max retain full snapshot/type/intro coverage; 17, Air and 18 Pro use the committed
compact profile. Existing retained PNG bytes stay unchanged. `make check` combines tests/snapshots;
`make targeted` selects aliases/suites. Timings and the fresh/warmed-process intro proof await simulator execution.

### How conflicts between design sources are settled

SplashSpec's prose gives the rule; keyframes fill what the prose leaves out. Where RN chose otherwise, it is recorded. All listed in OQ 5.

| # | Conflict | Native default | Why |
|---|---|---|---|
| S1 | Moon centre: board y 392 (30 pt above centre); prose "centred" | Centred in the window | Launch screen centres it and frame 0 must match (RN same). On 390 × 844 the wordmark top is 462, band top 470, apex 512.5 and status top 518. **User decision 2026-11-06:** preserve these relative y offsets at every height by centring the composition. At 874 the apex is 527.5 and status top 533, the same 5.5 pt clearance; the path no longer crosses the status text. |
| S2 | Board stars vs static system launch frame | Stars and pattern-dots removed by the user on 2026-11-06, in splash and Welcome | Plain CfSky gradient only. No opening or welcome-exit stars layer/track remains. |
| S3 | Ready hand-off: keyframes 1700–2100; prose "1500 Animation done … +400 Hand-off" | 1500–1900 | Prose rule (RN same). The board's "1900 ms · Hand-off" frame renders keyframes and shows mid-lift; it maps to native 1700. |
| S4 | Moon flight: keyframes ease-out; prose ease-in-out | ease-in-out | Prose rule (RN same). |
| S5 | Path: dasharray 560 on a 505.8 pt path completes at 1313 ms, up to 47 pt ahead of the light; prose "in step with the light" | `strokeEnd` = the light's arc-length fraction | Prose rule. |
| S6 | Welcome stagger: prose "about 100 ms" | Keyframe starts 2300 / 2400 / 2450 / 2600 / 2700 / 2750 | "About" is not a value (RN same). |

### Where investigators disagreed

- **`UILaunchScreen` dict vs storyboard:** storyboard (D7).
- **Readiness `resolve()` vs staged facts:** staged. RN needs three facts at different times (session known, gate resolved, stored data read); the slow rule needs `hasStoredData == false`, not unknown.
- **8 s with unresolved session:** RN hangs (bug). Native never blocks: default signed out at 8 s (OQ 7).
- **Moon landing target:** measured from Welcome. The welcome-flight track is built when the first anchor is published and rebuilt if it changes before W; the computed fallback (includes the row height) is used only if Welcome has not laid out by W − 50 ms.

## Trade-offs & Alternatives Considered

- **SwiftUI `KeyframeAnimator` / `PhaseAnimator` / `Canvas` + `TimelineView` for the splash:** evaluate on the main thread every frame, exactly while launch work runs.
- **ZStack overlay in the SwiftUI root:** shares transactions with a root re-rendering while loading; a window is isolated and torn down with `isHidden = true`.
- **`fillMode = .forwards` endings added as separate animations:** works, but two animations per key path make frozen sampling and rebuilds error-prone; merged tracks (D4) are one source.
- **`UILabel` / `CATextLayer` splash wordmark:** needs registered fonts and a main-thread commit near 1000 ms; a stall would delay or cut its fade. Baked image (D8).
- **`matchedGeometryEffect` for the moon flight:** both views in one hierarchy, no exact timing.
- **Lottie / Rive:** extra runtime and export step for ~15 tracks.
- **Tuist:** caching not worth it for one app. **Hand-made project:** every new target is a pbxproj edit.
- **sRGB colours for RN parity:** P3 is exact; most tokens are inside sRGB anyway. TokenGen prints sRGB hex for the gate document.
- **Variable Fraunces with opsz descriptor:** more exact at large Dynamic Type; revisit if OQ 10 scales the headline.
- **Store (GRDB vs SwiftData):** user chose pinned GRDB on 6 Nov (D18). SwiftData would require translating the settled relational schema and outbox behavior; native v1 preserves the RN final schema directly.
- **Generating `.xcstrings` from RN `en.json` / `nl.json`:** deferred (OQ 13); iOS owns catalogs, copying exact matching en/nl values. The auth copy table marks unmatched English rather than machine-translating it.
- **Reading the RN Keychain item:** impossible under a different bundle ID (expo-secure-store writes without `accessGroup`, so the item is in `TEAMID.net.chronoflow.app`). Native uses its own service now (OQ 9).

## Constraints and working rules

- **Read-only sources.** `chronoflow-new` and `chronoflow-mobile` are read-only. Scripts may read them; nothing writes to them (not even `expo prebuild` — see Phase 7).
- **No design, no invention.** A state or screen without a board is not drawn: stop and ask. Deferring beats inventing.
- **Values only from generated tokens and assets.** Both themes. Touch targets ≥ 44 pt (Welcome's buttons are 52). Colour never the only signal.
- **English and Dutch together.** Each visible string lands with its Dutch in the commit that introduces it, in a String Catalog with English sentences as keys. A test fails on a missing `nl` entry from Phase 0 on. Dutch written by a person, never machine-translated.
- **Copy** promises a clock shift, never symptom relief; modest scientific claims.
- **No unneeded comments.** Native components. No `+load` or static initialisers. No synchronous I/O on the main thread before the overlay flush.
- **Git.** `git init -b main`; first commit holds only docs. Then one branch per phase or sub-phase (`feat/phase-N-slug`, `feat/phase-3a-…`), stacked. Atomic Conventional Commits that tick the task here. Never commit to `main` directly; never merge or force-push unless asked. No `Co-Authored-By` or other trailer (OQ 1). Push and PRs only once OQ 4 names a remote.
- **Local builds only.** `make check` = lint + generator freshness and host tests + unit tests + snapshots on a pinned simulator. Nothing runs on PRs.
- **Board updates.** Refresh `_design/canvas/` from the canvas artifact, re-export frames, record the date here.
- **Who writes what.** Codex (`codex exec`) implements each phase; Opus reviewers check the diff against this plan, the boards and the device matrix (D1c); confirmed findings go back to Codex until the review is clean. Claude orchestrates and commits.
- **iOS 17 runtime.** Xcode 27.2 offers no downloadable iOS 17 (or 18) simulator runtime. The 17.0 floor is enforced by the compiler (deployment target) and checked on a physical iOS 17 device when one is available; simulator checks run on iOS 27.2.

## The spec

Board frame 390 × 844 pt. `w`, `h` = window size; `cy = h / 2` (S1). User decision 2026-11-06: every formerly bottom-anchored `h − k` becomes `cy + (422 − k)`, keeping the board composition centred at every height. The band stretches from its new top to the window bottom; the sky still fills the window. All times in ms from `t0` (D3).

### Tokens (TokenGen output; P3 as `displayP3` r g b)

| Token | Light hex | Light P3 | Dark hex | Dark P3 |
|---|---|---|---|---|
| skyTop | #1F285A | 0.1285 0.1565 0.3411 | #06091C | 0.0260 0.0360 0.1041 |
| skyMid | #4D427F | 0.2951 0.2591 0.4836 | #221A40 | 0.1281 0.1029 0.2429 |
| skyHorizon | #EB9666 | 0.8733 0.6048 0.4334 | #AA5830 | 0.6228 0.3604 0.2228 |
| skyTitle | #F4F9FF | 0.9590 0.9762 0.9981 | #E5ECF6 | 0.9039 0.9230 0.9591 |
| skyCopy | #121932 | 0.0746 0.0960 0.1879 | #E5ECF6 | 0.9039 0.9230 0.9591 |
| skyCopyBackground | #F3F7FC α0.9 | 0.9554 0.9692 0.9867 α0.9 | #0A0E1F α0.9 | 0.0427 0.0548 0.1153 α0.9 |
| dawn | #E78A45 | 0.8543 0.5599 0.3258 | #F2AD73 | 0.9083 0.6882 0.4861 |
| dawnForeground | #2D1205 | 0.1627 0.0756 0.0303 | #101428 | 0.0653 0.0798 0.1517 |
| background | #F3F7FC | 0.9554 0.9692 0.9867 | #0A0E1F | 0.0427 0.0548 0.1153 |

Inside `cf-sky`, `dawn-text` is `dawn`.

**`cf-sky`**: vertical, skyTop 0 %, skyMid at 55 % (light) / 60 % (dark), skyHorizon 100 %. The mid stop is stated in `tokens.json`'s `sky-mid` usage text and `theme.css:53` (no structured field; TokenGen holds it as a constant checked against `theme.css`). CSS interpolates in OKLab. Reference samples:

| | 0.0 | 0.1 | 0.2 | 0.3 | 0.4 | 0.5 | 0.6 | 0.7 | 0.8 | 0.9 | 1.0 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Light | #1F285A | #272D61 | #303167 | #38366E | #403B75 | #493F7C | #5D4C7F | #7E607E | #A1737A | #C58572 | #EB9666 |
| Dark | #06091C | #0A0C22 | #0F0F27 | #13112D | #181434 | #1D173A | #221A40 | #402B42 | #623B41 | #854A3C | #AA5830 |

TokenGen samples each segment separately, always emits a stop exactly at the mid stop (light 0.55 = #4D427F; on the 0.1 grid light is off by up to 5.7/255 there), and adds stops until `CAGradientLayer`'s interpolation is within ±1/255 of true OKLab at 1000 points.

**`pattern-dots`:** removed by the user on 2026-11-06. No tile primitive, generated pattern constants or approved dot-bearing primitive baselines remain.

**`cf-press`:** pressed scale 0.97, opacity 0.85, 120 ms `cubic-bezier(0.25, 0.1, 0.25, 1)`. **Reduce Motion:** pressed = opacity 0.85, scale 1, no transition (`theme.css:143-146`).

**Other constants:** path stroke white α0.55. Plane 8 pt white dot; glow disc r 6 (4 + spread 2), blur σ 5, white α0.8. Stars/pattern-dots removed by the user on 2026-11-06.

### Typography

| Element | Font | Size / line height | Tracking | Colour | Notes |
|---|---|---|---|---|---|
| Splash wordmark | Fraunces 400 (opsz 32) | 32 / 40 | −0.32 | skyTitle | Baked image (D8) |
| Status line | Figtree 400 | 14 / 20 | 0 | skyTitle | |
| Welcome wordmark | Fraunces 400 (opsz 20) | 20 / 28 | −0.20 | skyTitle | |
| Eyebrow | Figtree 600 | 12 / 16 | +1.2 | dawn | Uppercase |
| Headline | Fraunces 400 (opsz 48) | 48 / 48 | −0.48 | skyTitle | Header trait |
| Copy card | Figtree 400 | 16 / 24 | 0 | skyCopy on skyCopyBackground | Padding 16 v / 20 h, radius 22 |
| "Plan my trip" | Figtree 600 | 16 / normal | 0 | dawnForeground on dawn | Height 52 at default size, pill, full width |
| "Sign in" | Figtree 500 | 16 / normal | 0 | skyCopy on skyCopyBackground | Height 52 at default size, pill, full width |

Fraunces is never bold. Dynamic Type grows through xxLarge; xxxLarge and AX1–AX5 clamp to xxLarge (user, 2026-11-06; OQ 10).

### Splash layer tree and geometry (any `w × h`)

The container **is** the splash root: full window, ignores safe areas, `masksToBounds`, background skyTop, anchor (0.5, 0.4) with position adjusted so it still fills the window. Exit animations live on it, so `-cf.freezeAt` covers them. Sublayers, in order:

| Layer | Geometry |
|---|---|
| sky | `CAGradientLayer` `cf-sky`, full window; opacity animated |
| stars | Removed by the user on 2026-11-06; no layer. |
| halo | `CAGradientLayer(.radial)` centred on the sun, approximating `box-shadow 0 0 80 20` dawn α0.45 (disc r 110 blurred σ 40). **Alpha 0 for r < 90** (CSS clips an outer shadow inside the border box); pixel check at r ≈ 85 |
| sun | 180 × 180, centre (w/2, cy + 228), `cornerRadius` 90 + `masksToBounds` (no mask layer). Radial dawn: solid to r 70, α0 at r 91.6 (gradient radius 127.3). User composition decision 2026-11-06: on short screens its bottom may extend below the window like a horizon; its sides stay inside the horizontal safe bounds, its top stays inside the window, and at least one third of its height must be visible in sampled frames. |
| band | top = cy + 48, height = h − (cy + 48), stretching to the window bottom; skyHorizon with alpha 0 / 0.22 / 0.70 / 1.0 at 0 / 0.40 / 0.75 / 1.0; above the sun |
| path | `CAShapeLayer`, cubic (−10, cy + 218) → (90·w/390, cy + 48), (300·w/390, cy + 48) → (w + 10, cy + 218); stroke 1.5, butt caps. x scaling retains RN's rule (OQ 11); vertical composition settled by the user 2026-11-06 |
| plane | dot + glow (constants above), centred on the composition-centred path, no rotation (user 2026-11-06) |
| moon | `LaunchMoon` contents, 288 × 288, centre (w/2, cy), pixel-aligned, `minificationFilter = .trilinear`. Glyph 104 pt: Lucide `M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z`, viewBox 24, stroke 1.6, round caps/joins, dawn; glow dawn α0.45 σ 9 baked |
| wordmark | `LaunchWordmark` contents, box top cy + 40, height 40, centred |
| status | top cy + 96, height 20, centred: text layer (created when needed) + dot layer with `CAReplicatorLayer` ×3 (4 pt, gap 3, margin-left 6, currentColor) |

### Timeline: shared opening (all modes)

| Element | Property | Keys (ms: value) | Easing |
|---|---|---|---|
| Stars | Removed by the user on 2026-11-06 (S2) | — | — |
| Sky | opacity | 300: 0 → 1100: 1 | ease-out |
| Band | opacity | 300: 0 → 1100: 1 | ease-out |
| Sun + halo | translateY, opacity | 400: +110, 0 → 1300: 0, 1 | ease-out |
| Path | strokeEnd | 500: 0 → 560: 0.03 → 1400: 1 | linear (S5) |
| Plane | arc-length fraction | 500: 0 → 560: 0.03 → 1400: 1 | linear |
| Plane | opacity | 500: 0 → 560: 1; 1400: 1 → 1500: 0 | linear |
| Moon | translateY, scale | 300: 0, 1 → 1100: −28, 0.86 | ease-out |
| Wordmark | opacity, translateY | 1000: 0, +8 → 1400: 1, 0 | ease-out |

Animation done at 1500. Plane `position` keys: 128 points sampled by arc length, keyTimes from the fraction curve; `strokeEnd` uses the same fraction. Phase 3a verifies `strokeEnd` is arc-length proportional; otherwise the path becomes the sampled polyline.

### Endings

Curves: **ease-out** (0, 0, 0.58, 1), **ease-in-out** (0.42, 0, 0.58, 1), **intro** (0.2, 0.8, 0.2, 1).

**`ready`** (signed in, ready): `E = max(1500, readyAt)`; E → E + 400 container opacity 1 → 0, scale 1 → 1.08, anchor (0.5, 0.4), ease-out (S3). If ready is known before 1500 the exit is committed with begin 1500 (D5).

**`slow`** (signed in, `hasStoredData == false`, not ready at 2000): status opacity 0 → 1 over 2000–2300, ease-out, latched until the hand-off ends. Dots loop 1200 ms ease-in-out: 0.25 at 0 → 1 at 480 → 0.25 at 960, held to 1200; delays 0 / 200 / 400; started at overlay mount (as on the board). Hand-off as `ready`, starting at readyAt; forced at 8000.

**`welcome`** (signed out). `W = max(1600, endingKnownAt)` (OQ 7).

| Element | Change | ms | Easing |
|---|---|---|---|
| Band | opacity 1 → 0 | W → W+700 | ease-out |
| Stars | Removed by the user on 2026-11-06 | — | — |
| Sun + halo | translateY 0 → +120, opacity 1 → 0 | W → W+600 | ease-out |
| Path | opacity 1 → 0 | W → W+400 | linear |
| Wordmark | opacity 1 → 0, translateY 0 → −6 | W → W+300 | ease-out |
| Moon | centre (w/2, cy − 28) → target centre; scale 0.86 → target.width / 104 (board 0.27); one straight line, one progress | W → W+700 | ease-in-out (S4) |
| Container | opacity 1 → 0, no scale | W+700 → W+950 | ease-out |

Overlay torn down at W+950 (on the animation's completion, never `asyncAfter`).

### Welcome intro (first launch of the process only)

Each item: opacity 0 → 1, translateY +14 → 0, 450 ms, intro curve. Offsets from W+700:

| Item | Offset | Nominal start |
|---|---|---|
| Wordmark text (moon glyph does not animate) | +0 | 2300 |
| Eyebrow | +100 | 2400 |
| Headline | +150 | 2450 |
| Copy card | +300 | 2600 |
| "Plan my trip" | +400 | 2700 |
| "Sign in" | +450 | 2750 |

Last item lands at 3200. Welcome's moon is not animated; it sits under the overlay and is revealed by the dissolve.

### Welcome layout (on `cf-sky`)

- Background: one `CfSky` gradient only; pattern-dots removed by the user on 2026-11-06.
- Padding: top `max(safeTop + 16, 64)`, sides 24, bottom `max(safeBottom, 40)` (RN's rule; board is fixed 64 / 24 / 40; on Dynamic Island phones top becomes ~78 — OQ 10).
- Column `space-between` inside a scroll view (RN). Top group gap 16: moon row (Lucide moon 28 × 28, stroke 2 → 2.33 pt, dawn, no glow; gap 8; wordmark), eyebrow (+56 margin above), headline. Bottom group gap 12: copy card (+12 margin below), "Plan my trip", "Sign in".
- Board geometry on 390 × 844: moon row y 64–92, eyebrow 164–180, headline from 196, "Plan my trip" 688–740, "Sign in" 752–804.
- Moon anchor: `onGeometryChange(for: CGRect.self) { $0.frame(in: .global) }` → `MoonAnchorStore`.
- Fallback target centre: x = 24 + 14, y = max(safeTop + 16, 64) + rowHeight / 2, where rowHeight = max(28, wordmark line height at the capped current size).

### Readiness rules (RN Phase 21, with the RN bug fixed)

1. The ending is chosen once, the first time the session is known: signed out → `welcome`, else `app`.
2. Ready = signed out, or signed in + gate resolved + (gate ≠ `app` or `hasStoredData == true`).
3. Never cut short: `app` needs ready (or 8 s) and t ≥ 1500; `welcome` starts at W. Reduce Motion skips the wait.
4. Status shows when t ≥ 2000, `hasStoredData == false` (not `nil`) and not ready; latched until the hand-off ends.
5. At 8000 readiness is forced: `allowFirstLoad()` scoped to the current session; if the session is still unknown, signed out (OQ 7).
6. The hand-off happens exactly once.
7. A cold-start URL or notification response is captured in `PendingLaunchIntent` and never changes the ending.

### Reduce Motion

Read `UIAccessibility.isReduceMotionEnabled` at scene connect; `-cf.reduceMotion` overrides.
- Frame: skyTop + moon only, no lift, no wordmark.
- Hand-off when ready: 300 ms container fade, no scale, ease-out (RN-derived; OQ 6); no Welcome intro.
- Slow: status appears with a 300 ms fade; dots hold (opacity: OQ 6).
- `PressStyle` per `cf-press` above.

### Appearance

Splash follows the phone appearance captured once from the scene's `traitCollection` at connect (matches the launch screen). Welcome follows the system. Status bar light until the hand-off ends.

### Accessibility

- Overlay window: `accessibilityViewIsModal`, one image element "ChronoFlow is opening"; app window `accessibilityElementsHidden = true` until the hand-off ends.
- Status: announced once, queued (`AccessibilityNotification.Announcement`, `.accessibilitySpeechQueueAnnouncement = true`).
- After teardown: `.screenChanged` to Welcome's first element. Headline has the header trait. Reading order: wordmark, eyebrow, headline, copy, "Plan my trip", "Sign in".
- No haptics.

### Copy (String Catalog; English is the key)

| English | Dutch |
|---|---|
| ChronoFlow | ChronoFlow |
| ChronoFlow is opening | ChronoFlow wordt geopend |
| Getting your plan ready | Je plan wordt klaargezet |
| Jet-lag planner | Jetlagplanner |
| Plan your clock shift for your next trip | Plan de verschuiving van je biologische klok voor je volgende reis |
| Tell us your flights and how you sleep. You get a day-by-day plan for sleep, light and caffeine that helps your body clock shift. | Vertel ons welke vluchten je neemt en hoe je slaapt. Je krijgt een dagplan voor slaap, licht en cafeïne dat je biologische klok helpt verschuiven. |
| Plan my trip | Plan mijn reis |
| Sign in | Inloggen |

Language: phone preference (`nl`, else `en`); iOS's per-app language replaces RN's in-app override.

### Core seams

```swift
public enum LaunchEnding: Sendable, Equatable { case welcome, app }
public enum SessionPresence: Sendable, Equatable { case signedIn(accountID: String), signedOut }
public enum Gate: Sendable, Equatable { case verify, terms, walkthrough, app }

public protocol LaunchReadiness: Sendable {
    func session() async -> SessionPresence
    func gate() async -> Gate
    func hasStoredData() async -> Bool
    func allowFirstLoad() async
}

public struct LaunchState: Sendable, Equatable {
    public var ending: LaunchEnding?
    public var hasStoredData: Bool?
    public var isReady = false
    public var showsStatus = false
    public var exitStart: Duration?
    public var moonTarget: CGRect?
}
public enum LaunchEvent: Sendable {
    case session(SessionPresence), gate(Gate), storedData(Bool), moonAnchor(CGRect), reached(Duration)
}
public enum LaunchEffect: Sendable, Equatable {
    case commitStatus(at: Duration), cancelStatus, commitExit(LaunchEnding, at: Duration, moonTarget: CGRect?), forceReady
}
public func reduce(_ state: inout LaunchState, _ event: LaunchEvent, reduceMotion: Bool) -> [LaunchEffect]
```

```swift
public struct LaunchTimeline: Sendable, Equatable {
    public struct Track: Sendable, Equatable {
        public let layer: LayerID
        public let keyPath: String
        public let keyTimes: [Double]
        public let values: [TrackValue]
        public let curves: [CubicBezier]
    }
    public static func opening(size: CGSize, reduceMotion: Bool) -> LaunchTimeline
    public func withReadyExit(at start: Duration) -> LaunchTimeline
    public func withWelcomeExit(at start: Duration, size: CGSize, moonTarget: CGRect) -> LaunchTimeline
    public func withStatus(at start: Duration) -> LaunchTimeline
    public var tracks: [Track] { get }
    public func sample(at t: Duration) -> [LayerID: LayerValues]
}
```

Each `with…` returns a timeline with one merged track per key path (D4). Live playback: each track is one `CAKeyframeAnimation` keyed by `keyPath` on its layer, `fillMode = .both`, `isRemovedOnCompletion = false`, `beginTime = t0` (container-local, never 0), `preferredFrameRateRange(80, 120, 120)`. Rebuilding re-adds under the same key with the same `beginTime`. Frozen: `container.speed = 0`, `container.timeOffset = t`.

## Auth and offline-store spec (extension, 2026-11-06)

Paths below beginning `Sources/` or Swift `Tests/` are relative to `Packages/ChronoFlowKit/`; root Python `Tests/*.py`, app/hosted/UI/tool paths are repository-relative. These are plans, not completed work. Schema and wire contracts follow the verified sources, not stale RN API TODOs.

### Verified source map

`M` = `/Users/rickgout/Sites/chronoflow-mobile`; `W` = `/Users/rickgout/Sites/chronoflow-new` (both read-only). Verified on 2026-11-06:

| Concern | Sources and consequence |
|---|---|
| Native seams | `Sources/AppCore/SessionStore.swift:3` (`StoredSession`), `:21` (`SessionStore`); `App/Readiness/KeychainSessionStore.swift:5`; `App/SceneDelegate.swift:132` currently builds `StubReadiness`; `Sources/AppCore/Route.swift:1` and `App/RootView.swift:30` own route seams. Extend these. |
| Session/store | `M/src/session/storage.ts:3`, `session.ts:57` (save order), `sign-out.ts:31`; `M/src/db/schema.ts:56`, `account-database.ts:17`, `queries.ts:79`, `DatabaseProvider.tsx:141` (`syncedAt`). Native schema v1 is the final schema, not RN migration history. |
| Sync | `M/src/sync/engine.ts:46` (pull), `:115` (outbox), `:445` (cards), `:511` (eviction); `triggers.ts:42` (debounce), `:78` (epoch), `:155` (activation/reconnect); `M/src/db/store-account.ts:7` protects pending values. |
| Auth behavior | `M/src/components/auth/AuthScreen.tsx:22`, `useAuthForm.ts:34`, `AuthBanner.tsx:10`, `useAuthKeyboardScroll.ts:25`; `M/src/app/(auth)/{sign-in,two-factor,forgot,reset,sign-up}.tsx`; `M/src/app/(verify)/verify.tsx`. RN is behavioral reference; board copy wins unless an OQ records a conflict. |
| Mock | `M/src/data/mock/MockDataSource.ts:165` (restore/persist, latency), `:223` (offline), `:258` (failNext), `:293` (auth), `:467` (reset inbox); `rate-limit.ts:3`; `fixtures/auth.ts:1`. Inbox uses `{token,email}` in RN: do not reuse that verification wire contract. |
| Wire/API | `M/src/data/api/client.ts:49`, `device.ts:7`, `ApiDataSource.ts:74` and `:386`; `M/src/config/api.ts:34` (mock-only passkeys). `W/routes/api.php:40–63,99–107` is authoritative: forgot/reset/resend/verify exist. RN's `NotOnTheApiYet` and `docs/web-api-requests.md` are stale for those methods. |
| Server identity/security | `W/app/Actions/Api/IssueMobileToken.php:12` (one mobile token/device, 90 days); `W/app/Listeners/RefreshMobileTokenExpiry.php:11` (daily sliding extension); `MobileTwoFactorChallenges.php:13` (5 min, 5 failures); `W/app/Providers/AppServiceProvider.php:95` (login limits) and `:201` (production password policy). |
| Reset/verify truth | `W/app/Http/Requests/Api/V1/{ResetPassword,VerifyEmail}Request.php`; `W/app/Actions/Api/{ResetMobilePassword,MobileEmailVerification}.php`; `W/app/Actions/Fortify/ResetUserPassword.php:35` revokes tokens; `W/app/Http/Controllers/Api/V1/ResetPasswordController.php:16` returns 204. Reset does not sign in. Verify requires authenticated `{id,hash,expires,signature}`, not `{token,email}`. |
| Localized copy | Exact English sentence keys from `M/src/i18n/locales/{en,nl}.json`; field-message keys from `W/app/Http/Requests/Auth/AuthMessageKeys.php:10`. Human review is required for every missing exact match below. |

### Account schema v1 and observation

Use TEXT for IDs, UTC/date strings and JSON; INTEGER for booleans/counters. `?` means nullable; all other columns, including single-column TEXT primary keys, are NOT NULL as in RN's emitted SQL. Boolean defaults preserve RN's `true`/`false` SQL semantics; compare column metadata by name, with normalized boolean defaults. `PK` identifies the same natural/composite primary keys as RN; no new foreign keys beyond the one listed. GRDB adds its own migration bookkeeping table only. JSON values retain unknown members for later features; decode typed DTOs for fields actually consumed. Bind all SQL values.

| Table | Columns and constraints (RN final schema) |
|---|---|
| `account` | `id TEXT PK`, `name TEXT`, `email TEXT`, `has_verified_email INTEGER DEFAULT true`, `synced_at TEXT?`, `walkthrough_seen INTEGER DEFAULT false` |
| `trips` | `id TEXT PK`, `card JSON`, `adaptation JSON?`, `form JSON?`, `revision JSON?`, `current_input_hash TEXT?`, `keep_offline INTEGER DEFAULT false`, `departure_utc TEXT`, `plan_start_utc TEXT?`, `plan_start_zone TEXT?`, `preparation_days INTEGER?`, `plan_end_utc TEXT?`, `plan_end_date TEXT?`, `deleted_at TEXT?`, `deleted_locally INTEGER DEFAULT false` |
| `plan_versions` | `trip_id TEXT REFERENCES trips(id) ON DELETE CASCADE`, `input_hash TEXT`, `detail JSON`, `received_at TEXT`, `detail_version TEXT?`; PK `(trip_id,input_hash)` |
| `check_marks` | `trip_id TEXT`, `input_hash TEXT`, `type TEXT`, `local_date TEXT`, `ordinal INTEGER`, `status TEXT`, `marked_at TEXT`; PK `(trip_id,input_hash,type,local_date,ordinal)`; no RN FK |
| `settings` | `section TEXT PK`, `value JSON`. Sections: `bodyClock`, `preferences`, `reminders`, `planCredits`, `policies`, `sleepAnswered`, `readiness`, `billing`, `profileChange`, `dataExport`, `security`, `securityChange`, `securitySecrets`, `syncFailure`. Preserve schema names; do not start populating sensitive `securitySecrets` without a later design/security task. |
| `drafts` | `id TEXT PK`, `trip_id TEXT?`, `form JSON`, `base_form JSON?`, `dirty INTEGER DEFAULT true`, `review JSON?`, `token TEXT?`, `input_revision INTEGER DEFAULT 0`, `review_revision INTEGER?`, `wizard_source_revision TEXT?`, `wizard_review JSON?`, `furthest_step TEXT?`, `wizard_state JSON?`, `source_revision JSON?`, `save_failure JSON?`, `field_errors JSON?`, `updated_at TEXT` |
| `outbox` | `id TEXT PK` (UUIDv7), `kind TEXT`, `payload JSON`, `created_at TEXT`, `attempts INTEGER DEFAULT 0`, `last_error TEXT?`. Kind names: `check-off`, `settings`, `complete-trip`, `profile`, `data-export`, `security`, `walkthrough`. |

`AccountDatabase` owns pool/open/migrate/close; `AccountRepository`, `TripRepository`, `SettingsRepository`, `DraftRepository`, `OutboxRepository` own records and queries. GRDB records are Sendable values with explicit snake-case coding keys. `ValueObservation` fetches on GRDB's executor, exposing cancellable `AsyncThrowingStream` values; no synchronous initial fetch on MainActor. A small `@MainActor @Observable AccountModel` consumes values for SwiftUI and clears them on account epoch change. No view receives a GRDB connection or calls the API for account/trip reads; auth status requests remain online commands applied through the session controller. Offline availability means the data actually fetched: do not promise all historical plans are downloaded. Keep-offline/on-screen plan retention matches RN.

Sketches fix ownership/signatures without prescribing full implementations:

```swift
// Sources/LocalStore/AccountDatabase.swift (non-MainActor)
public actor AccountDatabase {
    public func open(accountID: String) async throws
    public func close() async throws
}
// Extend Sources/AppCore/SessionStore.swift; retain existing read/write/delete.
public protocol SessionControlling: Sendable {
    func restore() async throws -> SessionPresence
    func accept(_ result: SessionResult) async throws
    func signOut(discardPending: Bool, unauthorized: Bool) async throws -> SignOutResult
}
// Sources/AppCore/DataSource.swift; DTO definitions live beside it.
public protocol DataSource: Sendable {
    func passkeyOptions() async throws -> ApiPasskeyChallenge
    func passkeyLogin(_ input: ApiPasskeyLoginInput) async throws -> SessionResult
    func signIn(_ input: PasswordSignInInput) async throws -> SignInResult
    func completeTwoFactor(_ input: TwoFactorInput) async throws -> SessionResult
    func signUp(_ input: RegisterInput) async throws -> SessionResult
    func requestPasswordReset(email: String) async throws
    func resetPassword(_ input: ResetPasswordInput) async throws
    func verificationStatus() async throws -> EmailVerificationStatus
    func resendVerificationEmail() async throws -> EmailVerificationStatus
    func verifyEmail(_ input: SignedVerificationInput) async throws -> EmailVerificationStatus
    func signOut() async throws
    func fetchIdentity() async throws -> AccountIdentity
    func fetchAccount() async throws -> AccountSnapshot
    func fetchTrips() async throws -> [TripListItem]
    func fetchTripDetail(id: String) async throws -> TripDetail
    func send(_ change: OutboxChange) async throws -> MutationReceipt
}
```

`SessionResult` carries token/account/optional `tripId`; `SignInResult` is session or two-factor challenge. Challenges stay in memory, not Keychain or navigation URLs. Guest claim inputs remain optional DTO fields for parity, but guest recovery/continuation UI is deferred. `SignedVerificationInput` has `id`, `hash`, `expires`, `signature`; no dual RN-shaped overload. Tests may construct reset/verify inputs directly without registering any URL handler.

### API contract and offline sync

- Use an injected ephemeral URLSession: no shared cookie storage, cookies, persistent URL cache or redirects. URLSession delegate declines **every** redirect; test 301/302/307/308 and prevent bearer leakage across origins. Base URL must be absolute, have no user/password/query/fragment, and use HTTPS in Release; encode path components. Headers: `Accept: application/json`, JSON `Content-Type` for bodies, bearer from the active session for authenticated endpoints. Public auth calls (login/two-factor/register/forgot/reset/passkey options/passkey login), airports and guest review never receive an old bearer. No test invokes the live API; sanitized recorded-response JSON is derived from backend response assertions/DTOs and RN client fixtures, with provenance in `Tests/DataAccessTests/Fixtures/README.md`.
- Timeout 15 s; 90 s for registration and future wizard writes; logout 3 s. Cancel the underlying task on timeout/cancellation; timeout/transport failure → offline, explicit task cancellation remains cancellation. Never log passwords, tokens, recovery codes, signed links or response bodies with secrets. Sanitized recorded tokens and fixture credentials are test values only; production forms always start empty.
- Decode `{code,message,errors?,args?,retryAfterSeconds?}`. 401/`unauthenticated` → unauthorized; 403/`email_unverified` → verification gate; `validation_failed` → field-message keys + args (invalid/missing errors → server); 429/`throttled` → retry-after (valid body, then seconds/date header, then 60 s); `conflict` → conflict; other status/code, malformed JSON or unexpected success shape → server. Preserve status for outbox refusal classification. 204 is valid for reset/forgot/logout. Normalize Laravel `:min/:max` and RN `{{min}}` argument formats to String Catalog interpolation; never display an untranslated arbitrary backend sentence in Dutch.

| Operation | Endpoint and payload/result |
|---|---|
| Sign in | `POST auth/login {email,password,device_name,device_id,draft_token?,guest_secret?}` → `{kind:"session",token,account,tripId}` or `{kind:"two-factor",challengeId}`. Wrong credentials are 422/email; login server limits are 5/min email+IP, 20/min IP, 20/hour email. |
| Passkey options | `POST auth/passkey/options`, public with no body/bearer/cookies → `ApiPasskeyChallenge {challengeId,options:ApiPasskeyRequestOptions}`. Options: 32-byte unpadded-base64url challenge, `rpId:"app.chronoflow.net"`, `timeout:60000`, `userVerification:"required"`, `allowCredentials:[]`; challenge ID is 64 characters, single-use with 120 s expiry. Options limiter 10/min/IP. |
| Passkey login | `POST auth/passkey/login`, public with no bearer/cookies: `ApiPasskeyLoginInput {challengeId,credential:ApiPasskeyAssertion,device_id,device_name,draft_token?,guest_secret?}` → the same `ApiSession` as password login (including unverified accounts and 2FA accounts without a TOTP step). `ApiPasskeyAssertion {id,rawId,type:"public-key",response:ApiPasskeyAssertionResponse}`; response `{clientDataJSON,authenticatorData,signature,userHandle?}`. `id` and `clientDataJSON` require unpadded base64url; other binary fields accept base64/base64url, padded or unpadded; `rawId` must decode to the same bytes as `id`. Optional `userHandle` may be absent/null/empty. Credential strings ≤8192 characters. Login limits: 5/min/credential-ID-hash+IP, 20/min/IP, 20/hour/credential-ID-hash counting 422 only. |
| Two-factor | `POST auth/two-factor {challengeId,code}` **or** `{challengeId,recovery_code}` → session. Server challenge: 5 min, five failures, consumed recovery code. |
| Register | `POST auth/register {name,email,password,password_confirmation,device_id,device_name,language,...optional guest fields}` → session, initially unverified. `language` is `en` or `nl`. |
| Forgot/reset | `POST auth/forgot-password {email}` → 204 regardless of account existence. `POST auth/reset-password {token,email,password,password_confirmation}` → 204; all existing tokens revoked, **no new session**. |
| Verify | `GET users/me` → identity with `hasVerifiedEmail`, policies and walkthrough; status adapter adds no invented resend delay. `POST email/verification-notification` → `{email,hasVerifiedEmail,resendAfterSeconds}`. `POST email/verify {id,hash,expires,signature}` (authenticated) → same status. |
| Pull | `GET users/me`, then (only verified) `GET account`, `GET trips`, retained `GET trips/{id}`. Unverified sessions can use identity/auth/email routes; do not loop on protected 403s. |
| Outbox writes | Check-off → `PUT trips/{id}/checks`; settings → `PATCH account/body-clock`, `/preferences`, `/reminders`, or policies → `POST terms/acceptance`; profile → `PATCH users/me`; walkthrough → `POST walkthrough`. Validate payload shapes against the matching W request/DTO files. Do not invent completion/export endpoints: OQ 31. Security schemas remain stored-compatible but security features are outside these phases. |

Passkey contract source: `W/docs/ui-plan/phase-18-mobile-api-passkeys.md`, “Answers for iOS” and “iOS handoff”, branch `feat/mobile-api-passkeys` at `841be4bd` (2026-11-06; not deployed). A verification attempt consumes the challenge even on failure; fetch fresh options after `errors.challengeId` 422. Request validation precedes consumption; lock/expired/reused challenges map to the same expiry sentence. `validation_failed` maps `errors.credential` to “We couldn't sign you in with that passkey. Please try again.” (nl “We konden je niet inloggen met deze passkey. Probeer het opnieuw.”), and `errors.challengeId` to “The passkey request expired. Please try again.” (nl “Het passkeyverzoek is verlopen. Probeer het opnieuw.”). Required/length/UUID field messages use the existing field pattern (`args.max`, `args.attribute`); 429 uses `retryAfterSeconds`/Retry-After; 500 `server_error` means a server fault. No check-specific credential disclosure. Token/device replacement, 90-day sliding expiry and account-scoped optional claim `tripId` match password login.

AASA is served only at `https://app.chronoflow.net/.well-known/apple-app-site-association` (API host returns a 404 envelope), JSON `webcredentials.apps` = `["2UMFLSCBZ6.net.chronoflow.app.native","2UMFLSCBZ6.net.chronoflow.app"]`, application/json, max-age 3600. Team ID and both bundle registrations remain **unconfirmed** (OQ 4). Native passkey verification remains **Open: device only**, needing a team-signed build and deployed public HTTPS AASA. Registration from the app (`/v1/account/passkeys`) is a proposal outside these phases.

MockDataSource is an actor with separate persisted fake-server state (never the local account DB), injectable clock/random delay/store, normal latency 300–800 ms, `setOffline(_:)`, one-use `failNext(method:error:)`, 5/min rate windows and deterministic scenario seeds. Port RN auth/account/trips behavior and response shapes, including two-factor/recovery, unverified accounts, mutations and reset/verify mail events. Match the backend's reset revocation and signed verification contract rather than its stale RN variants. Mock inbox is a data/test API; **there is no committed inbox board**, so no inbox UI is included. Tests/previews inject named RN fixture values; never prefill customer fields or add fixture credentials as real configuration. Persist only in the explicit mock namespace after the overlay commit; tests use in-memory or temporary stores and no real-time sleeps.

Sync sequence for one epoch:

1. If offline, keep DB/outbox and return offline. Flush supported outbox rows in `(created_at,id)` order. Failed dependency keys block later rows with that key, while independent keys may proceed: settings by section, check/complete by trip, other mutations by kind. All local writes + enqueue happen in one SQLite transaction. Delete acknowledged rows in the response-application transaction; a network success followed by crash must be safe to replay (absolute check/settings values; endpoint-specific receipts, no invented idempotency header).
2. Pull identity first, upsert it without overwriting pending local profile/walkthrough values. If unverified, publish verify gate and stop; do not set `synced_at`. Pull account/settings preserving queued sections/profile edits; pending body-clock invalidates derived readiness. Then pull all trip cards, tombstone missing cards (including an empty list), never resurrect `deleted_locally`, and preserve queued local completions.
3. In the card/account transaction set `synced_at` on the matching account once those pulls succeed. This is RN's stored-data readiness marker, **not** a guarantee every plan detail downloaded. An older marker survives a later offline/partial failure. Evict deleted plans and non-keepOffline plans not held by an on-screen lease; never evict data referenced by pending rows. Fetch retained details only when missing or `detailVersion` changed; store detail/version/hash/check marks transactionally. Pending check-offs protect local marks from pull replacement. Expose a plan-lease seam for future Today UI, test it without building Today.
4. When a queued check-off has an old input hash, fetch current detail, re-key by stable `(type,local_date,ordinal)` when the step still exists; drop only a step that demonstrably disappeared. Retry one stale-plan response after refresh; never overwrite a newer local mark. Handle detail 404 without an endless retry loop; retry transient detail errors without clearing the readiness marker.
5. For final non-retryable 4xx (excluding 401, verification-required, retryable 408/425/429 and stale-plan conflict handling), persist a `settings.syncFailure` value and remove/resolve the refused row atomically as RN does. Retain transient failures with `attempts += 1` and sanitized `last_error`; back off. No toast/banner exists for sync failure in these boards: expose a typed event and defer its visual presentation (OQ 30). Unsupported kinds remain pending/blocked without hot-loop retries and cannot be produced by these phases (OQ 31).

NWPathMonitor callbacks run on a private queue; scene activation from `SceneDelegate.sceneDidBecomeActive` (UIKit equivalent of SwiftUI `scenePhase == .active`) forwards to the same engine. Background/disconnect cancels timers/listeners as appropriate; no background task scheduler is added. Use an injectable path monitor, clock and trigger source in tests. Sign-out cancels and awaits old tasks before pool close; epoch checks apply inside write transactions as well as before requests. An old 401 must never wipe a newly signed-in session.

`StoredDataReadiness` implements Phase 4's `LaunchReadiness`, including its stored-data update stream: signed-out ready immediately; signed-in gate from the DB; `hasStoredData = matching account.synced_at != nil`, initially false after a successful empty read (unknown until DB read completes). Stream false → true on first successful pull. Verify/terms/walkthrough are ready without that marker; cached app data works offline. Keep the 2 s status/8 s bound and session-scoped `allowFirstLoad`, which never fakes `synced_at`. Local DB corruption/open/protected-data errors are typed failures, never silently destructive migrations; no new error screen is authorized. Phase 9 tests the failure seam; a product UI needs a board (OQ 30). The `Perf` scheme explicitly selects signed-out readiness and starts no DB/sync; ordinary Release uses the selected data source/session after Phase 9d.

### Auth geometry, tokens and typography

Reference frame **375 × 812 pt**, not the splash's 390 × 844. Only the sky fills the window; content uses its measured size and `safeTop/safeBottom/safeLeft/safeRight`. Layout is a native scroll view with a minimum content height equal to the available viewport; use natural text/control heights and a flexible spacer between heading and card (minimum `space-6`, following RN). Insets: top `safeTop + space-4`, leading `safeLeft + space-4`, trailing `safeRight + space-4`, bottom `safeBottom + space-6`. In a zero-inset board fixture this gives 16/16/24; safe-area fixtures are checked separately. Do not scale all coordinates by 375/812 or put an absolute y on the form. Recompute on every window/inset/keyboard change, including Duo's asymmetric side rail; the sky remains full-bleed. No extra Duo posture has a board (OQ 11).

- Brand row: minimum 44 high; back control 44 × 44, 22 glyph; opposite 44 spacer keeps the brand centered within safe content. Brand gap 6, moon 20, dawn; heading margin 32 (24 for compact Sign up), heading/description gap 8. Problem/done variants use the board's 48 icon disc, 24 glyph and 8 bottom gap. Header/back stay native controls; designed brand placement is measured against the board rather than relying on a system navigation-title layout.
- Card: `card`/`card-foreground` (dark is not white), padding 20, radius `3xl` 26, gap 14, `shadow-soft`. Footer gap 12, min 48, full pill, `sky-copy-background`/`sky-copy`. Card width is available content width (343 in the zero-inset reference); no invented max-width/columns on Duo.
- Field bundle: label/input/hint-or-error gap 8, input border `input`, focused `ring`, invalid `destructive`, radius `md` 12, horizontal inset 12. Web input visual minimum 36 and `h-10` button 40 are **not native touch-target sizes**: native hit regions are at least 44; grow visible surfaces/height where needed for Dynamic Type, following RN's native controls. Record this platform adaptation against board references; never lock text into fixed-height 36/40 boxes. Default auth action is outline for Sign in; primary for Two-factor/Register/Reset/Forgot, ghost/outline alternatives as drawn. `lg` component padding 24; expired/done/failed actions min 48. One native Toggle for the shared password visibility state in Sign up, styled to the board's Show/Hide row, preserving switch semantics.
- Banner: AuthStates places it **first inside the card**, above every control/divider. Padding 12 v/14 h, gap 10, radius `xl` 18; 18 alert icon and 1 top offset. Background is OKLab mix `destructive` 10% + `card` 90%; 1 border is destructive at 35% alpha; text `card-foreground`, icon `destructive`. Export resolved Any/Dark mixed colors via TokenGen. Notice uses the bundle's info tone: card/background, border, radius `2xl` 22, padding 12, gap 12, 16 info icon in muted foreground; title weight 600.
- Extend `Tools/TokenGen` to generate needed semantic colors, auth metrics/typography and soft-shadow values **from** `tokens.json`, board declarations and component bundle (with freshness/source checks, as Welcome does). Include `foreground`, `card`, `card-foreground`, `input`, `border`, `ring`, `muted-foreground`, `primary`, `primary-foreground`, `accent`, `accent-foreground`, `destructive`, plus existing sky/dawn tokens; do not hand-code RGB, spacing or typography in views. Generate the board SVG back/eye/alert/info/check glyphs through `Tools/AssetGen` for native controls (including the passkey key glyph under settled OQ 20); no ad-hoc icon paths or colors in views. Shadows belong only to the auth card, never the splash tree. Reuse `CfSky`, `MoonShape`, `PressStyle`, font registry and root ContentSizeCap. No PatternDots generator/assets return.

| Element | Font | Default size / line | Tracking | Color |
|---|---|---|---|---|
| Brand | Fraunces 400, existing opsz 20 cut | 18 / 24 | 0 (board) | skyTitle |
| Heading | Fraunces 400, existing opsz 32 cut | 36 / 40 | −0.36 | skyTitle |
| Description / input | Figtree 400 | 16 / 24 | 0 | skyTitle / cardForeground |
| Field label / button / link | Figtree 500 | 14 / 20 | 0 | cardForeground/foreground or button foreground |
| Create-account link / banner and notice title | Figtree 600 | 14 / 20 | 0 | dawnText / cardForeground |
| Hint / field error / banner body / notice / countdown | Figtree 400 | 14 / 20 | 0 | mutedForeground / destructive / cardForeground |
| Divider / consent | Figtree 400 | 12 / 16 | 0 | mutedForeground (consent links foreground) |
| Footer | Figtree 500 | 14 / 20 | 0 | skyCopy |

Scale through the existing root **xxLarge** cap; no per-view caps or smaller font overrides. Multiline labels/hints/banners/consent may grow; links wrap/stack within their existing group when necessary, keeping source order. Countdown uses tabular figures. Compare AX5 and xxLarge geometry/pixels as in Welcome. System appearance changes update sky/card/input/border/error colors together. Keep D1b system controls/keyboard behavior and Liquid Glass automatically; auth card and pills retain their drawn surfaces.

### Form behavior, routing and accessibility

- Native TextField/SecureField (UITextField bridge only where needed for reliable focus/selection/passwordRules); native Button/Toggle, ProgressView for the bundle's loading affordance. No client-side validation; the server/mock returns all field messages. Six-character numeric entry limitation is input behavior, not a local correctness check. No offline-disabled submit. Double-submit lock across tap/return; disable fields/actions during a request, preserve button label and dimensions, and show the bundle loading indicator. Clear any banner on user edit; map validation to the displayed field. Credentials/emailTaken use banners; an error for an undisplayed field uses a notice/banner seam, subject to OQ 30.
- Keyboard safe-area avoidance, interactive scroll dismissal, focus-driven scroll and remeasurement after errors/keyboard resizing. Keep the focused input and submit fully visible in the measured keyboard-safe viewport, revealing the field's hint/error with them where space allows; test real frames rather than a fixed keyboard height. If SE/Duo at xxLarge cannot fit that pair within the existing layout, record an undesigned keyboard state and defer it under OQ 32; hiding the submit, shrinking capped text or inventing a pinned/duplicate action is not an acceptance workaround. Return chain: Sign in email → password → go; Sign up name → email → password → confirmation → go; Reset new → confirmation → go; Forgot email → send; recovery code → go. Number pad has no return: its Verify button must remain reachable above the keyboard; no auto-submit when six digits arrive. AutoFill: email/username, currentPassword/newPassword, oneTimeCode; no autocorrect/capitalization for email/password/codes.
- Sign in starts empty; clear password after **every** attempt, retain email and error/banner. On two-factor result push an in-memory challenge screen; no session before completion. Back → Sign in, discard code/challenge. Clear code after every attempt and on mode changes; recovery mode uses a regular keyboard and consumes each recovery code once. Missing challenge → Sign in; expired/exhausted challenge uses returned field/notice error, with no invented expiry screen. The sample board wrong-code message is a visual field-error example; use actual server keys, not its 30-second claim for every error.
- Welcome's Sign in now mounts AuthSignIn. Forgot/Create account enter auth navigation seams until their Phase 11 screens exist; footer Plan a trip first uses `.guestWizard`. Success accepts the session once, then routes unverified → `.verify`, verified eligible account → existing `.today`; existing terms/walkthrough gate precedence remains. Today has boards but building it is outside this plan; Debug route diagnostics only under D17/OQ 24, no invented Release destination. Never replay splash/Welcome intro on auth navigation or sign-out.
- Forgot transitions to the designed sent Notice after 204 for any address. Open email uses RN's `message://` through the system; a missing handler keeps this designed state, not a fabricated error screen. Reset input requires token+email, otherwise resetExpired; the invalid-token key also selects resetExpired. Send a new link prepopulates Forgot; done creates **no** session. Board reset/done auto-login claims and token-revocation copy need OQ 22/27 before implementation.
- Sign up uses one visibility control for both password fields; clears passwords after every attempt, keeps name/email. Terms/privacy open the existing web `/terms` and `/privacy` URLs (RN `src/config/web.ts:7`), not a new native policy reader. Unverified session → verify seam. Verify waiting/failed is designed; re-check users/me on scene active/return from email, resend uses the real endpoint and deadline `resendAfterSeconds` (0:42 is sample only). Matching account+email+epoch required before updating `has_verified_email`. Failed retry and resend buttons follow the failed board. Back/Use a different email explicitly signs out with discard. No toast or email-changed screen is added.
- Email reset/verify screens may be driven by typed inputs/mock inbox events in tests. **Universal links/app.chronoflow.net delivery is deferred server-side; emails currently go to web pages.** D15/OQ 15 still registers no colliding scheme. Real Forgot/Register/Resend can be implemented and contract-tested; on-device receipt of reset and signed verify inputs cannot be promised. Mock inbox exercises end-to-end transitions without external mail; it has no in-app UI board. Verification after completing the web flow can be detected by users/me on activation. OQ 25 gates production link integration/copy.
- VoiceOver order: back, brand (decorative moon hidden), heading (header trait), description, card banner, fields with labels/value/hint/error, submit/secondary links, footer. On new banner announce localized title+body once using queued `AccessibilityNotification.Announcement`; no announcement for each body redraw/edit. Announce sent notice and screen transitions; associate field errors with their input, retain focus after submit, move to first invalid field where applicable. Password visibility exposes switch state; no duplicate icon readings. Touch targets ≥44 and text/error icon supply non-color cues. Audits follow the root cap, with no inherited Welcome contrast exceptions for auth: report board conflicts and defer corrections to design.

### Auth copy (String Catalog; English sentence keys)

Exact matching values below are copied from RN `nl.json`, not newly translated. `PENDING HUMAN NL` means the board's English is absent from RN (even if RN has similar wording): implementation is blocked until a person supplies/approves it (OQ 28). Dynamic email/time use catalog interpolation, not sample addresses/times; `{{…}}` denotes the RN placeholder here and becomes typed catalog arguments. Labels marked by an OQ are recorded design copy, not authorization to ship conflicting text. AuthStates explanatory documentation headings are not app copy. The designed `changed` screen is out of scope.


**Shared and Sign in**

| English | Dutch / status |
|---|---|
| Back | Terug |
| Back to sign in | Terug naar inloggen |
| ChronoFlow | ChronoFlow |
| Welcome back | Welkom terug |
| Sign in to see your trips and plans. | Log in om je reizen en plannen te bekijken. |
| Email | E-mailadres |
| Password | Wachtwoord |
| Sign in | Inloggen |
| Sign in with a passkey | Inloggen met een passkey |
| or with email | of met e-mail |
| Forgot your password? | Wachtwoord vergeten? |
| Create an account | Een account aanmaken |
| New here? Plan a trip first | Nieuw hier? Plan eerst een reis |

**Two-factor**

| English | Dutch / status |
|---|---|
| Enter your code | Voer je code in |
| Open your authenticator app and type the 6-digit code for ChronoFlow. | **PENDING HUMAN NL — OQ 28** |
| 6-digit code | 6-cijferige code |
| Recovery code | Herstelcode |
| Each recovery code works once. | Elke herstelcode kun je één keer gebruiken. |
| Verify | Bevestigen |
| Use a recovery code instead | Gebruik een herstelcode |
| Use your authenticator app | **PENDING HUMAN NL — OQ 28** |
| That code didn't work. Codes change every 30 seconds, so try the newest one. | **PENDING HUMAN NL — OQ 28** |

**Recovery, reset and verification**

| English | Dutch / status |
|---|---|
| Reset your password | Stel je wachtwoord opnieuw in |
| Enter your email and we'll send you a link to choose a new one. | **PENDING HUMAN NL — OQ 28** |
| Send reset link | Verstuur resetlink |
| Check your inbox. | Bekijk je inbox. |
| If {{email}} has an account, a link to choose a new password is on its way. | **PENDING HUMAN NL — OQ 28** |
| Open email app | Open je e-mailapp |
| Choose a new password | Kies een nieuw wachtwoord |
| You'll be signed in on this phone once it's saved. | **PENDING HUMAN NL — OQ 28** |
| New password | Nieuw wachtwoord |
| At least 10 characters. | Minstens 10 tekens. |
| Confirm new password | Bevestig je nieuwe wachtwoord |
| Save and sign in | **PENDING HUMAN NL — OQ 28** |
| This link has expired | Deze link is verlopen |
| Reset links work once and expire after an hour. We can send you a new one. | Een herstellink werkt één keer en verloopt na een uur. We kunnen je een nieuwe sturen. |
| Send a new link | Nieuwe link sturen |
| Password saved | Wachtwoord opgeslagen |
| You're signed in on this phone. Use your new password next time, here and on the web. | **PENDING HUMAN NL — OQ 28** |
| Other devices stay signed in. If you didn't make this change, reset your password again and contact us. | Andere apparaten blijven ingelogd. Heb je dit niet zelf gedaan? Herstel je wachtwoord dan opnieuw en neem contact met ons op. |
| Continue | Doorgaan |
| Check your inbox | Bekijk je inbox |
| We sent a link to {{email}}. Open it on this phone to finish. | **PENDING HUMAN NL — OQ 28** |
| Resend link | Link opnieuw versturen |
| You can resend in {{time}}. | Je kunt de link over {{time}} opnieuw versturen. |
| Use a different email | Gebruik een ander e-mailadres |
| We couldn't check your email | We konden je e-mailadres niet controleren |
| The link may have expired, or we couldn't reach the server. | De link is misschien verlopen, of we konden de server niet bereiken. |
| Try again | Opnieuw proberen |

**Sign up**

| English | Dutch / status |
|---|---|
| Save your trips and get reminders on this phone. | Bewaar je reizen en ontvang herinneringen op deze telefoon. |
| Name | Naam |
| Confirm password | Bevestig je wachtwoord |
| Show password | Wachtwoord tonen |
| Hide password | Wachtwoord verbergen |
| Create account | Account aanmaken |
| `By creating an account you agree to the <terms>terms</terms> and <privacy>privacy policy</privacy>.` | `Door een account aan te maken ga je akkoord met de <terms>voorwaarden</terms> en het <privacy>privacybeleid</privacy>.` |
| Already have an account? Sign in | Heb je al een account? Log in |

**AuthStates banners**

| English | Dutch / status |
|---|---|
| That email and password don't match. | Dit e-mailadres en dit wachtwoord horen niet bij elkaar. |
| Check both and try again, or reset your password. | Controleer ze allebei en probeer het opnieuw, of herstel je wachtwoord. |
| Too many attempts. | Te veel pogingen. |
| Wait a few minutes before you try again, or reset your password now. | Wacht een paar minuten voordat je het opnieuw probeert, of herstel nu je wachtwoord. |
| Wait a few minutes before you try again. | Wacht een paar minuten voordat je het opnieuw probeert. |
| Something went wrong on our side. | Er ging bij ons iets mis. |
| Try again in a moment. | Probeer het zo meteen opnieuw. |
| There's already an account with this email. | Er is al een account met dit e-mailadres. |
| Sign in instead, or reset your password. | Log in of herstel je wachtwoord. |
| Your details are kept. Try again in a moment. | Je gegevens blijven bewaard. Probeer het zo meteen opnieuw. |
| Too many requests. | Te veel verzoeken. |
| Wait a few minutes before you ask for another link. | Wacht een paar minuten voordat je een nieuwe link aanvraagt. |
| Your new password wasn't saved. Try again in a moment. | Je nieuwe wachtwoord is niet opgeslagen. Probeer het zo meteen opnieuw. |
| We couldn't send the link. Try again in a moment. | We konden de link niet versturen. Probeer het zo meteen opnieuw. |
| Needs a connection | Verbinding nodig |

**Server field messages consumed by these forms**

| English | Dutch / status |
|---|---|
| Please fill this in. | Vul dit veld in. |
| Enter a valid email address, like name@example.com. | Vul een geldig e-mailadres in, zoals naam@voorbeeld.nl. |
| Use no more than :max characters. | Gebruik niet meer dan {{max}} tekens. |
| Use at least :min characters. | Gebruik minstens {{min}} tekens. |
| The passwords don't match yet. | De wachtwoorden komen nog niet overeen. |
| Use both uppercase and lowercase letters. | **PENDING HUMAN NL — OQ 28** |
| Use at least one letter. | **PENDING HUMAN NL — OQ 28** |
| Use at least one number. | **PENDING HUMAN NL — OQ 28** |
| Use at least one symbol. | **PENDING HUMAN NL — OQ 28** |
| This password has appeared in a data leak. Choose a different password. | **PENDING HUMAN NL — OQ 28** |
| Enter the 6-digit code from your authenticator app. | Vul de 6-cijferige code uit je authenticator-app in. |
| Enter one of the recovery codes you saved when you set up two-factor authentication. | Vul een van de herstelcodes in die je hebt bewaard bij het instellen van tweefactorauthenticatie. |
| The authentication code was not accepted. Try again. | De verificatiecode is niet geaccepteerd. Probeer het opnieuw. |
| This recovery code was not accepted. Try another saved code. | Deze herstelcode is niet geaccepteerd. Probeer een andere bewaarde code. |
| This password reset link is invalid or has expired. | Deze link om je wachtwoord te herstellen is ongeldig of verlopen. |
| This email verification link is invalid or has expired. | **PENDING HUMAN NL — OQ 28** |

Passkey/divider copy is retained under settled OQ 20; credential/challenge error translations are specified in the API contract. Password hint depends on OQ 21. Reset auto-login strings depend on OQ 27; the resetDone other-devices claim depends on OQ 22 even though RN has a Dutch value. Offline title exists in RN but **has no board variant** (OQ 23). Do not include the recovery placeholder `xxxx-xxxx` as a prefilled value; it is a sample format from the board. Credentials/emailTaken backend keys classify the named banners rather than displaying duplicate field messages.

**Banner mapping (AuthStates):** Sign in wrong → credentials title + check-both body; Sign in locked → too-many-attempts + reset-now body; generic sign-in/two-factor/forgot failure → server title + try-again body; two-factor throttled → attempts + wait body; Sign up taken → account-exists title + sign-in-instead body; Sign up server → server title + details-kept body; Forgot throttled → requests title + ask-for-another-link body; Reset server → server title + password-not-saved body; Verify resend server → server title + could-not-send body. Wrong/missing codes and password errors stay under their field. AuthStates does not draw arbitrary hidden-field notices, offline or a pending-change discard prompt: those need OQ 23/29/30, not a new ad-hoc layout.

## Tasks

### Phase 0: Scaffold and tooling (`feat/phase-0-scaffold`)

Unblocked (OQ 1–4 settled 5 Nov).

- [x] `git init -b main` (done); first commit `docs: add plan, working rules and design copy` with `plan.md`, `CLAUDE.md`, `AGENTS.md` (Codex reads it; same rules), `_design/canvas/` (five boards, `canvas.json`, `ds/chronoflow/{tokens.json,README.md,components}`, `SOURCE.md` with canvas URL and download date). Branch `feat/phase-0-scaffold`. (`main` holds only `e277d5d`.)
  Files: `plan.md`, `CLAUDE.md`, `AGENTS.md`, `_design/**`.
  Test: one commit on `main`; branch exists.
- [ ] Export board reference frames: render each board in the canvas (Chrome) at the board key frames (ready 0/700/1400/1900, slow 2600/4900, welcome 1500/1950/2400/3300, Welcome final), light and dark; record the method. Notes: board dots are not frozen (`dot()` ignores `frozen`), so dot opacity is excluded; `Main` ignores `at` and loops its intro, so Welcome content at 2400/3300 is compared against the `Main` keyframes, not the render.
  Files: `_design/frames/**`, `_design/frames/README.md`.
  Test: a frame exists for every listed time and theme.
- [x] XcodeGen 2.46.0 is installed. `project.yml`: target `ChronoFlow` (iOS 17.0, iPhone, portrait, Swift 6, Debug ID `net.chronoflow.app.native`, `Local.xcconfig` include for `DEVELOPMENT_TEAM`), `AppUITests`, `PerfUITests`; schemes `ChronoFlow` and `Perf` (Release). `.gitignore`: `*.xcodeproj`, `DerivedData`, `build/`, `Local.xcconfig`; `Local.xcconfig.example` committed. Verify XcodeGen output opens and builds in Xcode 27.2. (Orchestrator verified generation and full build via `make generate && make check`, 5 Nov; AppIcon was unset for that run; OQ 18 icon now settled on RN's 1024 px asset. See `Docs/tooling.md`.)
  Files: `project.yml`, `.gitignore`, `Config/Local.xcconfig.example`.
  Test: `make generate && xcodebuild -scheme ChronoFlow -destination 'platform=iOS Simulator,name=iPhone 17e' build`.
- [x] App shell: `AppDelegate`, `SceneDelegate` (creates the main window with `UIHostingController(rootView: RootView())`), empty `RootView`. (Build and launch verified by the orchestrator's passing window UI tests, 5 Nov.)
  Files: `App/AppDelegate.swift`, `App/SceneDelegate.swift`, `App/RootView.swift`.
  Test: builds and launches.
- [x] Info.plist: `UIApplicationSceneManifest` (one scene, `SceneDelegate`), `UILaunchStoryboardName = LaunchScreen`, `CADisableMinimumFrameDurationOnPhone = YES`, `UIUserInterfaceStyle = Automatic`, portrait only, `UIViewControllerBasedStatusBarAppearance = YES`. Minimal `LaunchScreen.storyboard` (background a temporary `LaunchSky` colour set with skyTop light/dark hex; replaced by TokenGen output in Phase 1). (Spec's Display P3 values; plist/storyboard checks passed. Orchestrator verified full-screen window checks on 17e and Duo, 5 Nov; Duo required its device destination on its own runtime.)
  Files: `App/Info.plist`, `App/LaunchScreen.storyboard`, `App/Assets.xcassets/LaunchSky.colorset/**`.
  Test: `plutil -lint`; app runs full-screen (window bounds equal the device screen) on iPhone 17e and iPhone Duo.
- [x] Package `Packages/ChronoFlowKit`: targets `DesignSystem`, `AppCore` (nonisolated), `Launch`, `Welcome`; UI targets `.defaultIsolation(MainActor.self)`; `defaultLocalization: "en"`; Swift Testing test targets; `swift-snapshot-testing` 1.19.x. Empty `Localizable.xcstrings` in `Launch` and `Welcome`, `App/InfoPlist.xcstrings`; `CatalogTests` fails on any key without an `nl` value. (Resolved 1.19.7; all five tests passed on the host and package/test targets compiled for iOS 17 simulator. Missing-nl failure probe verified and removed; orchestrator verified simulator suites via `make check`, 5 Nov.)
  Files: `Packages/ChronoFlowKit/Package.swift`, `Sources/*/`, `Sources/*/Resources/Localizable.xcstrings`, `App/InfoPlist.xcstrings`, `Tests/*/`.
  Test: one smoke test per target; `CatalogTests` fails on a test key with no `nl`, then passes once removed.
- [x] `.swift-format` (4-space, line 120); `Makefile`: `generate`, `format`, `lint` (`swift format lint --strict -r`), `test`, `snapshots` (pinned iPhone 17e / iOS 27.2), `duo` (window/UI checks with a dynamically resolved Duo destination), `perf`, `tokens`, `fonts`, `assets`, `check` (lint + test + snapshots); `Scripts/ci.sh` = `make generate check`. Confirm which Instruments templates exist in Xcode 27.2 (`xctrace list templates`: Animation Hitches, App Launch) and record them. (Orchestrator verified `make check`, clean-clone `Scripts/ci.sh` exit 0 and both Instruments templates, 5 Nov. Results in `Docs/tooling.md`; generator targets explicitly require Phase 1.)
  Files: `.swift-format`, `Makefile`, `Scripts/ci.sh`, `Scripts/duo-destination.py`.
  Test: `Scripts/ci.sh` passes on a clean clone.
- [x] `CLAUDE.md`: commands; working rules; traps (launch-screen caching: Clean Build Folder, delete app, restart Simulator; `.xcodeproj` is generated; RN repo read-only; fonts registered in the package, not `UIAppFonts`; no masks/filters/shadows in the launch tree; no localised launch storyboard); trailer rule (OQ 1). (Actual commands documented; shared rules and traps remain inherited through `@AGENTS.md`.)
  Files: `CLAUDE.md`.
  Test: review.

### Phase 1: Design tokens, fonts and launch assets (`feat/phase-1-design-system`)

Implementation complete. The orchestrator verified the committed Phase 1 state on 2026-11-05:
`make generate`, `make snapshots` and `make check` passed on iPhone 17e / iOS 27.2, including the
explicit-traits UIKit font test. Four primitive baselines were recorded and visually approved.
`make duo` passed on iPhone Duo's iPhone19-4 iOS 27.2 runtime; generators reproduced with no diff.
Review corrections and their host checks are recorded in `Docs/tooling.md`, along with commands to
validate the revised tree. These results cover 17e and Duo, not the full D1c matrix.

- [x] `Tools/TokenGen` (SwiftPM executable): OKLCH → OKLab → linear P3 (clip) → transfer curve. Writes 9 `.colorset`s (Any/Dark), `LaunchSky` to both catalogs (D10), `CfSky.generated.swift` (per-segment ramp with exact mid stop), `TokenGenReport.md` (sRGB hex).
  Files: `Tools/TokenGen/**`, `Sources/DesignSystem/Resources/Colors.xcassets/**`, `App/Assets.xcassets/LaunchSky.colorset/**`, `Sources/DesignSystem/CfSky.generated.swift`.
  Test: every hex/P3 in the spec table to ±1/255; ramp vs true OKLab at 1000 points ±1/255 both themes; `make tokens && git diff --exit-code`; catalog copies identical.
- [x] `Tools/fonts.sh` (venv with `fonttools`, `brotli`): TTFs from `google/fonts` at a pinned commit (OFL). First confirm the Fraunces source has the `opsz` axis and record SOFT/WONK defaults matching the web's `opsz-normal` build. Figtree static 400–700; Fraunces 400/500 at opsz 20, 32, 48. `FontRegistry.register()` via `CTFontManagerRegisterFontsForURLs(.process)`.
  Files: `Tools/fonts.sh`, `Sources/DesignSystem/Resources/Fonts/**` (+ `OFL.txt`, `SOURCE.md`), `Sources/DesignSystem/FontRegistry.swift`, `Sources/DesignSystem/Typography.swift`.
  Test: every face resolves after `register()`; styles match the typography table.
- [x] `Tools/AssetGen`: `LaunchMoon` (288 pt @2x 576 px / @3x 864 px, glyph 104 pt at offset 92, glow σ 9 α0.45, light #E78A45 / dark #F2AD73, P3) and `LaunchWordmark` (D8) to both catalogs; SVG sources committed.
  Files: `Tools/AssetGen/**`, `Assets/moon/*.svg`, `App/Assets.xcassets/{LaunchMoon,LaunchWordmark}.imageset/**`, `Sources/DesignSystem/Resources/Launch.xcassets/**`.
  Test: dimensions; stroke colour at the glyph's top-left arc; wordmark ink bounds match a CoreText layout of the string; copies identical.
- [x] Primitives: `CfSkyLayer` / `CfSky`, `PressStyle` (Reduce Motion: opacity 0.85, scale 1, no transition), `MoonShape`.
  Files: `Sources/DesignSystem/{CfSky,PressStyle,MoonShape}.swift`.
  Test: light/dark gradient and moon unit coverage; `PressStyle` values with and without Reduce Motion. The unused PatternDots primitive, its tests, tokens and four composite primitive snapshots were removed by the user's 2026-11-06 no-pattern decision.

### Phase 2: System launch screen (`feat/phase-2-launch-screen`)

- [x] `LaunchScreen.storyboard`: background `LaunchSky`; `UIImageView` `LaunchMoon`, content mode `center`, centred X/Y on the superview (not safe area), no size constraints. (Verified by the orchestrator on 2026-11-06: the launch matrix passed on all seven D1c devices — iPhone SE (3rd gen), 17e, 17, Air, 18 Pro, 18 Pro Max and iPhone Duo — and make check and make duo passed. Tests cover both appearances, normal/asymmetric insets, intrinsic centring and rendered asset parity. See Docs/tooling.md.)
  Files: `App/LaunchScreen.storyboard`.
  Test: hosted app test instantiates `UIStoryboard(name: "LaunchScreen")` in a window on every device in the D1c matrix (iPhone Duo required), light/dark; moon glyph centre at (w/2, h/2) ±0.5 pt.
- [x] `LaunchFrameView`: frame 0 drawn the same way (skyTop, `LaunchMoon` at natural size, centred, pixel-aligned); used by the overlay and Reduce Motion. (Verified by the orchestrator on 2026-11-06: the launch matrix passed on all seven D1c devices — iPhone SE (3rd gen), 17e, 17, Air, 18 Pro, 18 Pro Max and iPhone Duo — and make check and make duo passed. Tests cover whole-frame light/dark parity within 2/255, independent moon appearance, resizing/asymmetric insets, accessibility text size, captured appearance and an animation-free tree. Package image tests use the running device’s scale to respect asset thinning. See Docs/tooling.md.)
  Files: `Sources/Launch/LaunchFrameView.swift`, `AppTests/LaunchFrameParityTests.swift`.
  Test: hosted storyboard vs `LaunchFrameView` render, whole frame within 2/255. (The real system launch screen is a cached snapshot and cannot be captured by XCUITest; it is checked by screen recording in Phase 8.)

### Phase 3a: Pure timeline (`feat/phase-3a-timeline`)

OQ 5 follows the settled S1/S2 and listed S3–S6 rules. OQ 11 uses its default below. Verified by the orchestrator on 2026-11-06: all seven D1c devices, make check and make duo passed.

- [x] `CubicBezier`: CSS/CA solver (Newton + bisection), presets `easeOut`, `easeInOut`, `intro`, `linear`. (Pure Sendable solver; CSS references, endpoints, clamping, flat derivatives, overshoot and monotonicity pass on the host. iOS 17 compile/type-check passes; presentation-layer comparison is covered in 3b.)
  Files: `Sources/AppCore/CubicBezier.swift`.
  Test: known CSS reference values to 1e-4 (the presentation-layer comparison is in 3b).
- [x] `FlightPath`: composition-centred cubic for any size (vertical rule settled by the user 2026-11-06), 1024-sample arc-length table, `point(atFraction:)`, fraction curve. (OQ 11 default assumed, confirm) for x scaling. The 1024-entry table and 128 moving position keys preserve the 560 ms fraction knot. Host numerical and rendered stroke-tip tests pass every 10 ms; cubic trimming drift required the specified sampled-polyline fallback for the displayed path. Board length/apex and short/wide fixtures pass; iOS 17 compile/type-check passes.
  Files: `Sources/Launch/FlightPath.swift`.
  Test: length 505.8 ± 0.2 on 390 × 844; apex (195, 512.5); plane = stroke tip every 10 ms.
- [x] `MoonTarget` fallback math (pure): centre from safe insets and row height. (OQ 10 default assumed, confirm). Pure fallback uses the specified RN padding and row-height rule, with content bounds from all four safe insets. Board (38, 78), larger rows and asymmetric/short/wide host fixtures pass. Hosted running-device tests cover the D1c matrix and type-check for iOS 17.
  Files: `Sources/AppCore/MoonTarget.swift`.
  Test: board target (38, 78) on 390 × 844 with insets 47/34 → padding rule; all pinned devices; larger row height moves the centre.
- [x] `LaunchTimeline.opening` (incl. Reduce Motion) and `sample(at:)`. (Pure Sendable scalar/point tracks, absolute seconds from t0, one track per layer/key path. Every opening key/curve, all specified sample times, plane/stroke agreement every 10 ms and static Reduce Motion frame pass on the host; detached-task use and iOS 17 compile/type-check pass. No scene wiring in this phase.)
  Files: `Sources/Launch/LaunchTimeline.swift`, `Sources/Launch/LayerID.swift`.
  Test: table test of every key; `sample` at 0, 300, 700, 1100, 1400, 1500.
- [x] `withReadyExit`, `withStatus`. (OQ 6 default assumed, confirm). Reduce Motion uses the 300 ms ease-out fade and dots held at 1.0. Ready clamps to 1500 ms only with motion; status latches, pulses repeat from mount with three delayed replicas, and repeated endings replace prior endings. Host tests cover keys, fade samples, opening preservation and both composition orders; iOS 17 compile/type-check passes.
  Files: `Sources/Launch/LaunchTimeline+Ready.swift`.
  Test: keys; merged tracks keep opening keys intact (sample at 700 unchanged after adding an exit at 1500).
- [x] `withWelcomeExit`. (OQ 6 default assumed, confirm). No moon cross-fade; stars were subsequently removed by the user on 2026-11-06. (OQ 7 default assumed, confirm). W starts at max(1600 ms, resolution time). Host tests cover every ending key, one straight-line progress for centre/scale, landing within 0.01 pt, changed targets, late endings, opening preservation when added at 50 ms and Reduce Motion. Hosted D1c landing tests and the continuing matrix runner are written; iOS 17 compile/type-check passes.
  Files: `Sources/Launch/LaunchTimeline+Welcome.swift`.
  Test: moon lands on a given target to 0.01 pt; opening keys intact when added at 50 ms.

### Phase 3b: Core Animation scene (`feat/phase-3b-scene`)

Verified by the orchestrator on 2026-11-06: all seven D1c devices, make check and make duo passed. Device runs need OQ 4 (team) and OQ 14 (device). The physical-device D3 proof stays open; Phase 3c snapshot work proceeds by user direction.

- [x] `LaunchScene` layers (landed as one commit; accepted): sky/band; sun/halo; path/plane; moon/wordmark; status (text created lazily + replicated dots). `apply(_:)` sets model values from `sample`. (OQ 6 default assumed, confirm). Stars were removed by the user on 2026-11-06; Reduce Motion dots hold at 1.0, with the existing ease-out fade and no moon cross-fade. Complete layer tree, radial sun/clipped halo with generated alpha ramps, sampled path, baked plane glow, generated moon/wordmark and lazy localized status are implemented. The halo has a 250 pt radius and the sun has the designed 127.3 pt radius on both axes; host pixel tests verify both gradients at 2×/3×. Sampled scale transforms retain Z = 1 so render(in:) draws the moon and container at their sampled sizes. Frame geometry uses 1e-9 accuracy for anchor arithmetic residuals. Host tests and iOS 17 type-check pass.
  Files: `Sources/Launch/LaunchScene.swift`, `Sources/Launch/LaunchScene+Layers.swift`, `Sources/Launch/StatusLineLayer.swift`.
  Test: layer list equals the spec; no layer has `mask`, `filters`, `compositingFilter` or `shadowOpacity > 0`.
- [x] `LaunchOverlayController` + `SceneDelegate` order (D3, D14): overlay window (root VC `preferredStatusBarStyle = .lightContent`, VoiceOver element "ChronoFlow is opening" with its `nl` in the same commit), `isHidden = false`, opening tracks added, `CATransaction.flush()`, `t0` recorded; main window + root next run-loop turn; font registration detached; capture `connectionOptions` into `PendingLaunchIntent`. Verify which window drives the status bar; if not the overlay, set it on the main hosting controller until hand-off. Overlay is committed before scheduling the SwiftUI root, fonts register detached, intents are captured without routing, and a process-owned gate prevents replay. Both controllers request light status bars. Hosted ordering/reconnection/accessibility tests and UI coverage are written and iOS 17 type-checked. Actual status-bar appearance stays open (needs a device; open).
  Files: `Sources/Launch/LaunchOverlayController.swift`, `Sources/AppCore/PendingLaunchIntent.swift`, `App/SceneDelegate.swift`, `Sources/Launch/Resources/Localizable.xcstrings`.
  Test: signposts show `overlay-first-commit` ends before the root's first layout; UI test finds the element; a second scene connection mounts no overlay.
- [x] Launch arguments: `-cf.freezeAt <ms>` (container `speed = 0`, `timeOffset`), `-cf.mode ready|slow|welcome` (applies `withReadyExit(1500)`, `withStatus(2000)` + exit at `-cf.readyAt` (default 4600), or `withWelcomeExit(1600, fallback target)` without the coordinator), `-cf.mainThreadStall <ms>` (blocks main at 300 ms). (OQ 10 default assumed, confirm). Fallback landing uses all four safe insets and the current text size (28 pt row at the default category). (OQ 11 default assumed, confirm) for x scaling. Vertical anchoring now follows the user's 2026-11-06 composition rule. Arguments, merged playback and live freeze are implemented; parser/mode tests, light/dark sample-vs-presentation comparisons every 100 ms (0–3200) and the independent 700 ms XCUITest model reference are written and iOS 17 type-checked. Because tracks retain absolute nonzero t0, freezing uses timeOffset = t0 + elapsed seconds; elapsed alone would predate every animation. Position and interior-opacity comparisons use a 0.0005 tolerance for CA’s duration-dependent solver epsilon at 1 s. The independent host bisection reference checks all four presets at 1001 progress values to 0.0001; the tighter intro(0.95) = 0.9997243836889174 regression remains at 1e-12. The screenshot retains its original error limits, measures errors away from edges and the moon’s best alignment shift (≤0.5 pt), and includes 1 pt offset/20% opacity mutation checks. Runner and comparison fixtures pass.
  Files: `Sources/Launch/LaunchScene+Freeze.swift`, `App/LaunchArguments.swift`.
  Test: hosted test: `sample(at:)` equals `layer.presentation()` values on a frozen container at 0…3200 every 100 ms (this is also the bezier solver check against CA); XCUITest screenshot at `-cf.freezeAt 700` matches the 700 snapshot within tolerance.
  Runner: `python3 -I Scripts/launch-simulators.py --scene` covers all seven D1c devices and then attempts both `make check` and `make duo`.
- [ ] Signpost intervals ("Points of Interest"): `launch` (scene connect → overlay removed), `first-commit` (scene connect → flush), `session`, `ready`, `exit`, `intro`. Early D3 proof: one device Animation Hitches run with `-cf.mainThreadStall 500`. (OQ 14 default assumed, confirm). Proposed budget retained. Interval APIs, idempotent pairing tests and real connection/flush/root-layout markers are implemented; readiness/exit/intro call sites remain in Phases 4/5. Device trace, zero-hitch and ProMotion pacing proof are not run (needs a device; open). OQ 4 team and the reference device are still missing. See `Docs/perf/2026-11-06-d3-spike.md`; Phase 3c proceeds by user direction, and snapshots must be re-checked if the device proof changes the layer tree.
  Files: `Sources/AppCore/LaunchSignposts.swift`, `Docs/perf/<date>-d3-spike.md`.
  Test: 0 hitches in 0–1500 ms with the stall; frame intervals ≈ 8.3 ms on ProMotion. If this fails, stop and revisit D3 before Phase 3c.

### Phase 3c: Splash snapshots (`feat/phase-3c-snapshots`)

- [x] Implement the sampled splash snapshot suite and commit the 154 recorded baselines: all eleven frames in light/dark on every D1c device, opt-in recording, running-window and asymmetric/side-only inset geometry, host coverage and S1 checks. Pin `make test` and `make snapshots` to en/US and resolve slow snapshot copy from the explicit English Launch catalog. Host checks cover baseline completeness and Makefile language arguments. Verified by the orchestrator on 2026-11-06: all seven D1c devices passed snapshot comparison, hosted tests and both appearance UI tests; make check and make duo passed.
  Files: `Tests/LaunchTests/LaunchSnapshot*.swift`, `Tests/LaunchTests/__Snapshots__/**`, `Package.swift`, `Makefile`, `Tests/test_launch_resources.py`.
  (OQ 6 default assumed, confirm). (OQ 10 default assumed, confirm). (OQ 11 default assumed, confirm). Snapshot work proceeds before the physical-device D3 proof by user direction; re-check if that proof changes the layer tree. The D3 device task stays open (needs a device; open).

- [ ] Snapshots via `sample(at:)`, light and dark, on iPhone 17e for the full set and on every D1c device (iPhone SE, Air, 18 Pro Max, iPhone Duo at least) for 0, 1400 and welcome 2400; a geometry test asserts on each size that the moon glyph, wordmark and status stay fully inside the window and its horizontal safe area. Per the user's composition decision of 2026-11-06, the sun stays horizontally inside those safe bounds with its top inside the window and at least one third of its height visible; only its bottom may extend past the window. The path retains its designed horizontal endpoint bleed and stays vertically inside the window:
  ready 0, 700, 1400, 1700 (↔ board 1900), 1900; slow 2600, 4900 (readyAt 4600); welcome 1500, 1950, 2400 (fallback target); Reduce Motion 0.
  Files: `Tests/LaunchTests/LaunchSnapshotTests.swift`, `Tests/LaunchTests/__Snapshots__/**`.
  Test: recorded, reviewed side by side with `_design/frames/`, then pass. Status vs path apex: assert and record the relation on 844 and 874 (S1).
  Note: implementation and initial recorded baselines are complete above; acceptance stays open for PNG/board-frame approval. `_design/frames/` is absent. Full path containment conflicts with the designed endpoints, which bleed 10 pt beyond both edges; no inset redesign/default is provided. Tests preserve the bleed and assert vertical bounds/clipping. The user settled OQ 11's vertical part on 2026-11-06: preserve the 844 pt board's composition at every height. The SE/Duo collisions and 874 pt S1 crossing are resolved in geometry; ordinary clearance assertions replace the known issues. S1 now retains status top minus apex = 5.5 pt at both 844 (518 / 512.5) and 874 (533 / 527.5). Replacement non-844 launch recordings and their visual approval remain open. The 844 references are compared even in record mode to guard unchanged board frames, except the two Welcome-exit samples changed by the subsequent no-pattern decision.

- [x] Add the `--snapshots` D1c runner mode with compare-only default, optional record pass only under `SNAPSHOT_RECORD=1`, explicit en/US, failure continuation and final `make check` / `make duo`. Fixture tests cover recording isolation, all devices, failures and Duo runtime selection.
  Files: `Scripts/launch-simulators.py`, `Tests/test_launch_simulators.py`.

- [x] Document the committed snapshot entry point, explicit recording/language rules, geometry limits and the orchestrator's dated results.
  Files: `Docs/tooling.md`.

### Phase 3b review fixes

- [x] Guard notification payloads with `JSONSerialization.isValidJSONObject` before serialization. Capture identifier/action/payload/text through a testable AppCore function; Date, Data, non-string keys, nested invalid values and nonfinite numbers retain response metadata with nil JSON. Host tests also cover valid JSON and empty payloads.
  Files: `App/SceneDelegate.swift`, `Sources/AppCore/PendingLaunchIntent.swift`, `Tests/AppCoreTests/LaunchLifecycleTests.swift`.

- [x] Resolve the overlay opening accessibility label immediately after the first flush and first-commit signpost, keeping string-table I/O out of construction. Hosted tests check the label is absent before commit and available afterward; connection accessibility assertions are retained.
  Files: `Sources/Launch/LaunchOverlayController.swift`, `App/SceneDelegate.swift`, `AppTests/LaunchConnectionTests.swift`.

- [x] Pin device appearance before launching frozen screenshot parity in separate light/dark UI tests. After setting appearance, terminate any running instance, return to SpringBoard and poll the device's reported appearance with a 10-second bound before launch. Async teardown terminates the app and waits for appearance restoration before the next test. Each appearance must match its own model and clearly differ from the opposite model; retain displacement/opacity mutation checks. Hosted connection assertions check the overlay window inherits the scene style. Verified by the orchestrator on 2026-11-06: all seven D1c devices passed snapshot comparison, hosted tests and both appearance UI tests; make check and make duo passed.
  Files: `AppUITests/LaunchSceneTests.swift`, `AppTests/LaunchConnectionTests.swift`.

- [x] Record the accepted single-commit delivery of the scene layers and replace superseded Phase 3a/3b simulator narratives with the dated verified results. Retain the rendering/clock/solver rationale and physical-device open items.
  Files: `plan.md`, `Docs/tooling.md`.

### Phase 4: Readiness and hand-off (`feat/phase-4-readiness`)

Defaults authorized for OQ 7, 8, 9, 15 and 16; confirmation remains open. Verified by the orchestrator on 2026-11-06: all seven D1c devices passed Debug plus the isolated Release check; `make check` and `make duo` passed.

- [x] `Route` (`.welcome`, `.today`, `.signIn`, `.guestWizard`, `.terms`, `.verify`, `.walkthrough`) and `Navigator`; `RootView` mounts the gate's route from its first frame; Debug-only route screen per OQ 8.
  Files: `Sources/AppCore/Route.swift`, `App/RootView.swift`, `App/Debug/RoutePlaceholder.swift`.
  Test: hosted navigator tests cover every route and the unresolved state; Phase 4 UI tests read route identifiers after hand-off. (OQ 8 default assumed, confirm). Route seam plus Debug-only route-name placeholders, including the temporary Welcome seam until Phase 5; Release renders no placeholder text. Verified by the orchestrator on 2026-11-06: full D1c Debug plus isolated Release, `make check` and `make duo` passed.
- [x] Reducer, `LaunchClock` (`CACurrentMediaTime`, `t0` from D3), `ManualLaunchClock`.
  Files: `Sources/AppCore/LaunchReadiness.swift`, `Sources/AppCore/LaunchCoordinator.swift`, `Sources/AppCore/LaunchClock.swift`.
  Note: pure reducer, media/manual clocks and staged coordinator are implemented. A cancellable stored-data stream extends the one-shot seam so a first load can move false → true. (OQ 7 default assumed, confirm). Late signed-out starts at resolution; unknown session defaults signed out at eight seconds. Reducer/clock/coordinator tests are written; the orchestrator verified the full D1c Debug plus isolated Release checks, `make check` and `make duo` on 2026-11-06.
  Tests: ending chosen once; hand-off waits for animation and readiness; signed out ready at once; terms/verify/walkthrough ready without data; ready before 1500 emits exit at 1500; status committed at 2000 only when `hasStoredData == false`, cancelled if ready first, never for `nil`, latched; 8 s forces readiness and `allowFirstLoad` once for the current session; unresolved session at 8 s → OQ 7 default; welcome exit emitted on first anchor, re-emitted on anchor change before W, fallback at W − 50; Reduce Motion skips the wait; exit once; `PendingLaunchIntent` never changes the ending.
- [x] `SessionStore` + `KeychainSessionStore` (native service `net.chronoflow.app.native`, account `session`, JSON `{token, accountId}`; malformed → delete, signed out). `StubReadiness` via `-cf.session`, `-cf.gate`, `-cf.stored yes|no|never`, `-cf.readyDelay <s>`. Release wiring: signed out always (only the perf path runs Release).
  Files: `Sources/AppCore/SessionStore.swift`, `App/Readiness/KeychainSessionStore.swift`, `App/Readiness/StubReadiness.swift`, `App/LaunchArguments.swift`, `project.yml`, `Tests/test_launch_resources.py`.
  Test: protocol-backed in-memory parse/delete tests, hosted Keychain round-trip/malformed deletion, Debug parser/delayed-update and Release override-isolation tests are written. Simulator signing is ad-hoc without a team so the hosted app can use Keychain. The stub explicitly implements the async stream requirement; concrete and protocol calls share the injected absolute deadline. Tests use sleep-registration expectations, cover passed deadlines/cancellation and keep each iterator within one detached task. The orchestrator's 6 Nov Debug pass found unsigned Keychain access and a missing manual-clock sleep/readiness update; the orchestrator verified the full D1c Debug plus isolated Release checks, `make check` and `make duo` on 2026-11-06. (OQ 9 default assumed, confirm). Native-only key; migration deferred until a bundle switch. (OQ 15 default assumed, confirm). No URL scheme. Release always resolves signed out; the readiness store performs no synchronous I/O on the main actor.
- [x] Hand-off wiring: coordinator effects rebuild the timeline (D4); "Getting your plan ready" + `nl` added; on exit completion (`CATransaction` completion block) hide and release the window, clear `accessibilityElementsHidden`, post `.screenChanged`, restore status bar; announce status once, queued.
  Files: `Sources/Launch/LaunchOverlayController.swift`, `Sources/Launch/StatusLineLayer.swift`, `Sources/Launch/Resources/Localizable.xcstrings`, `App/SceneDelegate.swift`.
  Note: merged timeline effects, isolated exit-opacity CATransaction completion, stale-completion guards, window release, accessibility restoration/queued status and session/ready/exit signposts are implemented. Existing Launch catalog already contains both status translations. The root is created only once a route resolves, on the next main-loop turn. (OQ 16 default assumed, confirm). Every cold process start splashes; reconnects do not replay. The orchestrator's 6 Nov Debug pass found intermittent immediate weak-reference assertions after teardown. Lifetime tests now use scoped autorelease pools and bounded run-loop draining before requiring deallocation, including disconnection during a pending exit; production completion captures remain weak and both delegate references are cleared. Hosted and UI tests are written; the orchestrator verified the full D1c Debug plus isolated Release checks, `make check` and `make duo` on 2026-11-06. Welcome visuals, measured anchor publication and intro remain Phase 5. Device status-bar/performance checks remain in the open Phase 3b/8 tasks.
  Test: UI tests: signed out → `Route.welcome`; signed in + ready → `Route.today`; `-cf.stored no -cf.readyDelay 3.5` → status, hand-off ≈ 3.5 s; `-cf.stored never` → hand-off at 8 s; element tree hidden until hand-off.

- [x] Add the `--readiness` D1c simulator runner mode, en/US throughout, all Phase 4 Debug hosted/UI suites plus Release override-isolation tests, failure continuation and final `make check` / `make duo`; include readiness UI checks in `make duo`. The dedicated `ReadinessRelease` scheme builds only the app and hosted tests, with testability enabled only for that verification command; package test bundles stay in Debug. Fixture tests cover the full matrix, failure aggregation, scheme isolation and Duo runtime selection. Verified by the orchestrator on 2026-11-06: full D1c Debug plus isolated Release, `make check` and `make duo` passed.
  Files: `Scripts/launch-simulators.py`, `Tests/test_launch_simulators.py`, `Makefile`, `project.yml`.

- [x] Document the committed readiness runner, Debug argument units/defaults, native Keychain shape, simulator ad-hoc signing, Release behavior and verified 2026-11-06 simulator results and open device validation; update the shared signing trap.
  Files: `Docs/tooling.md`, `AGENTS.md`, `CLAUDE.md`.

### Phase 5: Welcome, intro and moon hand-over (`feat/phase-5-welcome`)

OQ 10 scaling settled by the user on 2026-11-06: cap at xxLarge. Defaults authorized for its padding/scrolling, OQ 12 and OQ 6; confirmation remains open.

- [x] `WelcomeView` per layout and typography, one `CfSky`, scroll view; six strings with `nl` in the same commit; header trait; reading order.
  Files: `Sources/Welcome/WelcomeView.swift`, `Sources/Welcome/WelcomeBrand.swift`, `Sources/DesignSystem/Buttons.swift`, `Sources/Welcome/Resources/Localizable.xcstrings`.
  Test: snapshots on the D1c matrix (iPhone Duo required), light/dark, en/nl, default and OQ 10 sizes; on 390 × 844 the board geometry above; on Duo nothing sits under the side rail or horizontal insets.
  Note: implemented the Main board with generated metrics, one sky (dots removed by the user 2026-11-06), scroll/space-between groups, exact typography, header trait and source reading order. All six Dutch values match RN `src/i18n/locales/nl.json`. (OQ 10 default assumed, confirm). RN padding and scrolling apply to all four safe insets. The user settled scaling on 2026-11-06: cap centrally at xxLarge, including xxxLarge and AX1–AX5. Test default/xxLarge and AX5 equality on every D1c device. Snapshot recording/comparison, board-frame approval and simulator geometry validation remain open; no new baselines are claimed.
- [x] Moon anchor → `MoonAnchorStore` → `LaunchEvent.moonAnchor`.
  Files: `Sources/AppCore/MoonAnchorStore.swift`, `Sources/Welcome/WelcomeBrand.swift`.
  Test: UI test at `-cf.freezeAt 2300`: flying moon centre within 0.5 pt of Welcome's moon on every D1c device (iPhone Duo required), and at the largest agreed text size.
  Note: Welcome publishes the glyph's actual global frame through a validated, deduplicating store into the coordinator; pre-flight updates rebuild the merged track. Root layout waits for detached font registration. Diagnostic Welcome now mounts the real screen and exposes presentation/measurement values for the frozen UI test. Default/AX5 UI and real-coordinator hosted landing tests are written; simulator validation remains open. (OQ 6 default assumed, confirm). Keep the flying moon's stroke/glow and the unanimated Welcome glyph as drawn, with no cross-fade. (OQ 10 default assumed, confirm). RN padding/scrolling and the root xxLarge cap apply; the measured frame replaces fallback geometry.
- [x] `IntroItem` (index, `LaunchIntro` from environment: start, clock, optional frozen time); live `.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.45).delay(start + offset − now)`; first launch of the process only.
  Files: `Sources/Welcome/IntroItem.swift`, `Sources/AppCore/LaunchIntro.swift`.
  Test: offsets; snapshots at 2400, 2450, 2700, 3200, 3300; second appearance has no intro.
  Note: all six stagger offsets share the overlay media clock, including late session resolution; frozen sampling uses the same intro bezier. The moon stays fixed. A claimed intro survives overlay teardown, while route revisits, reconnects and Reduce Motion render the final screen. The intro signpost spans W+700 through W+1600 independently of overlay removal. Host timing/claim tests and en/nl light/dark frozen snapshots at all five times are written; simulator comparison remains open.
- [x] Buttons → `Navigator`: "Plan my trip" → `.guestWizard`, "Sign in" → `.signIn`; `PressStyle`; 52 pt.
  Files: `Sources/Welcome/WelcomeView.swift`.
  Test: UI tests for both routes; `performAccessibilityAudit()` on Welcome.
  Note: native SwiftUI Buttons retain the board's dawn/sky pills, generated 52 pt minimum height, scalable labels and shared PressStyle, including the diagnostic Reduce Motion override. Both route UI tests, Dutch AX5 scroll reachability, reading-order geometry and full accessibility audits in en/nl and both appearances are written; simulator execution remains open. Fix round 4: audit at the top, then swipe up at most eight times until Sign in is hittable and fully inside the window; assert both actions are fully visible before the second audit. Both passes share the same handler and five board-contrast pairs, including Plan my trip. Partial/empty/outside frame regression tests are included. Fix round 5: keep the partial-visibility rule: the handler ignores exact `.contrast` issues only for explicit board pairs or an element whose current frame fails `isFullyVisible` against the app window; a nil element and every other issue still fail. Diagnostics include `partiallyVisible` and the ignore decision. Decision regressions cover partial contrast, fully visible non-board contrast, partial non-contrast/combined types, nil elements and all explicit board pairs. Fix round 6: the orchestrator confirms the SE Dutch Plan button is fully visible in both appearances, correcting round 5's partial-visibility explanation for that failure. The audit's element screenshot measures text 6.76:1 on the dawn pill and pill 1.40:1 against the sky. Add `(welcome.plan, .contrast)` to the explicit board pairs; preserve the designed dawn/dawn-foreground tokens. The second pass still requires both actions fully visible. Revised simulator execution remains open; fold rounds 5/6 into the action/audit-scroll commit that introduced the allow-list. Scrolling with the long Dutch headline is by design. (OQ 10 default assumed, confirm). RN scrolling/padding retained. (OQ 12 default assumed, confirm). Plan my trip opens `.guestWizard` (WizardWhereGuest); the stale board link still needs a designer update. Destination screens remain the existing OQ 8 seams.

- [x] Add the `--welcome` D1c runner mode: optional Welcome-only record pass, full comparison/hosted/UI pass, pinned en/US, failure continuation, final `make check` and `make duo`; include Welcome checks in `make duo`. Fixtures verify recording isolation, all seven devices, Duo runtime selection and failure aggregation. Simulator validation remains open.
  Files: `Scripts/launch-simulators.py`, `Tests/test_launch_simulators.py`, `Makefile`, `Package.swift`.

- [x] Document the committed Welcome matrix/recording entry points, the root xxLarge scaling policy, source translations, measured hand-over, shared-clock intro and host checks. Keep Phase 5 simulator, baseline and visual approval open until verified results are reported.
  Files: `Docs/tooling.md`.

### Phase 5 fix round 1

The orchestrator's 2026-11-06 record passes completed on all seven D1c devices, but all 196 Welcome
PNGs were blank. Comparison, `make check` and `make duo` failed. The accessibility audits reported
144 contrast failures, nine near failures and twelve English clipping issues without element details.
The supplied iPhone 18 Pro app screenshots render the actual Welcome in both themes; inspection against
`Main.dc.html` confirms the board's typography, text, card and pill surfaces. Formal visual approval stays open.

- [x] Capture Welcome through `drawHierarchy(afterScreenUpdates: true)` in a key, visible, explicitly laid-out hosting window, with explicit appearance/category/own display-scale traits and key-window restoration. Reject failed, uniform and transparent captures before snapshot verification. Add synthetic guard mutations and independent final-screen comparisons across both appearances/languages at default/xxLarge. Exercise asymmetric horizontal insets at every Dynamic Type size. Discard the 196 invalid recordings; replacement baseline recording/comparison remains open.
  Files: `AppTests/WelcomeSnapshotTests.swift`, `AppTests/WelcomeSnapshotPixels.swift`, `AppTests/WelcomeSnapshotGuardTests.swift`, `AppTests/WelcomeSnapshotReference.swift`, `AppTests/__Snapshots__/README.md`.
  Test: two portable pixel-guard tests pass on the host; iOS 17 type-check passes. UIKit execution and 196 replacement baselines await the D1c simulator run.

- [x] Log every accessibility issue's audit type, optional identifier/label and compact description to the console and retained attachments. Ignore only the five confirmed `(identifier, .contrast)` pairs listed below, whose token assignments and font weights match `Main.dc.html`, plus round 5's partial-visibility contrast rule; fail unknown/nil identifiers on fully visible elements, combined audit types, clipping and every other issue. Add exception-policy tests. Preserve the designed colours.
  Files: `AppUITests/WelcomeTests.swift`.
  Test: iOS 17 type-check passes; simulator diagnostics and revised audit results remain open.

- [x] Resolve the English `welcome.eyebrow` clipping identified by the orchestrator on 2026-11-06. Give the positively tracked label its intrinsic horizontal size while retaining the board's Figtree 600, 12/16 and +1.2 tracking. Hosted tests compare its frame with the attributed string's natural width at every category in en/nl, and UI tests audit clipping at xxLarge and AX5. No clipping issues are ignored; simulator validation remains open.
  Files: `Sources/DesignSystem/WelcomeText.swift`, `AppTests/WelcomeSnapshotTests.swift`, `AppUITests/WelcomeTests.swift`.

- [x] Keep Welcome recording opt-in and isolated to the hosted Welcome snapshot and guard suites, and include the isolated Release readiness/diagnostics check in each device's comparison pass. Continue from Debug failure to Release and through the full D1c matrix, then attempt both `make check` and `make duo`. Fixtures cover pass ordering, recording isolation and Release execution after Debug failure.
  Files: `Scripts/launch-simulators.py`, `Tests/test_launch_simulators.py`.
  Test: all 28 runner fixtures pass on the host; simulator execution remains open.

- [x] Document the corrected capture/guard contract, diagnostic audit policy, verified failed first run and pending replacement recording/accessibility acceptance through committed entry points.
  Files: `Docs/tooling.md`.

- [ ] Welcome contrast per board tokens: `welcome.eyebrow`, needs design decision. Open pair: `(welcome.eyebrow, .contrast)`, Figtree 600, `dawn` on `cf-sky`; no corrective design/default exists.
- [ ] Welcome contrast per board tokens: `welcome.headline`, needs design decision. Open pair: `(welcome.headline, .contrast)`, Fraunces 400, `skyTitle` on `cf-sky`; no corrective design/default exists.
- [ ] Welcome contrast per board tokens: `welcome.copy`, needs design decision. Open pair: `(welcome.copy, .contrast)`, Figtree 400, `skyCopy` on `skyCopyBackground`; no corrective design/default exists.
- [ ] Welcome contrast per board tokens: `welcome.signIn`, needs design decision. Open pair: `(welcome.signIn, .contrast)`, Figtree 500, `skyCopy` on `skyCopyBackground`; no corrective design/default exists.
- [ ] Welcome contrast per board tokens: `welcome.plan`, needs design decision. Measured on SE nl: text 6.76:1 on the pill, pill 1.40:1 against the sky (the audit flags it). No corrective design/default exists.
- [ ] Accept the 196 replacement Welcome references and revised accessibility results on every D1c device, then pass `make check` and `make duo`. The failed 2026-11-06 run is recorded above; no replacement result is claimed.

### Phase 5 user decisions and fix round 2 (2026-11-06)

- [x] Cap Dynamic Type at xxLarge once at RootView and on both production windows. Clamp explicit font traits and MoonTarget fallback row metrics through shared ContentSizeCap; the status layer uses the capped font and scaled line height. Tests compare AX5 with xxLarge for fonts, status pixels, row height, Welcome frames/pixels and action reachability, retaining different large-size output. The moon UI landing test uses AX5 with the existing 0.5 pt tolerance. OQ 10's scaling part is settled by the user; simulator execution remains open.
  Files: `App/RootView.swift`, `App/SceneDelegate.swift`, `App/LaunchArguments.swift`, `Sources/DesignSystem/ContentSizeCap.swift`, `Sources/DesignSystem/Typography.swift`, `Sources/Launch/StatusLineLayer.swift`, `AppTests/ContentSizeCapTests.swift`, `AppUITests/WelcomeTests.swift`, `AGENTS.md`.

- [x] Reuse RN's opaque 1024 px icon unchanged in the universal iOS AppIcon asset and enable AppIcon compilation for the iPhone app. Host tests check dimensions, absence of alpha/transparency and exact RN bytes; a hosted test checks the built CFBundleIcons primary name. OQ 18 icon settled by the user on 2026-11-06. (OQ 18 default assumed, confirm). No distinguishing Debug display name. Dark/tinted variants and a layered Liquid Glass icon need design assets; those remain Open. Built-icon validation remains open.
  Files: `App/Assets.xcassets/AppIcon.appiconset/**`, `project.yml`, `Tests/test_launch_resources.py`, `AppTests/AppIconTests.swift`, `AGENTS.md`.

- [x] Move Welcome snapshots and capture guards to hosted AppTests, keeping baselines alongside them and AppTests dependent only on ChronoFlow. Compare decoded RGBA pixels without linking package products again. Keep failed/uniform/transparent and opposite-language/appearance guards, with explicit own-scale/style traits and key-window restoration. make snapshots and the Welcome-only record pass select the hosted suites. The orchestrator's second package capture attempt failed on every device because the bare xctest process had no render-server connection; replacement recording/comparison remains open.
  Files: `AppTests/WelcomeSnapshot*.swift`, `AppTests/__Snapshots__/**`, `project.yml`, `Package.swift`, `Makefile`, `Scripts/launch-simulators.py`, `Tests/test_launch_resources.py`.

- [x] Replace 50 ms launch-connection sleeps with a bounded wait for the root window after async font registration. Freeze diagnostic Welcome at zero so overlay teardown cannot race the accessibility/order assertions. Retain the synchronous no-root/flush checks, flush-before-root-layout ordering, modal accessibility, and reconnect-no-replay assertions; disconnect both test delegates deterministically. Simulator validation remains open.
  Files: `AppTests/LaunchConnectionTests.swift`.

- [ ] Record and accept replacement Welcome baselines after the cap and hosted capture changes on every D1c device, including SE, 17e and Duo. Compare all references, pass the strict audits, make check and make duo; visual approval remains open. Only the four confirmed board-contrast identifiers (eyebrow, headline, copy, signIn) are allowed; all other issues fail.

### Phase 5 fix round 3 (2026-11-06)

The orchestrator reports that hosted Welcome recording succeeded on all seven D1c devices. Comparison
found the expected Dynamic Type cap audit failures and one intermittent dark English 2400 ms intro
mismatch on iPhone18,4. This round's revised comparison, make check and make duo remain open.

- [x] Audit all accessibility types except `.dynamicType`, honoring the user's 2026-11-06 xxLarge cap. Assert the exact audit type set with that decision in the failure message; retain the four board-contrast pairs and strict handling of every other reported issue.
  Files: `AppUITests/WelcomeTests.swift`.
  Test: audit selection and exception-policy tests written; simulator execution remains open.

- [x] Isolate frozen intro modifiers from live state/tasks and disable animation transactions for the sampled tree and its on-appear claim. The capture already awaits fonts and uses a fixed sample time; final content could mount before the intro claim. Present the frozen sample on the first body pass, then claim that same intro on appearance. Wait for the claim as well as measured frames; compare exact pixels/frames across clock advances, ten separate mounts at 2400 ms, and repeated render passes at every frozen sample in both locales/appearances, rejecting live layer animations. Keep pixel tolerance unchanged.
  Files: `Sources/Welcome/IntroItem.swift`, `Sources/Welcome/WelcomeView.swift`, `AppTests/WelcomeSnapshotTests.swift`.
  Test: repeated frozen pixel regression written; simulator execution remains open.

- [x] Extend the committed Welcome matrix runner's opt-in recording: `SNAPSHOT_RECORD=1` records Welcome only, `launch` records launch only, `all` records both. Keep all seven record passes before comparison, isolated Release comparison after Debug failures, cleared recording flags and final make check/make duo. Add selection and failure-continuation fixtures.
  Files: `Scripts/launch-simulators.py`, `Tests/test_launch_simulators.py`.

- [x] Document round 3 audit/frozen capture behavior, the user's composition/plain-sky decisions, S1's equal 844/874 relation, removed primitive fixtures and the committed launch/Welcome recording modes. Record only the orchestrator's supplied hosted-record success and outstanding failures; revised matrix/visual acceptance stays open. Fix round 4: the orchestrator reports `SNAPSHOT_RECORD=all` passes on 17e, 17, Air, 18 Pro and 18 Pro Max, and `make check` passed. SE/Duo sun containment and Duo Dutch action visibility failed; `make duo` failed. The tests now follow the horizon decision and require full action visibility for the second audit. Host checks pass: 80 SwiftPM tests, generator freshness/tests (7 TokenGen, 6 font/cache, 3 AssetGen), 9 launch-resource checks, 30 runner fixtures, strict formatting and direct iOS 17 app/hosted/package/UI compilation. The revised full matrix, board-frame/visual approval and existing device-only checks remain open.
  Files: `Docs/tooling.md`, `Tests/LaunchTests/__Snapshots__/README.md`, `AppTests/__Snapshots__/README.md`.

### User decision: board composition on every height (2026-11-06)

- [x] Centre the entire splash composition vertically using one pure LaunchLayout shared by FlightPath, LaunchTimeline and LaunchScene. Keep window-centred frame 0 and the moon's Welcome flight/target, preserve width-scaled path controls, and stretch the band to the window bottom. Replace short-screen known issues with the board's own minimum glyph/wordmark/status clearances from the sun and apex. Update S1, the geometry spec, Phase 3c note, OQ 11 and the resolved risk. Assert original 844 geometry exactly and compare its frames even during recording.
  Files: `Sources/Launch/LaunchLayout.swift`, `Sources/Launch/FlightPath.swift`, `Sources/Launch/LaunchTimeline.swift`, `Sources/Launch/LaunchScene+Layers.swift`, launch package/hosted geometry tests.
  Test: host geometry/timeline checks and D1c simulator tests written; replacement non-844 launch recordings and frozen landing validation remain open.
  Fix round 4: preserve the user's 2026-11-06 horizon composition on SE/Duo. Only the sun's bottom may cross the window; require horizontal safe containment, an inside top edge and at least one third visible height. Moon glyph, wordmark and status retain full containment. Host tests cover all D1c sizes/sample times and reject top/side overflow, less than one third visible, fully hidden and empty suns. The other short-screen assertions concern clearances, path bounds and landing, and retain their existing rules. Revised simulator execution remains open.

- [ ] Record and accept composition-centred launch references on all non-844 D1c devices. Verify the unchanged 844 frames, frozen moon landing, make check and make duo; visual approval remains open.

### User decision: plain sky without a dot pattern (2026-11-06)

- [x] Delete the splash stars layer/LayerID/tracks and Welcome pattern-dots, leaving only CfSky. Remove unused PatternDots, generated pattern/Welcome opacity tokens and generator parsing, the tile test, and all four dot-bearing Phase 1 composite primitive baselines and their fixture. Update existing layer/timeline expectations, S2/spec/background/constants and DesignSystem notes. Add no test for the absence of dots, per the user. Keep unchanged 844 frame comparisons except the two affected Welcome-exit samples.
  Files: launch/welcome/design-system sources, TokenGen, existing tests, `AGENTS.md`, `CLAUDE.md`.
  Test: existing suites updated; combined launch/Welcome replacement recording and visual approval remain open.

- [ ] Re-record affected launch and Welcome baselines with the plain sky on every D1c device; compare all references, run make check and make duo, then obtain visual approval. The orchestrator will use `SNAPSHOT_RECORD=all`.

### Phase 4 review fixes (after Phase 5)

- [x] Keep `-cf.mode ready` and validated `-cf.mainThreadStall` diagnostics in Release for the D3 procedure. Keep slow/Welcome modes, freeze, readyAt and all readiness overrides Debug-only; Release readiness remains signed out without Keychain access or route-name placeholders. Extend the isolated Release tests and document why the device proof can observe the 500 ms stall.
  Files: `App/LaunchArguments.swift`, `AppTests/ReleaseReadinessTests.swift`, `Docs/perf/2026-11-06-d3-spike.md`.
  Test: iOS 17 Debug/Release type-check and SIL compilation; revised Release execution awaits the simulator runner. The D3 trace remains (needs a device; open).

- [x] Prove `stop()` cancels work before any clock advance: bounded registration waits for two signed-in timers or three signed-out timers, drains to zero on stop and observes no state/callback change after eight seconds. Separately suspend session resolution and require its task to observe cancellation, with no later callback/forced readiness.
  Files: `Tests/AppCoreTests/LaunchCoordinatorTests.swift`.
  Test: host SwiftPM passes all 42 AppCore tests (77 package tests total, plus two portable capture guards), including both timer cases and unresolved-session cancellation.

- [x] Record the orchestrator's verified 2026-11-06 Phase 4 full D1c Debug plus isolated Release pass, `make check` and `make duo` in the Phase 4 notes and tooling guide. Retain OQ confirmations and device-only checks. These results cover the reviewed Phase 4 tree; this round's changed tests still need execution.
  Files: `plan.md`, `Docs/tooling.md`.

### Phase 3c review fixes (after Phase 5)

- [x] Flag settled short-screen sun/moon/wordmark/status collisions with geometry tests and height-scoped known issues; assert the status text-frame/replicator union against the path apex, including the 874 pt S1 crossing. Record exact affected baselines, OQ 11 and the materialised risk. Keep Phase 3c visual acceptance open for a user/design decision.
  Files: `Tests/LaunchTests/LaunchSnapshotTests.swift`, `plan.md`.

- [x] Replace stale Phase 3c/3b review-fix validation notes with the orchestrator's verified 2026-11-06 results for all seven D1c devices, both appearance UI tests, make check and make duo. Retain PNG/board-frame approval, short-screen collisions/S1 board review and physical-device D3 proof as open.
  Files: `plan.md`, `Docs/tooling.md`.

### Phase 5 review fixes (after Phase 5)

- [x] Render compressed Welcome typography at its exact scaled line pitch with CSS half-leading. Use natural-height native labels per line so ascenders/descenders can overflow the line boxes; preserve kerning, generated colours, the single accessibility label/header/identifier, the root xxLarge cap and measured moon hand-over. Keep wordmark/eyebrow/copy rendering unchanged. Add the computed three-line board height, scaled English/Dutch pitch, Unicode wrapping, unclipped Agj/Dutch glyphs and unchanged positive-leading pixels; require both Dutch AX5 actions fully visible after bounded scrolling. (OQ 10 default assumed, confirm). Retain RN padding/scrolling on all four safe insets. Host SwiftPM passes 82 tests; strict formatting, generator freshness/tests and resource/runner fixtures pass. Direct Swift 6/MainActor iOS 17 compilation/type-checking passes; Review round 2: the orchestrator recorded all 196 Welcome references across seven devices; comparison/UI stopped after SE, 17e and 17, with the 17e glyph-capture and SE 2700 ms failures below. Production permits glyph overflow; replace the resized-label comparison with exact RGBA/ink bounds against independent natural-height labels on a canvas padded by font ascent/descent, at 2×/3×, plus a clipping mutation. Exact scaled pitch assertions remain. Frozen capture now explicitly lays out/displays native descendants and flushes before drawing; require three matching pixel/frame passes within a bounded loop and two fresh hosts per headline sample (2450/2700/3200/3300) before recording/comparing. Keep the repeated clock/render regression and exact pixel tolerance. These are test/capture changes only: production rendering is unchanged from the recorded tree and the recorded baselines stay valid; no re-record is needed. Revised targeted SE/17e and D1c comparison, visual approval and glyph/audit execution remain open; no new device result is claimed.
  Files: `Sources/DesignSystem/{WelcomeText,ExactLineText,ExactLineTextLayout,Buttons}.swift`, `Sources/Welcome/{WelcomeView,WelcomeBrand}.swift`, `Tests/DesignSystemTests/ExactLineTextLayoutTests.swift`, `AppTests/WelcomeSnapshotTests.swift`, `AppUITests/WelcomeTests.swift`, `Docs/tooling.md`.

- [x] Split the reconnect and Reduce Motion regressions. First connect signed out with motion, require a mounted root and non-nil intro at the coordinator's exit start + 700 ms, then require Welcome to claim it once. Disconnect/reconnect without first-connection privileges, require a new mounted window, no overlay/intro, and pixels matching a final Welcome reference immediately and after 500 ms. Separately require a mounted Reduce Motion Welcome with no intro. Use bounded waits that fail if mounting/claiming never happens and restore the prior key window. Host checks pass; the UIKit regressions are written for the full Phase 5 D1c matrix, with execution still open.
  Files: `AppTests/WelcomeHandOverTests.swift`, `Docs/tooling.md`.

### Tooling: test speed (user request, 2026-11-06)

This work runs on `feat/phase-9-session-store` without starting Phase 9 or closing existing design/device gates.

- [x] Run up to four destinations in a bounded pool with configurable SIM_CONCURRENCY, dynamic type/runtime resolution (including Duo), fresh-app uninstall without reboot, separate device/pass logs and xcresults, per-suite PASS/FAIL and failing-test identifiers. Recording is serialized within each device and parallel only across distinct model namespaces. Host runner fixtures pass; simulator execution remains open.
  Files: `Scripts/launch-simulators.py`, `Tests/test_launch_simulators.py`, command documentation.
- [x] Build once per needed configuration with build-for-testing into build/DerivedData, then use test-without-building. Remove matrix clean and duplicate trailing make check/make duo runs; make check runs its combined test/snapshot selection once. Preserve the isolated Release scheme/testability and separate Perf path. Host fixtures pass; build counts/timings await the orchestrator.
  Files: `Scripts/launch-simulators.py`, `Makefile`, command documentation.
- [x] Classify every target/suite in one runner table with a discovery guard; split mixed UI policy/routing tests from layout/audits and hosted argument/pixel/cap logic from running-window checks. Give top-level Swift Testing tests named suites for explicit selectors. Run logic and Release readiness on 17e, matrix checks on every destination; explicit targeted selectors override scheduling. Pure fixed-fixture timeline/geometry tests remain logic; running-scale image tests remain matrix.
  Files: test suites, `Scripts/launch-simulators.py`, `Tests/test_launch_simulators.py`.
- [x] Select snapshot coverage from one per-model profile shared by the runner's host tests and Swift capture suites. Keep full coverage on SE/17e/Duo/Pro Max; compact devices keep large/xxLarge layout checks, intro 2700/3300 and launch ready-0/ready-1400/slow-2600/welcome-2400/reduceMotion-0. Both appearances/languages remain on Welcome. Remove 72 obsolete PNGs; retained PNGs are byte-identical to HEAD. Launch's existing PNGs cover large/English only; preserve those combinations under the no-re-record instruction and retain type/localization geometry checks. Adding Dutch/xxLarge launch PNGs needs a separately authorized recording, so that requested extension remains open below.
  Files: `Tests/SnapshotSupport/**`, snapshot suites/references, `Package.swift`, `project.yml`, host coverage tests.
- [x] Add make targeted DEVICES="se duo" ONLY="target/suite …", with optional REUSE_BUILD=1, using the same configuration grouping, device pool, fresh-app preparation and results. Resolve se/17e/17/air/18pro/18promax/duo without stored UDIDs; validate selectors/aliases before builds.
  Files: `Makefile`, `Scripts/launch-simulators.py`, `Tests/test_launch_simulators.py`, command documentation.
- [x] Normalize both Welcome comparison inputs through immutable PNG data and one explicit ImageIO sRGB RGBA8 decode path, with exact equality and no re-record. Add metadata/compression/one-channel mutation host regressions and --intro-order-check: fresh process versus a second process after all other Welcome suite tests, both through verifyWelcomeSnapshot. Save both captures and log memory-versus-PNG channel differences. Existing verification already ignored PNG byte identity; different compressed bytes alone cannot explain the SE failure.
  Files: `Tests/SnapshotSupport/SnapshotReference.swift`, `Tests/LaunchTests/SnapshotReferenceTests.swift`, `AppTests/WelcomeSnapshot{Tests,Reference}.swift`, runner and fixtures.
- [ ] Run --intro-order-check on SE and retained frozenIntro alone/full-suite comparisons; determine whether the remaining difference is capture state or in-memory/PNG representation from the logged channels and saved fresh/warm PNGs. The supplied two recordings are not available here; UIKit cannot run in this sandbox. Root cause and simulator confirmation remain open, not claimed fixed.
- [ ] Confirm the full matrix ≤10 min, make check ≤5 min and targeted 1–2 devices ≤3 min after build; exact measurement commands are in Docs/tooling.md. No simulator timing is claimed.
- [ ] Add Dutch/xxLarge launch image references only after resolving the conflict with this task's no-re-record instruction. Existing geometry/localization checks and English/large references remain active; no new baseline is invented.

### Phase 6: Audit (`feat/phase-6-audit`)

Reduce Motion, dark mode, VoiceOver and strings are built in the phases above; this phase only audits.
- [ ] Full UI suite under `-AppleLanguages (nl)`, `-cf.reduceMotion`, and `xcrun simctl ui booted appearance dark`.
  Files: `AppUITests/AuditTests.swift`.
  Test: all pass; Dutch strings not truncated at default size.

### Phase 7: Performance and comparison with RN (`feat/phase-7-performance`)

Blocked by OQ 14.

- [ ] `PerfUITests`, target bundle from `CF_TARGET_BUNDLE_ID`, 10 iterations, `Perf` scheme, signed out: `XCTApplicationLaunchMetric()` (first frame, sanity), `XCTOSSignpostMetric` for the native intervals, `XCTMemoryMetric`, `XCTCPUMetric` (process), `XCTClockMetric` until "Plan my trip" hittable (coarse "below RN" only).
  Files: `PerfUITests/LaunchPerfTests.swift`, `Makefile`.
  Test: runs against both bundles.
- [ ] `Scripts/hitches.sh`: `xcrun xctrace record --template 'Animation Hitches' --device <udid> --time-limit 5s --launch -- <app>`, 5 runs per app; export; hitch-time ratio, longest hitch, frame intervals over 0–3.2 s.
  Files: `Scripts/hitches.sh`.
  Test: produces `Docs/perf/<date>-<app>.md`.
- [ ] Cross-app timing by screen recording (≥ 60 fps device recording; resolution ±1 recorded frame): frames from first app frame to first animated change and to Welcome fully in, both apps.
  Files: `Scripts/frames.py`, `Docs/perf/README.md`.
  Test: script reports both times per run.
- [ ] RN baseline method (RN repo stays untouched): `rsync` the RN repo including its existing `ios/` and `node_modules` to a scratch folder; record `git rev-parse HEAD` and `git status --short`; build there with `xcodebuild -workspace ios/ChronoFlow.xcworkspace -configuration Release` (no `prebuild`); same device, charged, not Low Power, rebooted and idle 2 min; fresh signed-out install per app; record median and p90.
  Files: `Docs/perf/README.md`, `Docs/perf/baseline-rn.md`.
  Test: baseline exists before native targets are judged.

### Phase 8: Verification (`feat/phase-8-verification`)

- [ ] `Docs/plan-gate.md` in RN format (per board: Canvas title / Screen / Checks; **Fixed**, **Open**, **Recorded decision** S1–S6, **Needs a device**), with the board↔native mapping (board 1900 ↔ native 1700; slow 4900 with readyAt 4600; Welcome content from `Main` keyframes; dots excluded).
  Files: `Docs/plan-gate.md`.
  Test: review.
- [ ] Device run on the reference ProMotion iPhone: screen-recorded launch, last launch-screen frame vs first app frame (light/dark, after delete + reinstall and after an upgrade install); lift-away; slow then 8 s; moon landing; intro; Reduce Motion; VoiceOver; Dutch wrapping; 120 Hz via Animation Hitches frame intervals.
  Files: `Docs/plan-gate.md`.
  Test: each item ticked or recorded Open.
- [ ] Comparison report against the budget and an `**Outcome of Phase 8.**` paragraph here.
  Files: `Docs/perf/<date>-comparison.md`, `plan.md`.
  Test: review.

### Execution order for the auth extension

Phases 6–8 above remain open in their original positions and run later for splash/Welcome. By the user's 2026-11-06 instruction the next work starts on checked-out `feat/phase-9-session-store`, stacked on the current reviewed tree, without marking 6–8 complete. Each sub-phase below is one Codex implementation round and its own branch (the first uses the already checked-out branch); finish/tick its tasks in atomic commits before stacking the next branch. No implementation in this planning commit. An unresolved blocking OQ stops its **named sub-phase**; defaults are annotation proposals, not silently settled answers. The API/store work can proceed while UI copy/design OQs are resolved.

**Verification gates referenced by every new task:**

- **Matrix S (store/service), Phase 9a override (user, 2026-11-06):** run LocalStore/AppCore logic, migrations, records, observation and UUIDv7 in SwiftPM host tests on the Mac. Only Keychain and app-lifecycle checks require hosted AppTests, on **one iPhone 17e** via `make check` or a targeted run. The seven-simulator matrix runs only when the user asks for it. Existing launch/Welcome/Release readiness checks stay in `make check`; en/nl and both appearances remain covered there. No new UI or service snapshots. Use temporary stores, injected clocks and deny-by-default network stubs. Physical protection/locked-device behavior needs a signed device (OQ 4); simulator attribute checks do not prove hardware data protection.
- **Matrix A (auth):** on **all seven D1c devices**, hosted snapshots + geometry + UI keyboard/routing/accessibility checks, **en/nl × light/dark × default/xxLarge**, plus AX5 = xxLarge equivalence. Cover each implemented board state, normal and asymmetric safe insets, Duo side rail, keyboard shown/hidden and Reduce Motion. Measure field/submit visibility, scroll to audit every control and reject clipping/empty screenshots. Use hosted `AppTests` (dependent only on app), board reference exports, opt-in recording and explicit own display scale/traits; visual acceptance required before marking snapshots complete. No auth contrast allow-list is presumed.

Every sub-phase runs `make generate` when the manifest/project changes and `make check` before each commit. The seven-simulator matrix and `make duo` run only when the user asks for them (2026-11-06 override); Phase 9a uses host SwiftPM tests plus hosted checks on one 17e. Extend committed `Scripts/launch-simulators.py` modes and host runner tests rather than creating delivery-only `build/commits/simulators.sh`. The orchestrator runs simulator/device checks where Codex's sandbox cannot; record exact supplied results and leave unrun checks open. Future task paths use the same package-relative convention as the spec.

### Phase 9: Session, local store, API client and sync (`feat/phase-9-session-store`)

No UI. Four bounded rounds: 9a persistence/session, 9b remote contracts, 9c pull/outbox, 9d lifecycle/wipe/readiness. D18–D26 fix storage and data-source architecture. OQ 9 is RN migration only. OQ 26's backup default permits development work; shipping requires its answer. No auth route is mounted here.

#### Phase 9a: Store, session and device identity (`feat/phase-9a-store`)

- [x] Add `LocalStore` library/test target, exact GRDB 7.8.0 dependency and committed resolution; implement `AccountDatabase.open(accountID:)`, migration `v1` and storage attributes (D18/D19), all seven tables exactly as specified. Use background pool construction; validate path IDs; no destructive fallback or 15-migration replay.
  Files: `Packages/ChronoFlowKit/Package.swift`, `Packages/ChronoFlowKit/Package.resolved`, `Sources/LocalStore/{AccountDatabase,SchemaV1}.swift`, `project.yml`.
  Test: `Tests/LocalStoreTests/{SchemaV1,AccountDatabase}Tests.swift`: compare PRAGMA columns/defaults/PK/FK to the verified final RN schema fixture, fresh/reopen migration idempotence, cascade, WAL/foreign keys on readers/writer, rollback, account isolation, invalid/path IDs, failing migration preserves file, directory/sidecar protection and backup attributes. Verify **Matrix S**, including blocked-open launch ordering on 17e (user testing override; Duo only on request); physical lock proof remains a device check.
- [x] Add records/repositories/value observation for account, trips, plan_versions, check_marks, settings, drafts and outbox. Add `AccountModel` as an observation adapter, with no view; expose loaded/unknown/empty separately and keep all JSON round-trippable. Cancel subscriptions before account detach/close.
  Files: `Sources/LocalStore/Records/*.swift`, `Sources/LocalStore/{Account,Trip,Settings,Draft,Outbox}Repository.swift`, `Sources/LocalStore/AccountModel.swift`, `App/Session/AccountModel.swift`.
  Test: `Tests/LocalStoreTests/{Records,RepositoryObservation}Tests.swift` (including the pure AccountModel adapter on the host): JSON/null/composite-key round trips, atomic values after commit only, initial fetch off-main, no post-cancel delivery/cross-account values, pending observer permits pool close. Verify **Matrix S**; no observation-driven rendering added.
- [x] Extend the existing session reader/writer through `SessionController.restore()/accept(_:)` and `DeviceIdentityStore.identity()`. Retain the Phase 4 Keychain service/key/shape; add typed restore failure handling and mock namespace isolation. DB account upsert precedes Keychain write and signed-in publication; session marker is never faked. Generate/persist UUIDv7 once off-main, device name ≤255 characters. Full wipe/triggers await 9d.
  Files: `Sources/AppCore/{SessionStore,SessionController,DeviceIdentityStore}.swift`, `App/Readiness/KeychainSessionStore.swift`, `App/Session/{NativeSessionController,DevicePreferences}.swift`.
  Test: `Tests/AppCoreTests/{SessionController,DeviceIdentity}Tests.swift`, `AppTests/KeychainSessionStoreTests.swift`: legacy native JSON round trip, malformed deletion, inaccessible Keychain retry, DB/Keychain failure ordering, no published session on failed accept, concurrent accepts reject stale completion, per-source/account isolation, UUIDv7 bits/time/randomness and concurrent creation, restart persistence and wipe-survival contract. Verify **Matrix S** and first-flush-before-any-I/O assertions; no second session reader.

Implementation complete (2026-11-06); 115 host SwiftPM tests pass (30 new), plus 21 runner fixtures, nine resource checks, strict formatting and generator checks (7 TokenGen, 6 font/cache, 3 AssetGen). All package tests compile for the iOS 17 simulator target; Debug/Release app and hosted tests compile through SIL. Keychain, iOS file-protection attributes and first-flush/suspended-open hosted execution remain **Open: orchestrator on one 17e**; no simulator or physical-device result is claimed. Commands and defaults are in `Docs/tooling.md`, Phase 9a. The backup exclusion default (OQ 26) permits development; hardware lock proof and shipping approval stay open. Session lifecycle/sync/wipe composition stays in 9d.

- [x] Review fix: make a successful credential write the accept commit point; reject superseded/canceled accepts only before that point. Host regressions suspend the write and sync request, covering a newer invalid accept and caller cancellation without losing the committed publication.
- [x] Review fix: retain the published session during same-account refresh; publish signed-out before switching databases. Host regressions cover open, upsert and Keychain failures after sign-in, including the suspended refresh write, and compare presence, credentials, stored session and observer epoch.
- [x] Review fix: clear AccountModel on normal observation completion, hide a closing database from new lookups, and validate an attachment token captured before native actor hops. Host regressions close an attached database and suspend close after detach, rejecting delayed attachments and preserving a newer account's model.

#### Phase 9b: Data-source contract, mock and API (`feat/phase-9b-data-source`)

Stack on 9a. No UI; build passkey contracts and data-source methods for Phase 10 native sign-in (OQ 20 settled). Missing translations block rendering later, not contract decoding tests. Testing override (user, 2026-11-06): all portable contracts/client/mock/parity tests run in SwiftPM on the Mac; only build-setting/factory checks run in hosted AppTests on one iPhone 17e. The seven-device matrix runs only on user request.

- [x] Define Sendable auth/account/trip DTOs, passkey DTOs (`ApiPasskeyChallenge`, `ApiPasskeyRequestOptions`, `ApiPasskeyLoginInput`, `ApiPasskeyAssertion`, `ApiPasskeyAssertionResponse`), `DataSource.passkeyOptions()` / `passkeyLogin(_:)`, `DataFailure` and typed outbox payload/receipt contracts from W request/response DTOs and RN behavior. Add `DataAccess`/test targets, build-setting factory and validated base URL. Factory never selects API in tests; isolated API-client tests inject URLSession. Keep unsupported operations typed and explicit (OQ 31).
  Files: `Sources/AppCore/{DataSource,DataFailure,OutboxChange}.swift`, `Sources/AppCore/Contracts/*.swift`, `Sources/DataAccess/DataSourceFactory.swift`, `App/Session/AppServices.swift`, `Config/Base.xcconfig`, `App/Info.plist`, `project.yml`, `Packages/ChronoFlowKit/Package.swift`.
  Test: `Tests/DataAccessTests/{Contracts,DataSourceSelection}Tests.swift`, `AppTests/DataSourceBuildSettingTests.swift`: both result variants, optional/null fields, invalid payloads, mock defaults, explicit API selection, invalid setting/URL rejection, Release HTTPS-only, isolated state roots/services. Verify **host SwiftPM plus hosted factory tests on one 17e** with mock-only simulator launch and a test URLProtocol rejecting every unmatched request.
- [x] Implement `APIClient.request(_:)` and `APIDataSource` for all auth endpoints plus identity/account/trips and supported outbox writes. Include forgot/reset/resend/verify now despite RN TODOs and public passkey options/login with exact encoding/DTO/error contracts; enforce timeouts, headers, public-route bearer exclusion, no cookies/cache/redirects, cancellation and typed error-envelope mapping. Accept signed verify fields only.
  Files: `Sources/DataAccess/API/{APIClient,APIDataSource,APIEndpoint,APIRedirectDelegate}.swift`, `Tests/DataAccessTests/Fixtures/{auth,account,trips,errors}/**`, `Tests/DataAccessTests/Fixtures/README.md`.
  Test: `Tests/DataAccessTests/{APIClient,APIDataSource}Tests.swift` with URLProtocol stubs: recorded success/204/two-factor/unverified, every error code, field args, malformed/HTML body, body/header/date/default retry-after, timeout cancellation (15/90/3 s via injected scheduler), same/cross-origin redirects, no cookie/bearer leakage, signed verification payload, correct verbs/paths and sanitized provenance. Verify **host SwiftPM plus hosted factory tests on one 17e**; no live capture or network call.
- [x] Port mock auth/account/trips semantics with persisted fake-server state, `setOffline`, `failNext`, 300–800 ms injected delay, 5/min limiter, scenario fixtures and typed mock inbox. Add deterministic contract parity tests shared with API fixtures. Model reset revocation and valid/expired/tampered signed verify inputs as backend does; model deterministic passkey options/assertion login, single-use/expired challenges, credential failure, throttle and verified/unverified sessions behind an injected test assertion provider (never invoke AuthenticationServices or imply a real credential in mock); keep RN fixture credentials as explicit test/scenario values only.
  Files: `Sources/DataAccess/Mock/{MockDataSource,MockServerState,MockInbox,MockRateLimiter}.swift`, `Tests/DataAccessTests/Fixtures/MockScenarios.swift`.
  Test: `Tests/DataAccessTests/{MockAuth,MockAccountTrips,MockPersistence,DataSourceParity}Tests.swift`: offline/fail-once/latency bounds, five allowed attempts then throttle/reset window, two-factor/recovery reuse, register duplicate/unverified, non-enumerating forgot, reset once/expired, verification resend/deadlines, account/trip isolation and persistence across restart. Verify **host SwiftPM plus hosted factory tests on one 17e** with no real sleeps/network; no inbox UI or credential autofill.

Implementation complete (2026-11-06): all three tasks are ticked. Host verification and exact orchestrator commands are recorded in `Docs/tooling.md`, Phase 9b. Hosted execution remains open; no simulator or live API was run. The backend passkey handoff overrides the stale RN passkey TODO and token/email verification shape: passkey sign-in returns a session even with 2FA or an unverified email, verification uses authenticated signed fields, and password reset revokes sessions without signing in. Native AuthenticationServices/entitlements remain Phase 10/device work; no UI or Phase 9c/9d lifecycle wiring is added.

- [x] Review fix: exercise URLSession redirect callbacks for 301/302/307/308 and same/foreign hosts, with a following control session; verify effective cookie/cache/header configuration and real host-only loopback cookie handling. Delegate and security-configuration mutations fail the host regressions.
- [x] Review fix: replace Phase 9b's stale no-commits tooling note with its three implementation commits; a host regression checks the record against git history.
- [x] Review fix: use the backend's exact wrong-credentials email key in mock sign-in. Failure-path parity compares mock and API against the backend 422 envelope; the regression fails before the fix and passes after it.

#### Phase 9c: Full pull and durable outbox (`feat/phase-9c-sync`)

Stack on 9b. No UI; scope is the documented engine/repositories, not Settings/Today or security forms. OQ 31 defers producers/handlers for absent endpoints; schema parity remains required.

- [ ] Add `OutboxRepository.enqueue(_:)` transaction APIs for check-offs, supported settings/profile edits and walkthrough, plus typed storage for other RN kinds. Preserve pending local values; flush supported rows FIFO with dependency blocking, response-application transactions, final refusal → `syncFailure`, transient attempt/backoff metadata. Never enqueue auth/secrets or claim unsupported writes succeeded.
  Files: `Sources/LocalStore/{OutboxRepository,LocalMutations}.swift`, `Sources/Sync/{OutboxFlusher,OutboxFailurePolicy}.swift`, package target `Sync` (AppCore/LocalStore dependencies).
  Test: `Tests/SyncTests/{OutboxFlusher,LocalMutations}Tests.swift`: durable restart/rollback, FIFO tie-break, independent dependency progress, repeat-safe replay after response/crash, final 4xx vs 401/403/429/5xx, unsupported rows parked without spin, no sensitive payloads, mutation and enqueue atomic. Verify **Matrix S**; no sync-failure toast is invented (OQ 30).
- [ ] Implement `FullPull.run(epoch:)`: identity then verified account/trips, protected pending sections/profile/walkthrough/check marks, empty-list tombstones and deleted_locally guards, `synced_at` transaction semantics, retained plan details by detailVersion, plan lease/eviction and stale-check re-keying as in the spec.
  Files: `Sources/Sync/{FullPull,PlanRetention,CheckOffReconciler}.swift`, `Sources/LocalStore/{Account,Trip,Settings}Repository.swift`.
  Test: `Tests/SyncTests/{FullPull,PendingProtection,PlanRetention,CheckOffReconciler}Tests.swift`: full-pull order, unverified early stop, atomic marker/readiness, missing/empty trips, no resurrection, pending-value protection, retained/changed/unchanged/404 details, no eviction of pending/held plans, stable-step re-key and newer-mark preservation. Verify **Matrix S**, all API interactions through mock/URLProtocol.
- [ ] Assemble `SyncEngine.requestSync()/refreshNow()/cancelAndWait()` with injectable epoch/clock/source; one flight, one coalesced rerun and sanitized result events. Check cancellation/epoch inside response writes; preserve offline cached state. Lifecycle wiring and forced sign-out handler follow in 9d.
  Files: `Sources/Sync/{SyncEngine,SyncStatus}.swift`, `Tests/SyncTests/Support/*.swift`.
  Test: `Tests/SyncTests/SyncEngineTests.swift`: concurrent requests/refreshes, actor reentrancy, queued writes during pulls, cancellations before/after every await, wrong/stale epoch results rejected, empty initial DB first pull then offline restart, per-account isolation, transient failures retain outbox. Verify **Matrix S** with a blocked/mock source and no timer sleeps.

#### Phase 9d: Sync lifecycle, sign-out wipe and launch readiness (`feat/phase-9d-session-lifecycle`)

Stack on 9c. No UI. OQ 29 leaves voluntary pending-change confirmation as a return value only; no new dialog. D25 forced wipe is required regardless of that UI decision.

- [ ] Wire activation/reconnect/sign-in/DB-open/outbox triggers, 1 s debounce, capped exponential backoff and retry-after, cancellation on detach, path-monitor shutdown and epoch-scoped unauthorized handling. Expose future pull-to-refresh API; do not add its screen.
  Files: `App/Session/{SyncLifecycle,NetworkPathMonitor}.swift`, `App/SceneDelegate.swift`, `Sources/Sync/SyncEngine.swift`.
  Test: `Tests/SyncTests/SyncTriggerTests.swift`, `AppTests/SyncLifecycleTests.swift`: fake scene/path bursts, single flight/rerun, backoff 1/2/4…300 s/reset, 429 deadline, offline doesn't spin, stop drains observers/timers, 403 gates verify, current 401 calls wipe once and stale 401 cannot affect replacement session. Verify **Matrix S**, including reconnect and scene reconnect without splash replay.
- [ ] Implement serialized voluntary/forced `signOut` and account wipe, including pending-count result, flush attempt, explicit discard, 3 s logout deadline, cancellation/await/detach/close/delete order, wipe marker and cleanup retry. Clear Keychain/account secrets/ephemeral responses and route `.signIn`; keep device preferences. Never wait on sign-out recursively from the engine task it is canceling.
  Files: `App/Session/{NativeSessionController,AccountWiper}.swift`, `Sources/AppCore/SignOutResult.swift`, `App/Readiness/KeychainSessionStore.swift`.
  Test: `Tests/AppCoreTests/SignOutTests.swift`, `AppTests/AccountWipeTests.swift`: offline pending → needsConfirmation preserves rows; discard removes DB/WAL/SHM/session; 401 skips flush/logout; timeout still wipes; concurrent/partial-failure/restart cleanup; observer/reader lifetime; late response cannot recreate files; device ID/language/appearance survive; next account sees no old rows. Verify **Matrix S**. Pending confirmation UI stays deferred (OQ 29).
- [ ] Replace ordinary `StubReadiness` composition with `StoredDataReadiness` using the Phase 4 session reader and `synced_at` observation; keep Debug injected diagnostics and an explicit signed-out `Perf` build setting. Ordinary Release now restores the selected source's native session. Construct services only after overlay first commit; update historical Release tests to assert this new distinction without weakening argument isolation.
  Files: `App/Readiness/StoredDataReadiness.swift`, `App/SceneDelegate.swift`, `App/LaunchArguments.swift`, `App/Session/AppServices.swift`, `AppTests/ReleaseReadinessTests.swift`, `Config/Base.xcconfig`, `project.yml`, `Scripts/launch-simulators.py`, `Tests/test_launch_simulators.py`, `Docs/tooling.md`.
  Test: `Tests/AppCoreTests/StoredDataReadinessTests.swift`, `AppTests/{SessionReadiness,LaunchConnection,ReleaseReadiness}Tests.swift`: restored cached data offline ready, fresh false→true, unverified ready without marker, 2/8 s rules, late/unknown session and cancellation, unavailable protected store preserves data, no I/O before flush/no main-thread open/migrate, frozen launch unaffected, signed-out Perf touches no DB/network. Verify **Matrix S**, Debug and isolated Release, `make check`/`make duo`; record device-only protection/performance limits honestly.

### Phase 10: Sign in and two-factor (`feat/phase-10-sign-in`)

Stack on 9d; two rounds. OQ 20 is settled: retain the designed passkey button/divider and implement native sign-in. Resolve OQ 23 (offline variant), 24 (unfinished destination), 28 (Phase 10 Dutch copy) and 30 (hidden-field notices) **before 10a**. No default permits an invented state. A `.verify` result may use its existing route seam until 11d. Verified success goes to `.today` seam; Today implementation is excluded.

#### Phase 10a: Native Auth shell, controls and Sign in (`feat/phase-10-sign-in`)

- [ ] Export AuthSignIn none/wrong/locked/server, AuthStates banner references and Field/Button/Notice states, both appearances. Extend generated tokens/metrics/typography/shadow output; add `Auth` UI target with `AuthScreen`, `AuthBrand`, `AuthField`, `AuthButton`, `AuthBanner`, `AuthNotice` using native controls. Implement scroll/focus/error/submit handling and `AuthFormModel` classification/lock. Catalog includes every introduced English/Dutch string together; no sample credentials.
  Files: `_design/frames/auth/**`, `_design/frames/README.md`, `Tools/TokenGen/**`, `Tools/AssetGen/**`, `Sources/DesignSystem/Resources/Auth.xcassets/**`, `Sources/DesignSystem/{AuthTokens.generated,AuthTypography,AuthControls}.swift`, `Sources/Auth/{AuthScreen,AuthBrand,AuthFormModel}.swift`, `Sources/Auth/Resources/Localizable.xcstrings`, `Packages/ChronoFlowKit/Package.swift`, `project.yml`.
  Test: `Tests/AuthTests/{AuthFormModel,AuthFailureMapping,Catalog}Tests.swift`, TokenGen/AssetGen freshness, glyph and OKLab mix tests, `AppTests/{AuthControl,AuthLayout,AuthSnapshot}Tests.swift`: busy double-submit lock/edit clearing/field binding, contrast tokens, keyboard/focus, accessible labels and announcement deduplication. Verify **Matrix A** against 375 × 812 zero-inset board plus actual safe-area fixtures; no cap bypass, dots or glass imitation.
- [ ] Implement `SignInView`/model and Auth navigation stack; mount it for existing `.signIn` from Welcome. Password attempt always clears password, error variants match AuthStates, links enter guest/Forgot/Sign up seams. Two-factor result holds challenge and pushes a route seam until 10b; session result calls the one session controller, honors verify/terms/walkthrough/app gates and OQ 24's `.today` destination policy.
  Files: `Sources/Auth/{SignInView,SignInModel,AuthNavigation}.swift`, `App/RootView.swift`, `App/Session/AppServices.swift`.
  Test: `Tests/AuthTests/SignInModelTests.swift`, `AppUITests/SignInTests.swift`: Welcome/back/guest/forgot/signup routing, blank/server field/credential/throttle/server/offline cases (approved OQ 23), banner cleared on edit, return chain, password cleared on success/failure, two-factor gets no early session, verified/unverified routing, no splash replay. Verify **Matrix A**, recording/accepting all sign-in state snapshots and audits in en/nl/both appearances.

- [ ] Implement native passkey sign-in with AuthenticationServices `ASAuthorizationPlatformPublicKeyCredentialProvider`: `passkeyOptions()` → decode challenge and request a required-user-verification assertion for the returned RP ID → `passkeyLogin(_:)` → the one session controller. Serialize assertion credential ID, raw ID, clientDataJSON, authenticatorData, signature and optional userHandle using unpadded base64url (including id/clientDataJSON); never UTF-8-decode binary bytes. Handle canceled authorization without an error banner; map credential/challenge validation and field args to approved existing banner/field patterns, 429 to lock/retry-after and server/offline to the existing approved patterns (OQ 23/30). Fetch fresh options for retry after a consumed/expired challenge. Retain the board button/divider for both sources; mock uses an injected deterministic assertion provider with no system credential prompt/network and tests verified/unverified/2FA-session outcomes. Add `com.apple.developer.associated-domains` = `webcredentials:app.chronoflow.net` on the **device-signed configuration only**, never simulator/ad-hoc builds.
  Files: `Sources/Auth/{PasskeySignIn,SignInModel}.swift`, `Sources/Auth/Resources/Localizable.xcstrings`, device entitlements/configuration in `Config/` and `project.yml`.
  Test: host DTO/base64url/error mapping tests and mock/UI cancellation/retry/success tests; no live passkey requests. **Open: device-only verification** needs the confirmed Apple team/bundle IDs (OQ 4), a team-signed build and deployed AASA over public HTTPS, including Apple CDN delivery. Backend branch is not deployed; simulator/mock acceptance does not close this check.

#### Phase 10b: Two-factor code/recovery and auth acceptance (`feat/phase-10b-two-factor`)

Stack on 10a. OQ 28's Two-factor strings must be resolved. Expired challenges have no separate board: use the approved notice/banner policy or defer that visual state under OQ 30.

- [ ] Implement TwoFactor with code and recovery modes from AuthTwoFactor, shared form controls/model, oneTimeCode number pad (max six digits), mode toggle clears code/errors, every attempt clears code, correct field-error mapping and back cancellation. Session acceptance/routing uses 9d; challenge ID is memory-only and absent challenges return to Sign in.
  Files: `Sources/Auth/{TwoFactorView,TwoFactorModel,AuthNavigation}.swift`, `Sources/Auth/Resources/Localizable.xcstrings`, `_design/frames/auth/**`.
  Test: `Tests/AuthTests/TwoFactorModelTests.swift`, `AppUITests/TwoFactorTests.swift`: wrong/missing/latest code, recovery success/reuse, expired/five-failure challenge, throttled/server/offline, toggle/back/cancel/double submit, no code/token persistence, number-pad submit visibility and keyboard dismiss. Verify **Matrix A**, code/recovery/field-error/attempts/server snapshots and en/nl announcements.
- [ ] Complete auth matrix runner selection, hosted capture/blank guards, end-to-end mock sign-in/two-factor/relaunch/offline/wipe and strict accessibility audit report. Keep seams visible only as allowed by D17/OQ 24; document results and pending device checks without treating phases 6–8 as completed.
  Files: `AppTests/AuthSnapshot*.swift`, `AppTests/__Snapshots__/Auth/**`, `AppUITests/AuthAuditTests.swift`, `Scripts/launch-simulators.py`, `Tests/test_launch_simulators.py`, `Makefile`, `Docs/auth-gate.md`, `Docs/tooling.md`.
  Test: auth runner fixture/failure/record-isolation tests; `AppUITests/AuthSessionTests.swift` covers verified, two-factor and unverified accounts plus offline cached restore. Verify full **Matrix A** with side-by-side board review, AX5 equality, all controls audited after scrolling, `make check` and `make duo`; no auth contrast exemptions inherited from Welcome.

### Phase 11: Recovery and account creation (`feat/phase-11-account`)

Stack on 10b. Four bounded rounds, with independent copy/link gates. The API methods already exist and are unit-tested in 9b; this phase wires the screens. Typed input/mock inbox drives Reset/Verify in tests. Production universal-link handling is deferred server-side, so no claim that a real email opens these native screens; mark that limit in the gate report.

#### Phase 11a: Forgot password (`feat/phase-11-account`)

Resolve OQ 28's Forgot heading/notice translation and shared offline/notice policy before this round. Live endpoint is implemented, but tests never use it.

- [ ] Wire Forgot email form → `requestPasswordReset` (`POST auth/forgot-password`) and the designed sent Notice with interpolated submitted email, Open email app and Back to sign in. Preserve non-enumeration and correct throttle/server/field states. Connect Sign in's Forgot seam; send-new-link from future resetExpired enters the same form with prefilled email.
  Files: `Sources/Auth/{ForgotPasswordView,ForgotPasswordModel,AuthNavigation}.swift`, `Sources/Auth/Resources/Localizable.xcstrings`, `_design/frames/auth/**`.
  Test: `Tests/AuthTests/ForgotPasswordModelTests.swift`, `AppUITests/ForgotPasswordTests.swift`, hosted auth snapshots: existing/unknown email identical success, failure leaves form, sent email captured separately from edits, busy/return-send, no handler for message URL, back routing. Verify **Matrix A**, form/sent/throttled/server/field error and approved offline state in en/nl/both appearances. Real mail delivery/link reception remains outside simulator acceptance.

#### Phase 11b: Reset, expired and done (`feat/phase-11b-reset`)

Resolve OQ 21 (password rules/hint), 22 (all-token revocation copy), 27 (board promises auto-login), 28 (Reset Dutch copy) **before this round**. OQ 25/15 block real link entry, not typed-input/mock-inbox exercise.

- [ ] Add typed Reset input routing seam and Reset/resetExpired/resetDone state machine. Missing/invalid/expired/reused token selects designed expired view; confirmation and password use server field messages; clear both after every attempt. Successful 204 goes to the approved done copy/action and never fabricates a session. Send a new link wires 11a; Continue returns to Sign in under proposed OQ 27 default.
  Files: `Sources/AppCore/ResetPasswordInput.swift`, `Sources/Auth/{ResetPasswordView,ResetPasswordModel,ResetLinkExpiredView,AuthNavigation}.swift`, `Sources/Auth/Resources/Localizable.xcstrings`, `_design/frames/auth/**`.
  Test: `Tests/AuthTests/ResetPasswordModelTests.swift`, `AppUITests/ResetPasswordTests.swift`, hosted auth snapshots: direct typed/mock-mail entry, missing/expired/used token, validation/mismatch/production password rules, server/offline, 204 no Keychain session, passwords cleared, expired→Forgot and done→Sign in. Verify **Matrix A** for form/error/expired/done, keyboard and nl copy. Test real payloads only through URLProtocol; report native email entry as deferred.

#### Phase 11c: Sign up (`feat/phase-11c-sign-up`)

Resolve OQ 21 and 28's Sign up copy/field-message translations before this round; verify gate remains the existing seam until 11d.

- [ ] Build AuthSignUp name/email/password/confirmation, one native shared Show/Hide Toggle, consent web links, Create account and existing-account footer. Wire `signUp`, language/device identity, taken/server/field errors; clear passwords after every attempt and save unverified session through the same controller, then `.verify`. Do not implement guest claim recovery, reminders, policy reader or walkthrough here.
  Files: `Sources/Auth/{SignUpView,SignUpModel,AuthNavigation}.swift`, `Sources/Auth/Resources/Localizable.xcstrings`, `_design/frames/auth/**`.
  Test: `Tests/AuthTests/SignUpModelTests.swift`, `AppUITests/SignUpTests.swift`, hosted auth snapshots: empty/invalid/taken/password-confirm errors, server/offline/throttle under approved policy, one-toggle semantics/AutoFill/focus, language/device payload, no double registration, Keychain failure, unverified gate and web link targets. Verify **Matrix A**, default/taken/server plus field states, keyboard and all consent/toggle/footer controls reachable on SE/Duo at xxLarge.

#### Phase 11d: Verify email waiting/failed and recovery acceptance (`feat/phase-11d-verify`)

Resolve OQ 25's native link parameters/production copy decision and OQ 28's Verify Dutch copy before this round. Default is signed API input plus test/mock entry, not universal-link delivery; a production link integration remains deferred even if the screen is implemented. OQ 29 permits only the explicit Back/different-email discard behavior here.

- [ ] Mount AuthVerify waiting and verifyFailed for `.verify`; authenticated signed verify request when typed input exists, otherwise users/me check. Recheck on activation/email-app return, guard account/email/epoch, persist verified status and request sync, then existing gate route. Resend deadline uses server seconds; 429/reset of deadline cannot be bypassed by backgrounding. Back/Use a different email calls explicit discard/wipe; no mock inbox, toast or email-changed UI.
  Files: `Sources/Auth/{VerifyEmailView,VerifyEmailModel,AuthNavigation}.swift`, `App/RootView.swift`, `App/Session/SyncLifecycle.swift`, `Sources/Auth/Resources/Localizable.xcstrings`, `_design/frames/auth/**`.
  Test: `Tests/AuthTests/VerifyEmailModelTests.swift`, `AppUITests/VerifyEmailTests.swift`, hosted auth snapshots: waiting/failed/resend errors/countdown, signed success/invalid/expired/foreign/tampered inputs, auth bearer required, app-active web verification, stale status after sign-out/email change ignored, unverified 403 loop prevention, Back discards/wipes. Verify **Matrix A**, en/nl/both appearances, return-from-keyboard/email and VoiceOver announcements; no live mail/network.
- [ ] Extend auth matrix/gate documentation to all implemented Phase 11 variants and mock inbox data-driven journeys; document real Forgot/Reset/Register/Resend/Verify wire coverage separately from deferred link delivery. Revisit all blocking OQs; keep unavailable designs/production links and physical-only checks marked open, and preserve Phase 6–8 splash/Welcome work.
  Files: `AppUITests/AccountRecoveryTests.swift`, `AppTests/__Snapshots__/Auth/**`, `Scripts/launch-simulators.py`, `Tests/test_launch_simulators.py`, `Docs/auth-gate.md`, `Docs/tooling.md`, `plan.md`.
  Test: mock forgot→mail event→reset→Sign in, sign-up→mail event→verify→gate, wrong/expired links, offline/reconnect, sign-out/wipe/relaunch and cross-account isolation; runner selects only implemented states and cannot hit network. Verify full **Matrix A**, board acceptance, `make check` and `make duo`; no universal-link or TestFlight acceptance is inferred.

## Performance budget

The design sets the floor: hand-off ends at 1900 ms (ready) and Welcome is fully in at 3200 ms. "Better" = first frame sooner, first motion sooner, every frame kept, designed times never exceeded. Proposals; OQ 14 confirms.

| Metric | Target (native) | How measured |
|---|---|---|
| Launch to first frame | ≤ 400 ms on the reference device and below RN median | `XCTApplicationLaunchMetric()`, 10 runs, Release, both apps |
| Scene connect → overlay committed | ≤ 16 ms | `first-commit` signpost interval |
| First frame → first animated change | 300 ms + ≤ 1 recorded frame (designed), and below RN | Screen recording, both apps |
| Session known, signed out | ≤ 50 ms after scene connect | `session` signpost |
| Hand-off end, ready known before 1500 | 1900 ms ± 1 frame from `t0` | `exit` signpost |
| Welcome interactive (overlay removed) | 2550 ms ± 1 frame; cross-app below RN | `launch` signpost; screen recording for RN |
| Last intro item lands | 3200 ms ± 1 frame | `intro` signpost |
| Hitches 0–3.2 s | ratio < 1 ms/s, none longer than 1 frame, also with a 500 ms main-thread stall | Animation Hitches, both apps |
| Frame rate | ~8.3 ms frame intervals during the splash on ProMotion, outside Low Power Mode | Animation Hitches display/frame tracks |
| Peak memory to Welcome | below RN | `XCTMemoryMetric` |
| CPU to Welcome | process below RN; main-thread profile recorded | `XCTCPUMetric`; Time Profiler |
| Field | tracked after release | MetricKit `MXAppLaunchMetric` / `MXHitchMetric` (later) |

## Risks

- **Launch screen vs frame 0 mismatch / stale cache.** Mitigation: storyboard (D7), hosted parity test (Phase 2), screen-recorded device check incl. upgrade install (Phase 8), caching steps in `CLAUDE.md`.
- **Overlay commit not before root.** Mitigation: D3 ordering + `first-commit` signpost assertion in 3b.
- **D3 fails under load.** Mitigation: device stall test in 3b, before anything builds on it.
- **`strokeEnd` not arc-length proportional.** Mitigation: 3a spike, polyline fallback.
- **Status bar with two windows.** Mitigation: verify in 3b; fall back to the main hosting controller.
- **SwiftUI intro drifting from the CA clock.** Mitigation: one clock, `intro` signpost.
- **Snapshots differ from live.** Mitigation: no masks/filters; `sample` vs `presentation()` test; `-cf.freezeAt` screenshot.
- **Fraunces static cuts** look slightly off at sizes other than 20/32/48. Mitigation: OQ 10.
- **XcodeGen vs Xcode 27 formats.** Mitigation: Phase 0 check, synchronized-folder fallback.
- **Unfair RN comparison** (debug build, device state, signed-in data). Mitigation: Phase 7 protocol; signed-out only.
- **Short 667 pt screens** (also Duo 466 × 678): resolved by the user's 2026-11-06 composition decision. The moon stays window-centred; sun/band/path/plane retain the 844 board's relative offsets at every height. Tests require at least the board's glyph/wordmark/status clearances from the sun disc and path apex. Revised simulator validation and visual acceptance remain open.
- **Bundle ID / Keychain.** Carry-over only possible under the final ID; migration is its own phase.

## Open questions for the user

| # | Question | Default | Blocks |
|---|---|---|---|
| 1 | ~~Commit trailer~~ **Settled 5 Nov: no trailer** (RN rule). | — | — |
| 2 | ~~Tooling installs~~ **Settled 5 Nov:** user approved installs; XcodeGen 2.46.0 and SwiftLint 0.65.1 installed (SwiftLint unused unless adopted), `fonttools` venv and `swift-snapshot-testing` when their phase needs them. | — | — |
| 3 | ~~Minimum iOS~~ **Settled 5 Nov: iOS 17.0** (D1), Liquid Glass on 26+ (D1b). | — | — |
| 4 | **Settled 5 Nov:** `net.chronoflow.app.native` in development, local git only, no remote. Still open: Apple team ID (device runs from 3b) and whether native later takes `net.chronoflow.app`. Passkey AASA currently proposes **unconfirmed** team `2UMFLSCBZ6` and both bundle IDs `net.chronoflow.app.native` / `net.chronoflow.app`; confirm team membership/registrations in the Apple Developer account. | — | Device runs from 3b |
| 5 | **S1 and S2 settled 5 Nov:** moon centred; no stars in the opening. S3–S6 as listed (prose wins). | As listed | — |
| 6 | **Undesigned details:** Reduce Motion dot opacity and fade easing; flying moon (1.87 pt stroke, glow) vs Welcome moon (2.33 pt, no glow) — cross-fade or not; splash/Welcome pattern-dots removed by the user on 2026-11-06. | Dots hold at 1.0; ease-out; no cross-fade; pattern removed | Phase 3a / 5 |
| 7 | **Late or unknown session:** signed out known after 1600 → welcome ending at that moment, or the `ready` lift-away? Session unknown at 8 s → signed out? | Start at resolution; signed out | Phase 4 |
| 8 | **Stub destinations:** (a) Debug-only route-name screens, (b) inert buttons, (c) route seam only, (d) bring `AuthSignIn` / `TodayLoading` in. | (c) + (a), never in Release | Phase 4 |
| 9 | **Session source and migration.** Is the RN app live with real users? If native later ships as `net.chronoflow.app`, should it read the RN Keychain item (`session`; there is no `app:no-auth` key) and migrate SQLite, kv-store, `api.deviceId`? | Native-only session/store now (D18/D21); decide migration at bundle switch | RN import only; does not block Phase 9 |
| 10 | **Scaling settled by the user 2026-11-06:** maximum xxLarge; xxxLarge and accessibility sizes AX1–AX5 clamp to it. Smaller sizes scale normally. Still open: scrolling on 667 pt screens, long Dutch headline and safe-area padding (`max(safeTop+16, 64)` gives ~78 on Dynamic Island phones vs board 64). | Scroll as RN; RN padding rule | Phase 5 |
| 11 | **Vertical composition settled by the user 2026-11-06:** keep the 844 pt board's vertical relationships at every height (`h − k` → `h/2 + (422 − k)`), stretching the band to the window bottom. The moon stays window-centred for D7/S1. This resolves SE/Duo collisions and the 874 pt status/apex crossing. Still open: Duo's other postures and path endpoint bleed vs horizontal safe areas; no redesign is provided. | RN x control points × w/390; vertical rule settled | Phase 3a (vertical unblocked) |
| 12 | **Stale board link:** `Main` links "Plan my trip" to superseded `GuestFlight`; target is the new guest wizard (`WizardWhereGuest`)? | Yes; designer fixes the link | Phase 5 |
| 13 | **Translations source:** RN `en.json` / `nl.json` as single source generating `.xcstrings`, or iOS owns its strings? | Entered by hand for this slice | Later |
| 14 | **Performance targets and reference iPhone** (ProMotion) for device runs and the RN comparison. | Budget as proposed | Phase 3b device run, 7, 8 |
| 15 | **URL scheme:** register `chronoflow` natively (clashes with RN side by side)? | None in this slice | Phase 4 |
| 16 | **Cold start after a background kill:** always the splash, or state restoration? | Always the splash | Phase 4 |
| 17 | **Guest-draft recovery** pushing Welcome away during the moon flight: no board. | Out of slice; seam reserved | Later |
| 18 | **Icon settled by the user 2026-11-06:** reuse RN's opaque 1024 px `assets/images/icon.png` unchanged. **Open:** dark/tinted variants and a layered Liquid Glass icon need design assets; Debug display name distinction. | No distinguishing Debug name; system-derived dark/tinted appearances until designed | Non-blocking |
| 19 | **Android:** does RN keep Android, and stay the shipping iOS app until native reaches parity? | Yes | Not blocking |
| 20 | **Settled by user 2026-11-06: build native passkey sign-in in Phase 10.** Backend branch `feat/mobile-api-passkeys` at `841be4bd` provides the options/login contract (not deployed). | Retain AuthSignIn passkey button/divider; AuthenticationServices options → assertion → login; 9b builds DTOs and source methods. Registration stays out of scope. | No Phase 9 blocker; **Open device verification** requires confirmed team/bundle IDs (OQ 4), team-signed build and deployed public AASA. |
| 21 | **Password policy/hint:** board/RN says “At least 10 characters”; production requires 12+, mixed case, letters, numbers, symbols, uncompromised. Should native use server `passwordRules`? Security summary/RegisterPage expose it, but no public native rules endpoint exists. | Server validation wins; approve en/nl hint and board amendment for the production policy. Apply returned `passwordRules` to native password fields when available; do not call protected account APIs before login or scrape RegisterPage. Agree a public rules source or reviewed build-time AutoFill rules for unauthenticated Register/Reset. No client validation or reduced server policy. | **11b / 11c**; 9b decodes/contracts only |
| 22 | **ResetDone says “Other devices stay signed in.”** W ResetUserPassword invokes RevokeUserTokens; all tokens are revoked. | Correct the board and both languages to describe revocation; preserve real server behavior in mock/API tests. Do not ship the existing sentence even though RN has its nl translation. | **11b** done state |
| 23 | **Offline auth banner:** RN has “Needs a connection” with no body; AuthStates and all screen boards have no offline variant. | Propose that RN title in the existing AuthStates banner style after an approved board variant; until then defer offline presentation. Keep typed offline failures/test coverage; submit remains enabled offline. No ad-hoc popup/toast. | **10a** shared error UI and every dependent auth sub-phase; not 9 |
| 24 | **Destination while Today is unbuilt:** successful sign-in must go to `.today`; no Today implementation is included. What may simulator/Release users see? | Existing `.today` route seam and Debug-only D17 diagnostic; unverified → `.verify` seam until 11d; preserve terms/walkthrough precedence. Never invent a temporary Today/empty success screen. Ordinary Release must remain non-shipping until real destination UI exists. | **10a** navigation acceptance; shipping to that route; not 9 |
| 25 | **Verify-email link parameters and delivery:** RN/mock `{token,email}` differs from W `{id,hash,expires,signature}`; emails open web pages today and app.chronoflow.net universal links are deferred. What exact URL/path/encoding will deliver signed inputs, and what should “Open it on this phone to finish” promise meanwhile? | Use authenticated signed API DTO now, typed inputs/mock inbox in tests; recheck users/me after web verification on activation. Defer native URL/universal-link entry, pending approved URL contract/server association and production copy. No RN token-shaped API or colliding scheme. | **11d** production copy/entry policy; actual link delivery deferred; **11b** real reset-link entry only (typed/mock Reset remains possible); OQ 15 remains |
| 26 | **DB backup exclusion:** exclude all account files including unsent outbox/drafts, or preserve unsent changes across device restore? Device-only Keychain session cannot restore with a backed-up DB. | D19 proposed development default: exclude the entire account directory and sidecars from backup, keep unsent rows durable on this device; document that device loss/restore loses unsent changes. A backup/recovery product flow has no board, so defer it rather than silently back up tokens or split live WAL files. | Non-blocking **9a development** under proposed default; **Release shipping** awaits confirmation |
| 27 | **Reset promises automatic sign-in:** AuthTwoFactor reset says “You'll be signed in…”/“Save and sign in”; resetDone says “You're signed in…” and Continue links Today. API returns 204, and RN correctly returns to Sign in without a session. | Preserve no-session API behavior; propose RN's “Save new password” / “Password updated. Sign in with your new password.” and Continue → Sign in. Require approved reset/done board copy and human en/nl before implementing; do not silently add a login request or retain a password. | **11b** reset/done |
| 28 | **Exact-board translations and server field keys:** copy table marks missing exact English matches (Two-factor “type” vs RN “enter”, recovery toggle, Forgot/Verify prose, reset promises and production password messages). | A person supplies/approves nl for unchanged English, or approves a board/RN-copy amendment with its existing nl. Use exact existing values elsewhere; never machine-translate or let unknown server English leak into Dutch. This is not permission to ship `PENDING` strings. | **10a** shared field strings; **10b** Two-factor; **11a** Forgot; **11b** Reset; **11c** production password fields; **11d** Verify, each only for its missing rows |
| 29 | **Pending changes on voluntary sign-out:** RN asks before discarding, but no sign-out confirmation board is committed. | 9d returns needsConfirmation and preserves rows; defer the voluntary discard UI until designed. Forced authenticated 401 wipes immediately. Verify Back/Use a different email explicitly discards the unverified account queue, matching RN. | Future voluntary sign-out confirmation UI; not **9d** service or explicit Verify exit |
| 30 | **Undesigned failure states:** AuthStates has no arbitrary hidden-field notice, exhausted-challenge screen, store-open failure, sync-failure toast or mock inbox. | Reuse only an approved existing banner/notice variant with approved copy for hidden-field/challenge messages; obtain that mapping before 10a. Store/sync/inbox remain typed test seams with no product UI. Never build a mock inbox list, DB-error screen or new toast from RN alone. | **10a** hidden-field banner policy and **10b** challenge failures; store/sync/inbox UI deferred, not 9 service work |
| 31 | **Outbox parity vs absent endpoints:** RN final schema includes complete-trip/data-export/security kinds; W routes have no complete-trip or data-export endpoints, and RN's API adapters still defer them. How should future producers behave? | Preserve schema/kind decoding. Implement supported check-off/settings (including policy acceptance)/profile/walkthrough handlers now; do not create unsupported producers, fake endpoints or discard parked rows. Security features and unsupported writes need their own later scope/contracts. Mock may retain RN behaviors as isolated test values. | Future completion/export/security feature phases; not **9c** supported sync; no claim of full RN feature parity |
| 32 | **Keyboard overflow if measured:** can a focused input and submit both fit above the native keyboard on SE/Duo at xxLarge in every auth form? The static boards do not draw an overflowing keyboard state. | Require measured focus/submit visibility and the native return-key chain. If the matrix proves the pair cannot fit, request that state's design and defer it; do not add an undesigned sticky action, shrink text or accept a hidden submit. | Conditional **10a/10b/11 UI acceptance** for the failing state only; not Phase 9 |
