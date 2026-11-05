The four iOS primitive baselines under `PrimitiveSnapshotTests/` were recorded on iPhone 17e / iOS 27.2
and visually approved by the orchestrator on 5 November 2026: light/dark at 240 and 560 pt wide.
Run `make check` outside the implementation sandbox to verify them without recording new references.
These are isolated primitive fixtures, not screen layouts or device-size assumptions. The fixture uses
320 pt height and 3× rasterization on every simulator so the same baselines work throughout the matrix.
