# Plan: native iOS ChronoFlow — launch, splash animation and Welcome

## Context

ChronoFlow plans sleep, light and caffeine for each trip. Two apps exist, both read-only from here: the web app `/Users/rickgout/Sites/chronoflow-new` (product source of truth) and the Expo / React Native app `/Users/rickgout/Sites/chronoflow-mobile` (not feature complete). This plan starts a native iOS app in `/Users/rickgout/Sites/chronoflow-ios` (empty, not yet a git repo) that must perform better than the RN app.

**Where the RN launch loses time** (read from code; never timed, `docs/plan-gate.md` perf items are open):
- The overlay starts only after Hermes loads the bundle, all imports run and React commits; startup parses ~190 KB of en/nl JSON.
- Fonts load at runtime (not embedded); the wordmark and status wait for them.
- Readiness is a sequential JS chain: SecureStore read → SQLite open → migrations → sync and reminder scheduling (twice) → live queries.
- Every hand-off point (1.5 / 2 / 2.3 / 8 s) is a JS `setTimeout`, so JS stalls push the hand-off later.
- Five full-screen SVG layers in the overlay; Welcome draws `SkyBackground` twice; per-frame bezier allocation in worklets.
- The moon landing depends on JS layout (`measureInWindow`), with a fixed fallback offset.

**This slice covers:** the system launch screen; the animated splash in modes `ready`, `slow`, `welcome` plus Reduce Motion; the readiness seam that decides when and where the splash hands off; the signed-out Welcome screen with its intro stagger and the moon landing on it; light/dark, English/Dutch, accessibility; a performance budget measured against the RN app.

**It deliberately does not cover:** sign-in, guest wizard, Today, terms, verify, walkthrough (reached only through a route seam, OQ 8); database, sync, notifications, deep-link handling (the seam captures cold-start URLs and notification responses but does not act on them); guest-draft recovery (OQ 17); an in-app appearance setting; migrating RN users (OQ 9); Android. **The slice is not shippable to TestFlight**: Release builds exist only for the signed-out performance path.

**Sources:** canvas boards `SplashSpec`, `SplashScreen`, `SplashSlow`, `SplashWelcome`, `Main`, `canvas.json`, `ds/chronoflow/tokens.json` (downloaded 2026-11-05, byte-identical to `chronoflow-mobile/_design/canvas/`); `cf-sky`, `cf-press` and token variables in `chronoflow-mobile/_design/canvas/theme.css`; `pattern-dots` in `ds/chronoflow/components/bundle.css`; settled rules in RN `plan.md` Phase 21.

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

### How conflicts between design sources are settled

SplashSpec's prose gives the rule; keyframes fill what the prose leaves out. Where RN chose otherwise, it is recorded. All listed in OQ 5.

| # | Conflict | Native default | Why |
|---|---|---|---|
| S1 | Moon centre: board y 392 (30 pt above centre); prose "centred" | Centred in the window | Launch screen centres it and frame 0 must match (RN same). **Consequence on 390 × 844:** wordmark moves 432→462 (inside the band, which starts at 470) and status 488→518, below the path apex 512.5, so the path runs between wordmark and status; on 874 pt the status is above the apex (533 vs 542.5). The relation flips by device. |
| S2 | Stars at 0.55 at 0 ms; prose "0–300 static first frame, matches the system launch screen" and "300–1200 stars fade out" | 0–300 static (moon only). Stars stay at 0 throughout the opening. | The prose's static launch frame wins; any star fade-in would be invented. RN instead fades 0→0.55 over 0–300 (alternative in OQ 5). |
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
- **Store (GRDB vs SwiftData):** not needed in this slice; research leans GRDB 7 later.
- **Generating `.xcstrings` from RN `en.json` / `nl.json`:** deferred; the slice has 8 strings (OQ 13).
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

Board frame 390 × 844 pt. `w`, `h` = window size; `cy = h / 2` (S1). All times in ms from `t0` (D3).

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

**`pattern-dots`:** 7 × 7 pt tile from the layer's top-left, dot centred at 3.5; solid to r 1, linear fade to 0 at r 1.5; dot colour α0.16 × layer opacity. One layer, `backgroundColor` = pattern image rendered at screen scale.

**`cf-press`:** pressed scale 0.97, opacity 0.85, 120 ms `cubic-bezier(0.25, 0.1, 0.25, 1)`. **Reduce Motion:** pressed = opacity 0.85, scale 1, no transition (`theme.css:143-146`).

**Other constants:** path stroke white α0.55. Plane 8 pt white dot; glow disc r 6 (4 + spread 2), blur σ 5, white α0.8. Stars white (splash) / skyTitle (Welcome).

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

Fraunces is never bold. Growth beyond 52 pt belongs to OQ 10.

### Splash layer tree and geometry (any `w × h`)

The container **is** the splash root: full window, ignores safe areas, `masksToBounds`, background skyTop, anchor (0.5, 0.4) with position adjusted so it still fills the window. Exit animations live on it, so `-cf.freezeAt` covers them. Sublayers, in order:

| Layer | Geometry |
|---|---|
| sky | `CAGradientLayer` `cf-sky`, full window; opacity animated |
| stars | top 60 % of `h`, white pattern-dots |
| halo | `CAGradientLayer(.radial)` centred on the sun, approximating `box-shadow 0 0 80 20` dawn α0.45 (disc r 110 blurred σ 40). **Alpha 0 for r < 90** (CSS clips an outer shadow inside the border box); pixel check at r ≈ 85 |
| sun | 180 × 180, centre (w/2, h − 194), `cornerRadius` 90 + `masksToBounds` (no mask layer). Radial dawn: solid to r 70, α0 at r 91.6 (gradient radius 127.3) |
| band | bottom-anchored, 374 pt tall (top = h − 374); skyHorizon with alpha 0 / 0.22 / 0.70 / 1.0 at 0 / 0.40 / 0.75 / 1.0; above the sun |
| path | `CAShapeLayer`, cubic (−10, h − 204) → (90·w/390, h − 374), (300·w/390, h − 374) → (w + 10, h − 204); stroke 1.5, butt caps. x scaling is RN's rule; board silent (OQ 11) |
| plane | dot + glow (constants above), centred on the path, no rotation |
| moon | `LaunchMoon` contents, 288 × 288, centre (w/2, cy), pixel-aligned, `minificationFilter = .trilinear`. Glyph 104 pt: Lucide `M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z`, viewBox 24, stroke 1.6, round caps/joins, dawn; glow dawn α0.45 σ 9 baked |
| wordmark | `LaunchWordmark` contents, box top cy + 40, height 40, centred |
| status | top cy + 96, height 20, centred: text layer (created when needed) + dot layer with `CAReplicatorLayer` ×3 (4 pt, gap 3, margin-left 6, currentColor) |

### Timeline: shared opening (all modes)

| Element | Property | Keys (ms: value) | Easing |
|---|---|---|---|
| Stars | opacity | 0 throughout (S2) | — |
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
| Stars | opacity 0 → 0.2 | W+100 → W+700 | ease-out |
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

- Background: one `CfSky` + pattern-dots in skyTitle over full height at layer opacity 0.2.
- Padding: top `max(safeTop + 16, 64)`, sides 24, bottom `max(safeBottom, 40)` (RN's rule; board is fixed 64 / 24 / 40; on Dynamic Island phones top becomes ~78 — OQ 10).
- Column `space-between` inside a scroll view (RN). Top group gap 16: moon row (Lucide moon 28 × 28, stroke 2 → 2.33 pt, dawn, no glow; gap 8; wordmark), eyebrow (+56 margin above), headline. Bottom group gap 12: copy card (+12 margin below), "Plan my trip", "Sign in".
- Board geometry on 390 × 844: moon row y 64–92, eyebrow 164–180, headline from 196, "Plan my trip" 688–740, "Sign in" 752–804.
- Moon anchor: `onGeometryChange(for: CGRect.self) { $0.frame(in: .global) }` → `MoonAnchorStore`.
- Fallback target centre: x = 24 + 14, y = max(safeTop + 16, 64) + rowHeight / 2, where rowHeight = max(28, wordmark line height at current size).

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

## Tasks

### Phase 0: Scaffold and tooling (`feat/phase-0-scaffold`)

Unblocked (OQ 1–4 settled 5 Nov).

- [x] `git init -b main` (done); first commit `docs: add plan, working rules and design copy` with `plan.md`, `CLAUDE.md`, `AGENTS.md` (Codex reads it; same rules), `_design/canvas/` (five boards, `canvas.json`, `ds/chronoflow/{tokens.json,README.md,components}`, `SOURCE.md` with canvas URL and download date). Branch `feat/phase-0-scaffold`. (`main` holds only `e277d5d`.)
  Files: `plan.md`, `CLAUDE.md`, `AGENTS.md`, `_design/**`.
  Test: one commit on `main`; branch exists.
- [ ] Export board reference frames: render each board in the canvas (Chrome) at the board key frames (ready 0/700/1400/1900, slow 2600/4900, welcome 1500/1950/2400/3300, Welcome final), light and dark; record the method. Notes: board dots are not frozen (`dot()` ignores `frozen`), so dot opacity is excluded; `Main` ignores `at` and loops its intro, so Welcome content at 2400/3300 is compared against the `Main` keyframes, not the render.
  Files: `_design/frames/**`, `_design/frames/README.md`.
  Test: a frame exists for every listed time and theme.
- [x] XcodeGen 2.46.0 is installed. `project.yml`: target `ChronoFlow` (iOS 17.0, iPhone, portrait, Swift 6, Debug ID `net.chronoflow.app.native`, `Local.xcconfig` include for `DEVELOPMENT_TEAM`), `AppUITests`, `PerfUITests`; schemes `ChronoFlow` and `Perf` (Release). `.gitignore`: `*.xcodeproj`, `DerivedData`, `build/`, `Local.xcconfig`; `Local.xcconfig.example` committed. Verify XcodeGen output opens and builds in Xcode 27.2. (Orchestrator verified generation and full build via `make generate && make check`, 5 Nov; AppIcon explicitly unset per OQ 18. See `Docs/tooling.md`.)
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
- [x] Primitives: `CfSkyLayer` / `CfSky`, `PatternDots`, `PressStyle` (Reduce Motion: opacity 0.85, scale 1, no transition), `MoonShape`.
  Files: `Sources/DesignSystem/{CfSky,PatternDots,PressStyle,MoonShape}.swift`.
  Test: snapshots light/dark; unit test of `PressStyle` values with and without Reduce Motion.

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
- [x] `FlightPath`: bottom-anchored cubic for any size, 1024-sample arc-length table, `point(atFraction:)`, fraction curve. (OQ 11 default assumed, confirm). The 1024-entry table and 128 moving position keys preserve the 560 ms fraction knot. Host numerical and rendered stroke-tip tests pass every 10 ms; cubic trimming drift required the specified sampled-polyline fallback for the displayed path. Board length/apex and short/wide fixtures pass; iOS 17 compile/type-check passes.
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
- [x] `withWelcomeExit`. (OQ 6 default assumed, confirm). No moon cross-fade; stars retain the board geometry during the dissolve. (OQ 7 default assumed, confirm). W starts at max(1600 ms, resolution time). Host tests cover every ending key, one straight-line progress for centre/scale, landing within 0.01 pt, changed targets, late endings, opening preservation when added at 50 ms and Reduce Motion. Hosted D1c landing tests and the continuing matrix runner are written; iOS 17 compile/type-check passes.
  Files: `Sources/Launch/LaunchTimeline+Welcome.swift`.
  Test: moon lands on a given target to 0.01 pt; opening keys intact when added at 50 ms.

### Phase 3b: Core Animation scene (`feat/phase-3b-scene`)

Verified by the orchestrator on 2026-11-06: all seven D1c devices, make check and make duo passed. Device runs need OQ 4 (team) and OQ 14 (device). The physical-device D3 proof stays open; Phase 3c snapshot work proceeds by user direction.

- [x] `LaunchScene` layers (landed as one commit; accepted): sky/stars/band; sun/halo; path/plane; moon/wordmark; status (text created lazily + replicated dots). `apply(_:)` sets model values from `sample`. (OQ 6 default assumed, confirm). Stars retain the board geometry; Reduce Motion dots hold at 1.0, with the existing ease-out fade and no moon cross-fade. Complete layer tree, radial sun/clipped halo with generated alpha ramps, sampled path, baked plane glow, generated moon/wordmark and lazy localized status are implemented. The halo has a 250 pt radius and the sun has the designed 127.3 pt radius on both axes; host pixel tests verify both gradients at 2×/3×. Sampled scale transforms retain Z = 1 so render(in:) draws the moon and container at their sampled sizes. Frame geometry uses 1e-9 accuracy for anchor arithmetic residuals. Host tests and iOS 17 type-check pass.
  Files: `Sources/Launch/LaunchScene.swift`, `Sources/Launch/LaunchScene+Layers.swift`, `Sources/Launch/StatusLineLayer.swift`.
  Test: layer list equals the spec; no layer has `mask`, `filters`, `compositingFilter` or `shadowOpacity > 0`.
- [x] `LaunchOverlayController` + `SceneDelegate` order (D3, D14): overlay window (root VC `preferredStatusBarStyle = .lightContent`, VoiceOver element "ChronoFlow is opening" with its `nl` in the same commit), `isHidden = false`, opening tracks added, `CATransaction.flush()`, `t0` recorded; main window + root next run-loop turn; font registration detached; capture `connectionOptions` into `PendingLaunchIntent`. Verify which window drives the status bar; if not the overlay, set it on the main hosting controller until hand-off. Overlay is committed before scheduling the SwiftUI root, fonts register detached, intents are captured without routing, and a process-owned gate prevents replay. Both controllers request light status bars. Hosted ordering/reconnection/accessibility tests and UI coverage are written and iOS 17 type-checked. Actual status-bar appearance stays open (needs a device; open).
  Files: `Sources/Launch/LaunchOverlayController.swift`, `Sources/AppCore/PendingLaunchIntent.swift`, `App/SceneDelegate.swift`, `Sources/Launch/Resources/Localizable.xcstrings`.
  Test: signposts show `overlay-first-commit` ends before the root's first layout; UI test finds the element; a second scene connection mounts no overlay.
- [x] Launch arguments: `-cf.freezeAt <ms>` (container `speed = 0`, `timeOffset`), `-cf.mode ready|slow|welcome` (applies `withReadyExit(1500)`, `withStatus(2000)` + exit at `-cf.readyAt` (default 4600), or `withWelcomeExit(1600, fallback target)` without the coordinator), `-cf.mainThreadStall <ms>` (blocks main at 300 ms). (OQ 10 default assumed, confirm). Fallback landing uses all four safe insets and the current text size (28 pt row at the default category). (OQ 11 default assumed, confirm). Bottom anchoring and width-scaled path are retained. Arguments, merged playback and live freeze are implemented; parser/mode tests, light/dark sample-vs-presentation comparisons every 100 ms (0–3200) and the independent 700 ms XCUITest model reference are written and iOS 17 type-checked. Because tracks retain absolute nonzero t0, freezing uses timeOffset = t0 + elapsed seconds; elapsed alone would predate every animation. Position and interior-opacity comparisons use a 0.0005 tolerance for CA’s duration-dependent solver epsilon at 1 s. The independent host bisection reference checks all four presets at 1001 progress values to 0.0001; the tighter intro(0.95) = 0.9997243836889174 regression remains at 1e-12. The screenshot retains its original error limits, measures errors away from edges and the moon’s best alignment shift (≤0.5 pt), and includes 1 pt offset/20% opacity mutation checks. Runner and comparison fixtures pass.
  Files: `Sources/Launch/LaunchScene+Freeze.swift`, `App/LaunchArguments.swift`.
  Test: hosted test: `sample(at:)` equals `layer.presentation()` values on a frozen container at 0…3200 every 100 ms (this is also the bezier solver check against CA); XCUITest screenshot at `-cf.freezeAt 700` matches the 700 snapshot within tolerance.
  Runner: `python3 -I Scripts/launch-simulators.py --scene` covers all seven D1c devices and then attempts both `make check` and `make duo`.
- [ ] Signpost intervals ("Points of Interest"): `launch` (scene connect → overlay removed), `first-commit` (scene connect → flush), `session`, `ready`, `exit`, `intro`. Early D3 proof: one device Animation Hitches run with `-cf.mainThreadStall 500`. (OQ 14 default assumed, confirm). Proposed budget retained. Interval APIs, idempotent pairing tests and real connection/flush/root-layout markers are implemented; readiness/exit/intro call sites remain in Phases 4/5. Device trace, zero-hitch and ProMotion pacing proof are not run (needs a device; open). OQ 4 team and the reference device are still missing. See `Docs/perf/2026-11-06-d3-spike.md`; Phase 3c proceeds by user direction, and snapshots must be re-checked if the device proof changes the layer tree.
  Files: `Sources/AppCore/LaunchSignposts.swift`, `Docs/perf/<date>-d3-spike.md`.
  Test: 0 hitches in 0–1500 ms with the stall; frame intervals ≈ 8.3 ms on ProMotion. If this fails, stop and revisit D3 before Phase 3c.

### Phase 3c: Splash snapshots (`feat/phase-3c-snapshots`)

- [x] Implement the sampled splash snapshot suite and commit the 154 recorded baselines: all eleven frames in light/dark on every D1c device, opt-in recording, running-window and asymmetric/side-only inset geometry, host coverage and S1 checks. Pin `make test` and `make snapshots` to en/US and resolve slow snapshot copy from the explicit English Launch catalog. Host checks cover baseline completeness and Makefile language arguments. Verified by the orchestrator on 2026-11-06: snapshot, package and hosted tests passed on all seven D1c devices. The dark frozen-screenshot UI test captured light appearance on every device except 18 Pro, also failing make check and make duo. Appearance synchronization is corrected below; revised UI validation is open.
  Files: `Tests/LaunchTests/LaunchSnapshot*.swift`, `Tests/LaunchTests/__Snapshots__/**`, `Package.swift`, `Makefile`, `Tests/test_launch_resources.py`.
  (OQ 6 default assumed, confirm). (OQ 10 default assumed, confirm). (OQ 11 default assumed, confirm). Snapshot work proceeds before the physical-device D3 proof by user direction; re-check if that proof changes the layer tree. The D3 device task stays open (needs a device; open).

- [ ] Snapshots via `sample(at:)`, light and dark, on iPhone 17e for the full set and on every D1c device (iPhone SE, Air, 18 Pro Max, iPhone Duo at least) for 0, 1400 and welcome 2400; a geometry test asserts on each size that the moon, wordmark, status, sun and path stay inside the window and its horizontal safe area:
  ready 0, 700, 1400, 1700 (↔ board 1900), 1900; slow 2600, 4900 (readyAt 4600); welcome 1500, 1950, 2400 (fallback target); Reduce Motion 0.
  Files: `Tests/LaunchTests/LaunchSnapshotTests.swift`, `Tests/LaunchTests/__Snapshots__/**`.
  Test: recorded, reviewed side by side with `_design/frames/`, then pass. Status vs path apex: assert and record the relation on 844 and 874 (S1).
  Note: implementation and recorded baselines are complete above; this acceptance task stays open for PNG/board-frame approval and revised UI validation. `_design/frames/` is absent. Full path containment conflicts with the designed endpoints, which bleed 10 pt beyond both edges; no inset redesign/default is provided. Tests preserve the bleed and assert vertical bounds/clipping. S1: status top 518 is below apex 512.5 at height 844; top 533 is above apex 542.5 at height 874.

- [x] Add the `--snapshots` D1c runner mode with compare-only default, optional record pass only under `SNAPSHOT_RECORD=1`, explicit en/US, failure continuation and final `make check` / `make duo`. Fixture tests cover recording isolation, all devices, failures and Duo runtime selection.
  Files: `Scripts/launch-simulators.py`, `Tests/test_launch_simulators.py`.

- [x] Document the committed snapshot entry point, explicit recording/language rules, geometry limits and the orchestrator's dated results.
  Files: `Docs/tooling.md`.

### Phase 3b review fixes

- [x] Guard notification payloads with `JSONSerialization.isValidJSONObject` before serialization. Capture identifier/action/payload/text through a testable AppCore function; Date, Data, non-string keys, nested invalid values and nonfinite numbers retain response metadata with nil JSON. Host tests also cover valid JSON and empty payloads.
  Files: `App/SceneDelegate.swift`, `Sources/AppCore/PendingLaunchIntent.swift`, `Tests/AppCoreTests/LaunchLifecycleTests.swift`.

- [x] Resolve the overlay opening accessibility label immediately after the first flush and first-commit signpost, keeping string-table I/O out of construction. Hosted tests check the label is absent before commit and available afterward; connection accessibility assertions are retained.
  Files: `Sources/Launch/LaunchOverlayController.swift`, `App/SceneDelegate.swift`, `AppTests/LaunchConnectionTests.swift`.

- [x] Pin device appearance before launching frozen screenshot parity in separate light/dark UI tests. After setting appearance, terminate any running instance, return to SpringBoard and poll the device's reported appearance with a 10-second bound before launch. Async teardown terminates the app and waits for appearance restoration before the next test. Each appearance must match its own model and clearly differ from the opposite model; retain displacement/opacity mutation checks. Hosted connection assertions check the overlay window inherits the scene style. Revised UI validation is open.
  Files: `AppUITests/LaunchSceneTests.swift`, `AppTests/LaunchConnectionTests.swift`.

- [x] Record the accepted single-commit delivery of the scene layers and replace superseded Phase 3a/3b simulator narratives with the dated verified results. Retain the rendering/clock/solver rationale and physical-device open items.
  Files: `plan.md`, `Docs/tooling.md`.

### Phase 4: Readiness and hand-off (`feat/phase-4-readiness`)

Defaults authorized for OQ 7, 8, 9, 15 and 16; confirmation remains open.

- [x] `Route` (`.welcome`, `.today`, `.signIn`, `.guestWizard`, `.terms`, `.verify`, `.walkthrough`) and `Navigator`; `RootView` mounts the gate's route from its first frame; Debug-only route screen per OQ 8.
  Files: `Sources/AppCore/Route.swift`, `App/RootView.swift`, `App/Debug/RoutePlaceholder.swift`.
  Test: hosted navigator tests cover every route and the unresolved state; Phase 4 UI tests read route identifiers after hand-off. (OQ 8 default assumed, confirm). Route seam plus Debug-only route-name placeholders, including the temporary Welcome seam until Phase 5; Release renders no placeholder text. Simulator validation is open.
- [x] Reducer, `LaunchClock` (`CACurrentMediaTime`, `t0` from D3), `ManualLaunchClock`.
  Files: `Sources/AppCore/LaunchReadiness.swift`, `Sources/AppCore/LaunchCoordinator.swift`, `Sources/AppCore/LaunchClock.swift`.
  Note: pure reducer, media/manual clocks and staged coordinator are implemented. A cancellable stored-data stream extends the one-shot seam so a first load can move false → true. (OQ 7 default assumed, confirm). Late signed-out starts at resolution; unknown session defaults signed out at eight seconds. Reducer/clock/coordinator tests are written; simulator validation is open.
  Tests: ending chosen once; hand-off waits for animation and readiness; signed out ready at once; terms/verify/walkthrough ready without data; ready before 1500 emits exit at 1500; status committed at 2000 only when `hasStoredData == false`, cancelled if ready first, never for `nil`, latched; 8 s forces readiness and `allowFirstLoad` once for the current session; unresolved session at 8 s → OQ 7 default; welcome exit emitted on first anchor, re-emitted on anchor change before W, fallback at W − 50; Reduce Motion skips the wait; exit once; `PendingLaunchIntent` never changes the ending.
- [x] `SessionStore` + `KeychainSessionStore` (native service `net.chronoflow.app.native`, account `session`, JSON `{token, accountId}`; malformed → delete, signed out). `StubReadiness` via `-cf.session`, `-cf.gate`, `-cf.stored yes|no|never`, `-cf.readyDelay <s>`. Release wiring: signed out always (only the perf path runs Release).
  Files: `Sources/AppCore/SessionStore.swift`, `App/Readiness/KeychainSessionStore.swift`, `App/Readiness/StubReadiness.swift`, `App/LaunchArguments.swift`, `project.yml`, `Tests/test_launch_resources.py`.
  Test: protocol-backed in-memory parse/delete tests, hosted Keychain round-trip/malformed deletion, Debug parser/delayed-update and Release override-isolation tests are written. Simulator signing is ad-hoc without a team so the hosted app can use Keychain. The stub explicitly implements the async stream requirement; concrete and protocol calls share the injected absolute deadline. Tests use sleep-registration expectations, cover passed deadlines/cancellation and keep each iterator within one detached task. The orchestrator's 6 Nov Debug pass found unsigned Keychain access and a missing manual-clock sleep/readiness update; revised simulator validation is open. (OQ 9 default assumed, confirm). Native-only key; migration deferred until a bundle switch. (OQ 15 default assumed, confirm). No URL scheme. Release always resolves signed out; the readiness store performs no synchronous I/O on the main actor.
- [x] Hand-off wiring: coordinator effects rebuild the timeline (D4); "Getting your plan ready" + `nl` added; on exit completion (`CATransaction` completion block) hide and release the window, clear `accessibilityElementsHidden`, post `.screenChanged`, restore status bar; announce status once, queued.
  Files: `Sources/Launch/LaunchOverlayController.swift`, `Sources/Launch/StatusLineLayer.swift`, `Sources/Launch/Resources/Localizable.xcstrings`, `App/SceneDelegate.swift`.
  Note: merged timeline effects, isolated exit-opacity CATransaction completion, stale-completion guards, window release, accessibility restoration/queued status and session/ready/exit signposts are implemented. Existing Launch catalog already contains both status translations. The root is created only once a route resolves, on the next main-loop turn. (OQ 16 default assumed, confirm). Every cold process start splashes; reconnects do not replay. The orchestrator's 6 Nov Debug pass found intermittent immediate weak-reference assertions after teardown. Lifetime tests now use scoped autorelease pools and bounded run-loop draining before requiring deallocation, including disconnection during a pending exit; production completion captures remain weak and both delegate references are cleared. Hosted and UI tests are written; revised simulator validation is open. Welcome visuals, measured anchor publication and intro remain Phase 5. Device status-bar/performance checks remain in the open Phase 3b/8 tasks.
  Test: UI tests: signed out → `Route.welcome`; signed in + ready → `Route.today`; `-cf.stored no -cf.readyDelay 3.5` → status, hand-off ≈ 3.5 s; `-cf.stored never` → hand-off at 8 s; element tree hidden until hand-off.

- [x] Add the `--readiness` D1c simulator runner mode, en/US throughout, all Phase 4 Debug hosted/UI suites plus Release override-isolation tests, failure continuation and final `make check` / `make duo`; include readiness UI checks in `make duo`. The dedicated `ReadinessRelease` scheme builds only the app and hosted tests, with testability enabled only for that verification command; package test bundles stay in Debug. Fixture tests cover the full matrix, failure aggregation, scheme isolation and Duo runtime selection. Simulator validation is open.
  Files: `Scripts/launch-simulators.py`, `Tests/test_launch_simulators.py`, `Makefile`, `project.yml`.

### Phase 5: Welcome, intro and moon hand-over (`feat/phase-5-welcome`)

Blocked by OQ 10, 12 (and OQ 6 for the moon cross-fade).

- [ ] `WelcomeView` per layout and typography, one `CfSky`, scroll view; six strings with `nl` in the same commit; header trait; reading order.
  Files: `Sources/Welcome/WelcomeView.swift`, `Sources/Welcome/WelcomeBrand.swift`, `Sources/DesignSystem/Buttons.swift`, `Sources/Welcome/Resources/Localizable.xcstrings`.
  Test: snapshots on the D1c matrix (iPhone Duo required), light/dark, en/nl, default and OQ 10 sizes; on 390 × 844 the board geometry above; on Duo nothing sits under the side rail or horizontal insets.
- [ ] Moon anchor → `MoonAnchorStore` → `LaunchEvent.moonAnchor`.
  Files: `Sources/AppCore/MoonAnchorStore.swift`, `Sources/Welcome/WelcomeBrand.swift`.
  Test: UI test at `-cf.freezeAt 2300`: flying moon centre within 0.5 pt of Welcome's moon on every D1c device (iPhone Duo required), and at the largest agreed text size.
- [ ] `IntroItem` (index, `LaunchIntro` from environment: start, clock, optional frozen time); live `.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.45).delay(start + offset − now)`; first launch of the process only.
  Files: `Sources/Welcome/IntroItem.swift`, `Sources/AppCore/LaunchIntro.swift`.
  Test: offsets; snapshots at 2400, 2450, 2700, 3200, 3300; second appearance has no intro.
- [ ] Buttons → `Navigator`: "Plan my trip" → `.guestWizard`, "Sign in" → `.signIn`; `PressStyle`; 52 pt.
  Files: `Sources/Welcome/WelcomeView.swift`.
  Test: UI tests for both routes; `performAccessibilityAudit()` on Welcome.

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
- **Short 667 pt screens**: bottom-anchored sun/band may overlap the centred moon. OQ 11.
- **Bundle ID / Keychain.** Carry-over only possible under the final ID; migration is its own phase.

## Open questions for the user

| # | Question | Default | Blocks |
|---|---|---|---|
| 1 | ~~Commit trailer~~ **Settled 5 Nov: no trailer** (RN rule). | — | — |
| 2 | ~~Tooling installs~~ **Settled 5 Nov:** user approved installs; XcodeGen 2.46.0 and SwiftLint 0.65.1 installed (SwiftLint unused unless adopted), `fonttools` venv and `swift-snapshot-testing` when their phase needs them. | — | — |
| 3 | ~~Minimum iOS~~ **Settled 5 Nov: iOS 17.0** (D1), Liquid Glass on 26+ (D1b). | — | — |
| 4 | **Settled 5 Nov:** `net.chronoflow.app.native` in development, local git only, no remote. Still open: Apple team ID (device runs from 3b) and whether native later takes `net.chronoflow.app`. | — | Device runs from 3b |
| 5 | **S1 and S2 settled 5 Nov:** moon centred; no stars in the opening. S3–S6 as listed (prose wins). | As listed | — |
| 6 | **Undesigned details:** Reduce Motion dot opacity and fade easing; flying moon (1.87 pt stroke, glow) vs Welcome moon (2.33 pt, no glow) — cross-fade or not; splash stars top 60 % vs Welcome full height during the dissolve. | Dots hold at 1.0; ease-out; no cross-fade; as boards | Phase 3a / 5 |
| 7 | **Late or unknown session:** signed out known after 1600 → welcome ending at that moment, or the `ready` lift-away? Session unknown at 8 s → signed out? | Start at resolution; signed out | Phase 4 |
| 8 | **Stub destinations:** (a) Debug-only route-name screens, (b) inert buttons, (c) route seam only, (d) bring `AuthSignIn` / `TodayLoading` in. | (c) + (a), never in Release | Phase 4 |
| 9 | **Session source and migration.** Is the RN app live with real users? If native later ships as `net.chronoflow.app`, should it read the RN Keychain item (`app:no-auth` / `session`) and migrate SQLite, kv-store, `api.deviceId`? | Native-only key now; decide at bundle switch | Phase 4 (shape only) |
| 10 | **Welcome at large Dynamic Type, 667 pt screens, long Dutch headline; safe-area padding** (`max(safeTop+16, 64)` gives ~78 on Dynamic Island phones vs board 64). | Scroll as RN; RN padding rule; scaling capped as RN | Phase 5 |
| 11 | **Short, wide and iPad screens:** every iPhone including iPhone Duo must fit (D1c, settled). Still open: iPhone portrait only (does Duo need its other postures)? Sun, band and path on 667 pt and wide widths? | RN rule: x control points × w/390, bottom-anchored | Phase 3a |
| 12 | **Stale board link:** `Main` links "Plan my trip" to superseded `GuestFlight`; target is the new guest wizard (`WizardWhereGuest`)? | Yes; designer fixes the link | Phase 5 |
| 13 | **Translations source:** RN `en.json` / `nl.json` as single source generating `.xcstrings`, or iOS owns its strings? | Entered by hand for this slice | Later |
| 14 | **Performance targets and reference iPhone** (ProMotion) for device runs and the RN comparison. | Budget as proposed | Phase 3b device run, 7, 8 |
| 15 | **URL scheme:** register `chronoflow` natively (clashes with RN side by side)? | None in this slice | Phase 4 |
| 16 | **Cold start after a background kill:** always the splash, or state restoration? | Always the splash | Phase 4 |
| 17 | **Guest-draft recovery** pushing Welcome away during the moon flight: no board. | Out of slice; seam reserved | Later |
| 18 | **App icon and Debug display name:** reuse RN's icon or wait for a board; distinguish the Debug build on the home screen? | No icon and no distinguishing name until you decide | Phase 0 (non-blocking) |
| 19 | **Android:** does RN keep Android, and stay the shipping iOS app until native reaches parity? | Yes | Not blocking |
