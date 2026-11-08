# Hosted profile snapshots

All seven D1c profiles render inside one 17e simulator using explicit point size, four safe-area
insets and display scale from `Tests/SnapshotSupport/profiles.json` in ChronoFlowKit.
`SnapshotContainerTests` checks rendered fixture geometry, bounds, scale and pixels under normal and
larger parent insets. Profile Welcome hosts disable system safe-area injection and pass all four fixture
insets directly to the shared `WelcomeGeometry`; the UIKit safeAreaInsets getter is not the fixture.

References are named by profile alias, geometry and scale, never the executing simulator model.
Welcome covers both languages/appearances, the profile's Dynamic Type categories and intro times.
Splash covers the profile's frames in both languages/appearances at large and xxLarge.
Image capture guards reject uniform/transparent/failed Welcome images; comparison uses identical
immutable PNG → sRGB RGBA decoding on both sides, with exact channel equality. The fully exited
`ready-1900` splash explicitly requires zero alpha everywhere; every other splash requires visible content.
One window is reused per profile, with fresh SwiftUI identities for distinct states and matching committed
rasters/frames before capture. Equivalent landed/capped/non-localized frames reuse their raster.

The old per-simulator references were deleted for tooling round 3 (2026-11-06).
The failed recording's 708 partial PNGs were removed. New baselines are deliberately absent until the orchestrator records and visually reviews them:

```sh
make generate
SNAPSHOT_RECORD=0 make targeted DEVICES="17e" ONLY="AppTests/SnapshotContainerTests"
SNAPSHOT_RECORD=1 /usr/bin/time -p make snapshots
SNAPSHOT_RECORD=0 make snapshots
SNAPSHOT_RECORD=0 /usr/bin/time -p make check
```

Recording uses one 17e process and one worker. `make matrix` is opt-in and is unnecessary for recording.

Second fix round (2026-11-06): Welcome capture now uses CPU layer rendering instead of drawHierarchy.
The user's 792 recorded PNGs are retained unchanged. Re-record the 320 Welcome references with
`SNAPSHOT_RECORD=1 make targeted DEVICES=17e ONLY=AppTests/WelcomeSnapshotTests`; its comparison follows
automatically. The 472 splash references retain their existing capture path. Comparison remains exact.


Phase 11b–11d references are intentionally absent until user recording/review: Auth/Reset (104),
Auth/SignUp (130), Auth/Verify (130). They use the lean three-profile/five-variant-per-state policy
(one xxLarge reference on 17e, four default variants on each profile). Existing Forgot PNGs are
unchanged. See Docs/tooling.md for targeted recording/comparison commands.
