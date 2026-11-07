# Auth subtitle contrast

User decision, 2026-11-07, extended in Phase 11a fix round 1: **ignore Apple's contrast result
only for the shared `auth.subtitle` on every auth screen, and only while that screen’s rendered
pixels prove every visible line is at least 4.5:1.** This covers Sign in, Two-factor and Forgot now,
and Reset, Sign up and Verify when implemented. Every other
text element stays strict. `(sign-in.guest, .contrast)` remains the only unconditional allow-list
pair (OQ 33); this adds no token, design or snapshot change.

`AuthAuditTests` matches the exact `auth.subtitle` accessibility identifier and `.contrast` type,
then requires a unique static-text subtitle in a unique containing scroll view with the issue's frame.
There is no screen-name allow-list; a new auth screen must pass its own measurement.
Inside that issue handler it captures the app screenshot, reads the live safe-area/scroll/keyboard
viewport and subtitle frame, derives scale from the raster/app bounds, and uses the audited
appearance and default/xxLarge category with generated `skyTitle` and `Typography.authBody`.
`RenderedTextContrast` decodes the screenshot to sRGB and samples clean background pixels inside
each visible line's rectangle. Samples must be far from the ink token (at least 0.1 in one sRGB
channel) and flat across their 3 × 3 neighbourhood (within 2/255 per channel). Every visible pixel
row needs a clean local sample; no clean background means no measurement. The minimum ratio uses
the worst local background, including bright patches behind the subtitle, never the window edge.

Ink coverage is projected against each row's local background. Pixels with at least 10% coverage
count as ink, including antialiasing and dimmed text. At least 40% of those pixels must be within
0.03 per channel of the token, with at least one visible line-height's worth of near-token pixels
(and at least three). This rejects a mostly dimmed line even if some opaque pixels survive. The
reported ink is the darkest qualifying pixel, rather than the closest match. The exception still
requires the measured minimum to be **≥ 4.5:1** on every visible line.

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
default/xxLarge × Sign in/code/recovery and Forgot form, field error, attempts, server, offline
and sent. It reveals controls in the audit's order, measures the actual subtitle frame after each scroll, verifies clean background pixels across the subtitle's
columns against the corresponding x/y pixels of a full-window rendered board sky, samples rendered
text ink and background behind each line, and prints ratios, frames and scroll
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

Fix round 3 host fixtures cover a bright local patch with the left screen edge unchanged, the
corresponding x/y sky mismatch, one surviving token pixel, 37.5% surviving token pixels amid dimmed
ink, normal antialiasing, and a rectangle without clean background. Read-only remeasurement of all
80 saved round-1 crops remains measurable and above 4.5:1; sampled background differences from the
same-row sky stay within 2/255. This is sampler validation, not a new simulator acceptance run.

Phase 11a’s supplied Forgot audit failures were excluded from measurement by the previous
Sign in/Two-factor scroll-name gate. The gate is removed; the same unique-element, visible-line,
finite-ratio and ≥ 4.5:1 requirements apply. This policy change does not establish a passing Forgot
measurement: revised hosted and UI execution remains required.
