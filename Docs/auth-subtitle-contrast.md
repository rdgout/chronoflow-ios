# Auth subtitle contrast, Phase 10b fix round 1

The 17e serial rerun still reports strict contrast failures. **There is no new exemption or design
change.** The rendered failure screenshots do not reproduce a 4.5:1 text-contrast failure. An audit
false positive is a hypothesis, not an accepted exception. Task 2 remains open.

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

The hosted test and revised strict UI audit need the user's simulator run. CoreSimulator access is
denied in this sandbox; direct iOS compilation is not a hosted measurement pass. If the hosted
measurement finds a board-matching ratio below 4.5, retain the audit failure and add a new Open
question with those measured values, default **none — needs the user's design decision**. If pixels
continue to pass while the system audit fails, investigate the audit discrepancy without widening
OQ 33. The only allowed pair remains `(sign-in.guest, .contrast)`.

```sh
make generate
make targeted DEVICES="17e" ONLY="AppTests/AuthSubtitleContrastTests AppTests/AuthSnapshotGuardTests AppTests/DataSourceFactoryHostedTests AppUITests/AuthSessionTests AppUITests/AuthAuditTests"
```
