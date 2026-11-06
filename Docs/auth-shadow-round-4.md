# Phase 10a visual round 4: shadow bitmap orientation

Base: `101df9e`. The user's hosted run failed the round-3 shadow guard in all eight
Sign in states. Their discarded recording is not used as a reference.

## Cause and reproduction

The shadow bitmap was upside down when displayed by UIKit. The bitmap is created with
a raw Quartz context, whose positive shadow Y points upward. The generated board offset
is positive downward. Passing that offset unchanged puts the strongest ink above the card
in the image's rows. [Apple documents this shadow-direction difference](https://developer.apple.com/library/archive/documentation/2DDrawing/Conceptual/DrawingPrintingiOS/GraphicsDrawingOverview/GraphicsDrawingOverview.html).

The previous Mac test accidentally compensated for this: its flipped `CALayer.render(in:)`
composition also inverted the CGImage contents. Inspecting the image rows directly at
3×, six points outside the card at its horizontal centre, found alpha **19 above / 1 below**
in light and **51 above / 5 below** in dark.

Vertically reflecting that image in the old Mac layer composition, or drawing the original
image rows in their UIKit orientation, reproduces every reported below-card channel exactly:

| Appearance | Reproduced below RGB | Reported hosted below RGB | Red attenuation against sky |
| --- | --- | --- | --- |
| Light | (198.16129032, 133.08211144, 113.58944282) | (198.16129032, 133.08211144, 113.58944282) | 0.74193548 |
| Dark | (131.72727273, 72.73900293, 58.15542522) | (131.72727273, 72.73900293, 58.15542522) | 2.67741935 |

This accounts for the residual ink and identical results in all states. The bitmap exists
and overflows the card; clipping or an untriggered draw would not reproduce these values.

## Fix and guards

Negate the generated vertical offset when passing it to Quartz. The bitmap now has the
stronger halo in its lower rows, for both device display and CPU capture. Blur, spread,
opacity, color, card geometry and raster extent retain their generated values.

The Mac board guard now composites the production CGImage with explicit image coordinates
instead of letting macOS layer rendering invert it. It checks both 2× and 3×. A separate
raw-alpha guard checks downward ink across bounds changes, display scales and reused
light → dark → light layers. Restoring the old offset fails both tests (32 issues) and
reproduces the hosted values above.

Fixed Mac image composition results (all four states share this shadow geometry):

| Scale / appearance | Below RGB | Beside RGB | Largest channel error vs board |
| --- | --- | --- | --- |
| 2× light | (187.82, 127.38, 111.63) | (96.84, 78.69, 126.33) | 1.81 |
| 2× dark | (108.71, 59.94, 47.79) | (36.04, 26.83, 59.84) | 1.77 |
| 3× light | (187.55, 127.19, 111.52) | (96.71, 78.59, 126.35) | 1.54 |
| 3× dark | (108.44, 59.77, 47.72) | (35.90, 26.72, 59.79) | 1.50 |

The hosted eight-state guard retains its original samples, board RGB, four-level tolerance,
minimum red attenuation (8/20 below, 1/2 beside) and card-bottom assertion. It checks both
the existing CPU `layer.render(in:)` capture and UIKit `drawHierarchy(afterScreenUpdates: true)`.
Each path has its own plain-sky baseline. Capture success is required, and measured RGB is
logged with the capture path, appearance, state and region. The snapshot capture helper
is unchanged.

## Validation and hosted commands

`make quick` passes. Both Mac shadow guards pass; the old-direction mutation fails.
Production Auth and all hosted AppTests type-check for the iOS 17 deployment target.
All 896 existing Auth PNG SHA-256 hashes are unchanged; none is delivered in the patch.

Close-out (user's host report, 2026-11-07): corrected controls/layout/snapshots,
SignInTests and serial AuthAuditTests PASS on 17e. All 896 Auth references were re-recorded
at `04a8e8b` and committed in `8e2d542`; all eight board pairs are accepted with documented
adaptations and no defects. Only the shared-shell SE/Duo keyboard run remains under OQ 32;
see `plan.md` and `_design/frames/README.md`.
