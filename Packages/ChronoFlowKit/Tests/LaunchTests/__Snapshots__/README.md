# Splash snapshots

Record on the D1c simulator matrix with `python3 -I Scripts/launch-simulators.py --snapshots`.
The runner compares all eleven Phase 3c samples in both appearances on every device.
`SNAPSHOT_RECORD=1` opts into recording; without it, tests compare and missing baselines fail.
Xcodebuild receives that variable as `TEST_RUNNER_SNAPSHOT_RECORD`.

Images use the running window size, its four safe-area insets and its display scale. Filenames include
simulator model, point dimensions, scale, appearance, mode and time. No other catalog scale is loaded. Slow frames resolve the Launch catalog explicitly in English,
independently of the host or runner language.
Samples render only the splash overlay, including its transparency during the exit; Welcome content
belongs to Phase 5. Dots use the sampled replica opacities rather than the board's running dot animation.

Review PNGs against the splash boards and plan keyframes: ready 1700 maps to board 1900 (S3), the moon
is window-centred (S1), stars/pattern-dots are removed (user 2026-11-06; S2), the path follows the light's arc length (S5),
and the Welcome flight uses ease-in-out (S4) to the safe-area fallback. S1 places status top 518 below
path apex 512.5 on the 844 pt fixture, and top 533 below apex 527.5 on the 874 pt fixture: the same 5.5 pt clearance.

The user's 2026-11-06 rule centres the 844 pt composition at every height. Re-record launch and Welcome
together with `SNAPSHOT_RECORD=all python3 -I Scripts/launch-simulators.py --welcome`.
The unchanged 844 frames are compared even in record mode; only its two Welcome-exit samples
(1950/2400) may change with the no-pattern decision. Revised recordings and visual approval are open.

154 baselines were recorded on 2026-11-06. PNG approval and side-by-side review against exported board frames remain open.
`_design/frames/` has not been exported. Do not generate replacement board frames from app rendering.
Re-check these snapshots if the physical-device D3 proof changes the layer tree.

Test-speed decision (2026-11-06): the current per-model profiles are in
`Packages/ChronoFlowKit/Tests/SnapshotSupport/profiles.json`. Full coverage stays on SE/17e/Duo/Pro Max;
17/Air/18 Pro keep the compact selection. There are 118 retained references. Retained PNGs have
not been re-recorded; visual acceptance and the SE fresh/warmed-process comparison remain open.
Use the current commands at the top of `Docs/tooling.md`; earlier recording notes above are historical.
