# Auth board references

`node Scripts/export-auth-boards.cjs` exports standalone HTML from the committed boards and the
actual component bundle, for Sign in none/wrong/locked/server, Two-factor code none/field/attempts/server
and recovery none/attempts/server, AuthStates and Field/Button/Notice,
in light and dark. Open `auth/*.html` in Chrome at 375 × 812 (AuthStates: 375 × 1900;
controls: 375 × 1200).
The exports preserve the board's sample field values for design comparison only. Native fields start
empty. Embedded source CSS and local committed fonts avoid the unavailable canvas `support.js` and
`/_blob` URLs. The user-authorized plain-sky change removes the obsolete dot div.

The controls export uses the bundle's Field normal/error/hint and Button outline/loading/disabled
states and info Notice. Focus uses the bundle's native `:focus-visible` rule when the field is focused.
The native adaptation grows 36/40-point field/button surfaces to at least 44 points, allows wrapping,
adds safe-area insets and scrolls. Text sizes remain those of the board, through the root xxLarge cap.

PNG exports exist in ignored `build/board-png/`: the user generated the original 12 Sign in/shared
control exports and the later 14 Two-factor exports on the host with headless Chrome (375 points wide at 3×). The exact command used, substituting the name and height:

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

Shared-shell SE/Duo keyboard acceptance is settled under OQ 32 at 9505993, with the user's
visible-keyboard passes. The later helper/audit changes and round-4 corrections still need the
user's updated simulator reruns, as recorded in `Docs/auth-gate.md`.

Final Two-factor board review — fix round 4 (user's side-by-side report, 2026-11-07):
all seven board states were compared with the native 17e references, in light and dark.

| Board / native state | Visual result |
| --- | --- |
| code none / attempts / server | **acceptable-adaptation** |
| code field / fieldError | **defect corrected**: the plain rejected-code backend key now maps to the board's “That code didn't work. Codes change every 30 seconds, so try the newest one.” and its approved Dutch translation. Updated references/comparison remain the user's run. |
| recovery none / attempts / server | **placeholder defect corrected**: catalogued `xxxx-xxxx` in both languages, marked `shouldTranslate: false`, drawn with `mutedForeground`. Recovery attempts otherwise passes as an acceptable adaptation. Updated references/comparison remain the user's run. |

Accepted adaptations stay: the shared Field error state's red border (as on the controls board),
44-point native controls and the resulting upward card shift, empty native fields and plain sky.
Recovery field-error captures retain the designed shared Field treatment and approved backend copy;
there is no separate recovery-error board. The placeholder changes every empty recovery capture,
including fieldError, and is excluded from the accessibility value; the label remains “Recovery code”
(“Herstelcode” in Dutch).

The board export's ghost toggle row previously showed raw `onclick` / `toggleRecovery` /
`setState({ recovery: … })` template text. This was an **export bug, not design**. The exporter now
removes inert `on-*` template attributes before interpolating render values, so a function's quotes
and arrow cannot corrupt the import tag or leak into its label. All 14 Two-factor HTML exports have
been regenerated; PNGs from the earlier export should be regenerated with `make auth-board-pngs`.
The read-only canvas is unchanged.

`make quick` passes. Intentional native reference changes are **code-fieldError and recovery-***,
in en/nl, light/dark and every existing D1c profile/category. The user will record these on 17e,
compare them in a fresh process and rerun the updated simulator gates before pushing. No new
simulator/reference comparison pass is claimed here; the implementation and board-review work is
complete under the user's task-2 closeout instruction.
