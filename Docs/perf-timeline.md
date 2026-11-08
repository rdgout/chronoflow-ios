# Trip timeline performance

The page is `PlanUI.TripPageView(tripID:repository:retention:...)`. The tab-shell worktree
can construct it at its `TripPageDestination` seam. Pass the session's shared
`SyncEngine.retention` (the same instance used by `FullPull`), and a fetch closure that
calls `FullPull.fetchDetail(tripID:epoch:)` with the current epoch. `TripPageModel` also
exposes online/sync-completed hints, `awaitingSync`, selected-day/offset, time format,
language and hidden-category preferences. Trip actions, block details, editing, Settings,
My trips and Today navigation are callbacks owned by their respective phases.

The default view is Timeline; the navigation-bar toggle is transient. Each lazily mounted
day has one Canvas. `PlanDecoder` decodes, lays out and prepares labels off-main, caching
by trip/input hash/detail version with a raw-payload guard. Block bucketing avoids scanning
the whole trip for every day. Calendar-based local dates avoid allocating date formatters
for every interval. Marks and preference changes invalidate presentation appropriately.

A worker rasterises static day drawings using generated P3 colours, registered fonts,
patterns, packed tiles, ticks and zone/continuation markers. The Canvas blits the prepared
image and adds the minute-driven now line. Packing, date formatting, text layout, patterns
and symbol rendering stay outside the draw closure. System-symbol images are shared by
all days. A four-day LRU bounds the raster cache; views release their images on disappearance.
Accessibility children use the same time-ordered prepared blocks as the list.

## Fixtures and direct launch

Debug launch arguments:

- `-cf.trip-page S3` opens S3 directly; `S1`–`S6` and a supplied mock UUID also work.
- `-cf.trip-page large30` / `-cf.trip-page large60` open synthetic trips directly.
- `-cf.timeline-fixtures` adds both synthetic trips to an isolated in-memory mock server, account directory and credential service.
  The default seven-trip mock stays unchanged. This flag does not alter a persisted server.

`MockTimelineFixtures` repeats the first six S3 days five/ten times, preserving UTC day
lengths, multi-zone ticks and overnight flights. Each day also receives S1's existing dense
caffeine structure. IDs and every instant/date argument are shifted; copy keys are retained.
Blocks are clipped at tour/day boundaries. These are structural stress fixtures, not planner
output or clinically meaningful itineraries. Tests assert unique IDs, continuous bounds,
several zones, overnight flights, populated lanes, and catalog coverage in both languages.

The ordinary Release app ignores the launch seam. The **Perf configuration** explicitly
opts in with `CHRONOFLOW_TIMELINE_PERF`; it remains optimized and keeps the existing isolated
signed-out launch setup. Synthetic fixture support is shared code; only Debug includes
additional trips in the normal mock server.

## Host benchmarks

```sh
make quick
sh Scripts/swiftpm.sh test ChronoFlowKit --filter TimelinePerformanceTests
```

Each XCTest `measure` sample decodes the full detail bytes, calls `layoutPlan` (which calls
`indexTimeline`), and runs the exact `preparePlan` used by the observation model. Fixture
construction, file I/O and initial catalog loading are outside the sample; these are cold
model preparations, rather than cache-hit measurements. Cache reuse/invalidation has
separate functional tests. The tests assert a budget on **each** sample, and XCTest reports
mean, standard deviation and ten samples.

| Fixture | Host Debug budget per sample | Observed host mean, 2026-11-08 |
| --- | ---: | ---: |
| S3 | 200 ms | 14 ms |
| 30 days | 500 ms | 41 ms |
| 60 days | 1,000 ms | 83 ms |

These are warm host-process measurements from this worktree's Mac checks, not iPhone or
simulator results. The pre-optimization 60-day host mean was 297 ms. The equivalence suite
compares bucketed layouts against a full scan for S1–S6, reversed inputs and hidden lanes.
The latest host log is `build/phase15-quick-complete.log`; fresh runs supersede these observations.

## Optimized hosted UI run — user runs this

```sh
make perf-timeline
```

This generates the project, builds the existing Perf scheme in its optimized Perf
configuration and runs **only** `PerfUITests/TimelinePerfTests` on 17e. It does not run the
seven-device matrix. `make perf` still runs only the original launch benchmark.

`test60DayTimeToFirstTimelineFrame` measures the custom
`net.chronoflow.app.native` / `Timeline` / `time-to-first-timeline-frame` signpost, plus
`XCTApplicationLaunchMetric`. The custom interval begins after fixture/database seeding,
just before creating the page model. It includes repository observation, decode, layout,
label preparation and the first day raster. It ends after the splash overlay is gone and
two display-link callbacks have passed with a ready timeline. Thus it represents a visible
committed frame, not simply a SwiftUI `onAppear`. Launch time is reported separately and
includes the diagnostic fixture setup. Tests wait for `trip.timeline.presented` so a missing
signpost/failed raster cannot silently pass.

`test60DayScrollEndToEnd` waits for that frame, then manually starts measurement and swipes
from the **first** day through all 60 days to the end card, with a 240-swipe guard. It measures
`XCTOSSignpostMetric.scrollingAndDecelerationMetric` and process memory. Three iterations
relaunch the app, so the first traversal creates day drawings lazily; this does not merely
exercise a previously warmed whole-trip raster cache.

| Metric | Acceptance budget | Aim |
| --- | ---: | ---: |
| First visible 60-day timeline frame | ≤ 2,500 ms | ≤ 1,000 ms |
| Scrolling hitch time ratio, S3 and 60 days | ≤ 5 ms/s (0.5%) | ≤ 1 ms/s |
| Frame interval | 16.67 ms at 60 Hz; 8.33 ms at 120 Hz | stay within the display interval |
| Memory growth during 60-day traversal | ≤ 40 MiB above the first-frame process footprint | stable after initial lazy allocations |

XCTest's scrolling metric supplies hitch time ratio; it is **milliseconds of hitching per
second**, not a frame count. Report the mean and worst iteration, first-frame signpost
samples, total scrolling duration and memory samples. The time/hitch/memory budgets are
review targets until a simulator/device baseline is established; UI tests enforce readiness
and full traversal, while host samples enforce their absolute time budgets. Simulator
load and refresh rate affect results, so compare on the same runtime/profile/appearance.
For S3, launch with `-cf.trip-page S3` and use the same Instruments scrolling interval.

Open the Perf `.xcresult` in Xcode and expand the Performance reports for both test methods.
The runner prints the result bundle paths under `build/test-results/17e/`; build diagnostics
are under `build/test-results/build/Perf.log`. Search the runner logs for `measured` and
`time-to-first-timeline-frame`, or export measurements with Xcode's `xcresulttool` installed
on the machine running the test. No simulator numbers are claimed here.

## Visual acceptance still to run

```sh
make generate
make targeted DEVICES="17e" ONLY="AppTests/TripPageSnapshotTests"
```

The suite injects SE, 17e and Duo profiles inside one 17e simulator, en/nl × light/dark at
default size plus one xxLarge variant for each state/profile. It covers loading, remote
loading/offline, ready timeline, no-plan, not-found/server, list/end and end-card variants.
No references were recorded, and the suite intentionally compares without recording even
if `SNAPSHOT_RECORD` is set. Missing references require a separate reviewed recording step.
The live Valet read gate, simulator runtime validation and wide-layout phase remain deferred.
