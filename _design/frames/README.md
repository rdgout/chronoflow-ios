# Auth board references

`node Scripts/export-auth-boards.cjs` exports standalone HTML from the committed boards and the
actual component bundle, for Sign in none/wrong/locked/server, AuthStates and Field/Button/Notice,
in light and dark. Open `auth/*.html` in Chrome at 375 × 812 (AuthStates: 375 × 1900;
controls: 375 × 1200).
The exports preserve the board's sample field values for design comparison only. Native fields start
empty. Embedded source CSS and local committed fonts avoid the unavailable canvas `support.js` and
`/_blob` URLs. The user-authorized plain-sky change removes the obsolete dot div.

The controls export uses the bundle's Field normal/error/hint and Button outline/loading/disabled
states and info Notice. Focus uses the bundle's native `:focus-visible` rule when the field is focused.
The native adaptation grows 36/40-point field/button surfaces to at least 44 points, allows wrapping,
adds safe-area insets and scrolls. Text sizes remain those of the board, through the root xxLarge cap.

PNG exports now exist in ignored `build/board-png/`: the user generated all 12 on the host with
headless Chrome (375 points wide at 3×). The exact command used, substituting the name and height:

```sh
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=3 --window-size=375,<812|1900 banners|1200 controls> --screenshot=build/board-png/<name>.png file://$PWD/_design/frames/auth/<name>.html
```

`make auth-board-pngs` regenerates the HTML and runs that export for all names with the matching
heights through `Scripts/export-auth-pngs.sh`. Run it on the host: Chrome headless exits 134 in this
sandbox. PNG outputs stay in `build/` and are not committed.

Visual review on 2026-11-06 compared all eight Sign in board/native pairs (none/wrong/locked/server,
light/dark; native wrong = credentials) against recorded `AppTests/__Snapshots__/Auth/board-*.png`.
Codex confirmed the reported differences by inspecting each pair before editing. All eight had
outline-button exterior hairlines and continuous rather than semicircular button/footer ends.
AuthButton's fills, outline `strokeBorder` and hit shape now explicitly use `Capsule(style: .circular)`;
the old code used SwiftUI's default continuous capsule. There is no second system bordered style:
the native Button uses PressStyle. New hosted pixel guards check both end caps against analytic
circles of radius height/2, require their fill/outline, and reject exterior ink at 2×/3×, large/xxLarge,
in both appearances. Final visual acceptance remains pending the corrected hosted renders.

The darker light-mode **Create an account** link is an intentional text-contrast adaptation. The
board's `.cf-sky` scope overrides `--dawn-text` with `var(--dawn)` even inside the card. Native keeps
the base `dawn-text` semantic token, following `tokens.json`'s usage rule and the web's
`resources/css/app.css` / `docs/ui/claude-design/DESIGN-SYSTEM.md` dawn-text change: dawn fills and
borders use `dawn`, text on light surfaces uses `dawn-text`. This preserves the strict
[WCAG 1.4.3](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html) text-contrast policy
(4.5:1 for this text). It adds no audit exemption and leaves OQ 33's accepted border/guest pairs intact.
Ratios computed from generated Display P3 tokens, converted to linear sRGB and relative luminance
with gamut clipping, on the actual `card` token:

| Appearance | dawn / card | dawn-text / card |
| --- | --- | --- |
| Light | 2.5456:1 (fails) | 5.4441:1 (passes) |
| Dark | 9.2888:1 (passes) | 9.2888:1 (passes; same token value) |

Host contrast tests pin these four ratios; a hosted pixel test pins the actual link ink to `dawnText`
in en/nl and both appearances. The other differences remain the documented 44-point control growth
(card grows upward with its bottom anchored), empty native fields, safe-area/scroll adaptation and
allowed text wrapping. Header, typography, sky, banners and control colors otherwise match the
reviewed boards within those adaptations.

The **896 Auth references must be re-recorded** on 17e after the capsule change, then compared again
and visually reviewed. Recording remains the user's work; this fix round does not update PNGs.
Run `AppTests/AuthControlTests`, `AppTests/AuthLayoutTests` and `AppTests/AuthSnapshotTests`
(all D1c sizes and AX5 equality), then `AppUITests/SignInTests` and serial `AppUITests/AuthAuditTests`.
`DesignSystemTests/AuthBoardContrastTests` also runs in `make quick`. The shared-shell acceptance
task stays open until corrected visual/snapshot and remaining keyboard acceptance are complete.
