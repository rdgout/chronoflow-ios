# ChronoFlow iOS

ChronoFlow is a jet-lag planner. It plans sleep, light and caffeine for a trip. This repo is the native iOS app (Swift, UIKit scene life cycle hosting SwiftUI), built to perform better than the Expo / React Native app.

`plan.md` is the plan. Work one phase at a time, tick each task in the same commit that completes it, and follow its Decisions (D1–D17), spec and Open questions. Do not start a task whose phase is blocked by an open question.

## Sources (read-only)

- `_design/canvas/`: the design boards (`*.dc.html`), `canvas.json` and the design system (`ds/chronoflow/tokens.json`, `README.md`, `components/`). The canvas itself is a claude.ai artifact the user maintains; this is a local copy.
- `/Users/rickgout/Sites/chronoflow-mobile`: the RN app. Its `plan.md` Phase 21 holds settled splash rules. Read it; never write to it, and never run `expo prebuild` or builds inside it.
- `/Users/rickgout/Sites/chronoflow-new`: the web app, the product source of truth. Read-only.

## Working rules

- **No design, no invention.** If a screen or state has no board, stop and say so. Deferring beats inventing.
- **Values only from generated tokens and assets**, light and dark. No hard-coded colours or 390 × 844 geometry.
- **Every iPhone, iPhone Duo included.** Splash and Welcome geometry is computed from the window size and all four safe-area insets (Duo has a side rail). Verify on the device matrix in `plan.md` D1c.
- **Minimum iOS 17.0.** No `#available` checks below 17.
- **Liquid Glass on iOS 26+.** Never set `UIDesignRequiresCompatibility`. Use system controls so they pick up Liquid Glass automatically. Explicit glass APIs only behind `if #available(iOS 26, *)` with the plain system default as fallback, never a hand-drawn imitation. Designed surfaces stay as drawn.
- **Native components** over hand-built look-alikes of system controls.
- **English and Dutch together.** Every visible string goes into a String Catalog with its `nl` value in the same commit. Never hard-code customer-facing text.
- **Copy** promises a clock shift, never symptom relief.
- **No unneeded comments.** Write only the comment that records a *why* the code cannot show.
- **Performance.** No synchronous I/O on the main thread before the splash overlay is committed. No `+load` or static initialisers. No `mask`, `filters` or shadows in the splash layer tree.

## Commands

| Command | What it does |
| --- | --- |
| `make generate` | Generate `ChronoFlow.xcodeproj` from `project.yml` (the project file is not committed) |
| `make check` | Lint, generator freshness and host tests, unit tests and snapshots; run before every commit |
| `make format` | Format owned Swift sources with the toolchain formatter |
| `make lint` | Run strict Swift formatting lint on the host |
| `make test` / `make snapshots` | Run the individual suites on the pinned iPhone 17e / iOS 27.2 |
| `make duo` | Run window/UI checks on the first available iPhone Duo on its iPhone19-4 iOS 27.2 runtime; resolve its destination dynamically |
| `make perf` | Run the Release `Perf` scheme (launch metric scaffold until Phase 7) |
| `make tokens` / `make fonts` / `make assets` | Regenerate the committed tokens, static fonts and launch assets |
| `make generators-check` | Verify generated outputs, fonts and raster assets and run their host tests; first run needs network (see `Docs/tooling.md`) |
| `Scripts/ci.sh` | Run `make generate check` locally |

Simulators: Xcode 27.2 with iOS 27.2 runtimes (iPhone SE 3rd gen, 17e, 17, Air, 18 Pro, 18 Pro Max, iPhone Duo). Duo runs on its own runtime (`com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4`, build 24B91016s); the regular runtime (24B8117) has no Duo device type. Use `make duo`, which resolves by device type and runtime instead of name/OS or a fixed UDID. No iOS 17 simulator runtime is downloadable for Xcode 27.

## Git

- One branch per phase (`feat/phase-N-slug`), stacked. Never commit to `main` directly after the first docs commit; never merge, push or force-push unless asked. There is no remote yet.
- Commits are atomic and follow Conventional Commits: `type(scope): subject`, lower-case imperative subject. No `Co-Authored-By` or other trailers.

## Traps

- `xcode-select` points at full Xcode (`/Applications/Xcode.app`); keep it that way.
- The launch screen is cached by iOS. After changing it: Clean Build Folder, delete the app, restart the Simulator.
- `*.xcodeproj` is generated; edit `project.yml`, never the project file.
- Hosted `AppTests` must depend only on `ChronoFlow`, using `TEST_HOST` / `BUNDLE_LOADER`; linking its package products again duplicates resource-bundle accessors and crashes package test processes.
- XcodeGen target presets override project-level settings. Set `TARGETED_DEVICE_FAMILY: "1"` and `SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD: NO` on every iOS target to keep it iPhone only.
- XcodeGen defaults to an `AppIcon` asset; its setting stays empty until OQ 18 resolves the icon design.
- Fonts are registered from the package with `CTFontManagerRegisterFontsForURLs`, not `UIAppFonts`.
- The launch storyboard is not localised.
- `make snapshots` runs the DesignSystem, Launch and Welcome test suites; Phase 1 has four approved primitive baselines, with launch image baselines added in Phase 3c.
- `Config/Base.xcconfig` optionally includes ignored `Config/Local.xcconfig`; copy `Local.xcconfig.example` there for a device team. Simulator builds use ad-hoc signing (`CODE_SIGN_IDENTITY = -`) with no team; disabling signing breaks hosted Keychain access (`errSecMissingEntitlement`).
