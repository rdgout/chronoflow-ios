# Auth subtitle contrast, Phase 10b fix round 2

User decision, 2026-11-07: **ignore Apple's contrast result only for the Sign in and Two-factor
subtitle, and only while rendered pixels prove every visible line is at least 4.5:1.** Every other
text element stays strict. `(sign-in.guest, .contrast)` remains the only unconditional allow-list
pair (OQ 33); this adds no token, design or snapshot change.

`AuthAuditTests` matches the exact `auth.subtitle` accessibility identifier and `.contrast` type,
then requires a unique static-text subtitle in the current auth scroll view with the issue's frame.
Inside that issue handler it captures the app screenshot, reads the live safe-area/scroll/keyboard
viewport and subtitle frame, derives scale from the raster/app bounds, and uses the audited
appearance and default/xxLarge category with generated `skyTitle` and `Typography.authBody`.
`RenderedTextContrast` decodes the screenshot to sRGB, finds actual rendered ink within each visible
line, and samples the unobstructed sky at the same pixel rows behind it. CfSky is horizontally uniform.
Every visible line must have measurable ink; missing lines, offscreen-only text, mismatched bounds,
conversion/capture failures and minima below 4.5 fail. No ratio from a different screen, stage or
hosted run can exempt an issue. Logs/retained attachments report context, frames, measured/expected
line count, per-line ratios/ink and the overall measured minimum (or `unmeasurable`), alongside the
source screenshot. Combined types, nil/prefix identifiers and every other text element stay strict.

The user's round-1 `make check` passed the hosted pixel guard, capture guards, sessions and Release
readiness. Its system audit repeated the same 80 subtitle results. The revised exception still needs
the user's simulator execution; no new audit pass is claimed here.

The following saved-crop measurements are **round-1 diagnostic evidence**, not inputs to the exception.

The saved `build/test-results/17e/Debug-serial.xcresult` contains 80 failing subtitle element crops:
32 English Two-factor, 32 Dutch Two-factor and 16 Dutch Sign in. Exported read-only with:

```sh
xcrun xcresulttool export attachments --path build/test-results/17e/Debug-serial.xcresult --output-path build/phase-10b-audit-attachments
```

Each crop was matched to its attached failure context. Decode into sRGB, sample the unobstructed
sky on each ink-bearing row, and compare the rendered opaque text colour with that row's sky using
WCAG relative luminance. Group ink rows into their two displayed lines. Values below are the minimum
ratios within each line, across every saved reveal stage and both Two-factor modes. The matching
stages have identical measurements. None of these crops shows the subtitle over the orange bottom.
Dutch Sign in failures in this result are at xxLarge; no default-size Sign in failure crop exists.

| Subtitle | Size | Light line 1 / line 2 | Dark line 1 / line 2 |
| --- | --- | --- | --- |
| Two-factor, en and nl, code and recovery | default | 10.8872 / 10.6966 | 15.7349 / 15.5897 |
| Two-factor, en and nl, code and recovery | xxLarge | 10.8559 / 10.4839 | 15.6097 / 15.4609 |
| Sign in, nl | xxLarge | 10.8559 / 10.4839 | 15.6097 / 15.4609 |

Rendered foreground sRGB bytes are `(244, 249, 255)` light and `(229, 236, 246)` dark, within
raster quantisation of the generated `skyTitle` P3 token converted to sRGB. Per-crop/context values
and filenames are in `build/phase-10b-audit-crop-ratios.log`. Additional read-only measurements of
the committed board/17e PNGs agree: the lowest Two-factor subtitle ink-row ratio at xxLarge is
10.7269 light / 15.5719 dark on the board fixture, and 10.3586 / 15.3765 on 17e. Those static PNG
measurements are in `build/phase-10b-static-subtitle-17e.log`; they do not execute the app.

`AuthSignIn.dc.html` and `AuthTwoFactor.dc.html` inherit `--sky-title` and draw the subtitle at
Figtree 400, 16/24. `AuthScreen` uses generated `skyTitle` and `Typography.authBody` (the same
font/size/leading). The native sky uses the generated CfSky ramp over the window; the 17e crop
backgrounds and committed PNGs agree within rasterisation differences. There is no evidence here
for changing the token, moving the subtitle or redesigning the gradient. The condition for a new
design Open question (board text below 4.5:1) has not been established.

`AppTests/AuthSubtitleContrastTests` now renders the board and 17e fixtures, en/nl × light/dark ×
default/xxLarge × Sign in/code/recovery. It reveals controls in the audit's order, measures the
actual subtitle frame after each scroll, verifies the background against a full-window rendered
board sky, samples rendered text ink and sky behind each line, and prints ratios, frames and scroll
offsets. Missing ink and ratios below 4.5 fail. It never reads or writes snapshot references. The
portable sampler has host checks for actual ink, blank lines and luminance arithmetic.

The hosted guard now uses the same measurement-completeness check as the UI audit, including
partially visible subtitles. Portable host mutations cover a missing second line (one passing line
must not suffice), fully blank/invisible text and low contrast. UI policy checks pin exact identity,
type, finite measurement and the 4.5 threshold. UIKit execution remains the user's check; CoreSimulator
access is denied in this sandbox. Task 2 also retains its existing Two-factor side-by-side board review.

```sh
make generate
make targeted DEVICES="17e" ONLY="AppTests/AuthSubtitleContrastTests AppTests/AuthSnapshotGuardTests AppTests/DataSourceFactoryHostedTests AppUITests/AuthSessionTests AppUITests/AuthAuditTests"
```
