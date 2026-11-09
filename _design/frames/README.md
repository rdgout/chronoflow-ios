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

Final visual acceptance round 3 (user's host report, 2026-11-07): all eight Sign in pairs
(none/wrong→credentials/locked/server × light/dark) are **acceptable-adaptation**, with no defects.
Capsules, outline hairline and card shadow match. Hosted guards pin circular end caps, reject
exterior outline ink and compare the downward card shadow against the board in both capture paths.

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
in en/nl and both appearances. Accepted adaptations are 44-point controls (card grows upward with
its bottom anchored), empty native fields, the dawn-text link, plain sky, safe-area/scroll handling
and a banner wrapping one word earlier (nit).

All **896 Auth references** were re-recorded on 17e at `04a8e8b` and committed in `8e2d542`.
User's host runs PASS: `AppTests/AuthControlTests`, `AuthLayoutTests`, `AuthSnapshotTests`
(all D1c sizes and AX5 equality), `AppUITests/SignInTests`, serial `AuthAuditTests` and
`DesignSystemTests/AuthBoardContrastTests`.

Only the shared-shell SE/Duo keyboard acceptance remains open (OQ 32). Run
`make targeted DEVICES="se duo" ONLY="AppUITests/SignInKeyboardTests"` on the host. The suite
checks email/password focus at xxLarge with field errors and the server banner in en/nl, using
real keyboard frames and retaining geometry/screenshots. If the pair cannot fit, record the
undesigned keyboard state and defer under OQ 32 without changing the layout.
