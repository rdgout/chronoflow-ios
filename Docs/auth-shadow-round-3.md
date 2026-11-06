# Phase 10a visual round 3: card shadow

Measured against HEAD `5228ba3` and the user's 896 subsequently recorded Auth references.
All 896 reference SHA-256 hashes were captured before work and verified unchanged afterward.
No reference was recorded, removed, staged or included in the delivery patch.

## Measurements before the fix

Core Graphics decoded each PNG into 8-bit, premultiplied RGBA in sRGB, matching
`SnapshotRaster`. Both supplied PNG types already declare sRGB. All images are 1125 × 2436.
Coordinates start at the top left, in physical pixels; bounds below are inclusive:

- Below: x = 555–565, y = 2188–2218, in the card/footer gap.
- Beside: x = 1080–1120, y = 1495–1505, beside the card's right edge.
- Sky control: x = 0–5, y = 2188–2218.

Each entry is mean **(R, G, B)**. `wrong` maps to the native `credentials` banner.
Board paths are `build/board-png/sign-in-{state}-{appearance}.png`; native paths are
`AppTests/__Snapshots__/Auth/board-{appearance}-en-large-{banner}.png`.

| Pair | Board below | Native below | Board beside | Native beside |
| --- | --- | --- | --- | --- |
| light / none | (186.01, 126.20, 110.77) | (198.90, 133.63, 113.65) | (95.55, 77.76, 125.51) | (98.07, 79.53, 127.12) |
| light / wrong | (186.01, 126.20, 110.77) | (198.90, 133.63, 113.65) | (95.55, 77.76, 125.51) | (98.07, 79.53, 127.12) |
| light / locked | (186.01, 126.20, 110.77) | (198.90, 133.63, 113.65) | (95.55, 77.76, 125.51) | (98.07, 79.53, 127.12) |
| light / server | (186.01, 126.20, 110.77) | (198.90, 133.63, 113.65) | (95.55, 77.76, 125.51) | (98.07, 79.53, 127.12) |
| dark / none | (106.94, 58.82, 46.92) | (134.40, 74.16, 59.22) | (35.00, 26.12, 59.03) | (38.81, 28.86, 64.62) |
| dark / wrong | (106.94, 58.82, 46.92) | (134.40, 74.16, 59.22) | (35.00, 26.12, 59.03) | (38.81, 28.86, 64.62) |
| dark / locked | (106.94, 58.82, 46.92) | (134.40, 74.16, 59.22) | (35.00, 26.12, 59.03) | (38.81, 28.86, 64.62) |
| dark / server | (106.94, 58.82, 46.92) | (134.40, 74.16, 59.22) | (35.00, 26.12, 59.03) | (38.81, 28.86, 64.62) |

Red min–max, identical across all four states in each appearance:

| Appearance | Board below | Native below | Board beside | Native beside |
| --- | --- | --- | --- | --- |
| light | 179–193 | 196–202 | 93–98 | 97–99 |
| dark | 97–116 | 132–137 | 32–38 | 38–40 |

The native sky-control means are (198.93, 133.65, 113.65) light and
(134.42, 74.20, 59.27) dark. Native below-card values equal plain sky to within 0.05
levels per channel: the references have no measurable shadow there. These are the actual
values in the supplied files; the earlier review's quoted ranges differ.

## Change and rendered guard

The previous SwiftUI inset shape used `.blur`, a render-server effect absent from these
CPU captures. `AuthCardShadowLayer` now bakes the shadow with Core Graphics and places the
result in an overflowing sublayer behind the existing SwiftUI card fill. All appearance
colors, opacity, offset, spread and blur come from generated `ColorToken.authShadow` and
`AuthTokens`. CSS blur diameter is twice the generated sigma; Quartz shadow parameters
are converted to device pixels. The bitmap includes three sigmas plus the offset on each
side so the halo is not cut off at the card bounds. It updates with bounds, appearance and
display scale. No token, card layout, splash or capture-helper changes.

The Mac test renders the actual production shadow layer and card over `CfSkyLayer` at 3×,
with the board's card width and bottom edge. Its card top is above both sample regions;
the native touch-target adaptations grow cards upward without moving their bottom edge.
It reuses the layers across light → dark → light changes. Results:

| Appearance | Fixed below RGB | Fixed beside RGB | Largest absolute channel error vs board |
| --- | --- | --- | --- |
| light | (187.55, 127.19, 111.52) | (96.71, 78.59, 126.35) | 1.54 |
| dark | (108.44, 59.77, 47.72) | (35.90, 26.72, 59.79) | 1.50 |

Shared board fixtures require each mean channel within four 8-bit sRGB levels. They also
require red attenuation against a capture without shadow: at least 8/20 levels below and
1/2 levels beside for light/dark. This explicitly rejects missing side ink even where the
board's light side attenuation is smaller than the absolute color tolerance. Removing the
shadow makes both the tolerance and ink checks fail.

`AuthControlTests.testCardShadowMatchesBoardInkInAllEightSignInStates` applies the same
checks to full hosted Sign in screens, including layout, clipping and background order.
It captures plain sky first and never writes references.

## Validation and references

`make quick` passes: strict formatting, all package/TokenGen/AssetGen host tests and
3 signing / 10 launch-resource / 53 simulator-runner fixtures. The production Auth module
and hosted AppTests type-check against the iOS 17 deployment target. The new host rendered
test passes and its missing-shadow mutation fails as expected.

CoreSimulator access is unavailable in this sandbox, so corrected full iOS renders and
the new hosted guard remain pending. No final visual acceptance is claimed. Run the hosted
Auth controls/layout/profile suites on 17e, re-record **all 896 Auth references**, and review
all eight board pairs again. Existing references remain untouched and uncommitted. No
seven-simulator matrix or Duo runtime run is needed for this change.
