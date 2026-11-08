# Trip timeline performance

The page is `PlanUI.TripPageView(tripID:repository:retention:...)`. The tab-shell worktree
can construct it at its `TripPageDestination` seam. Pass the session's shared
`SyncEngine.retention` (the same instance used by `FullPull`), and a fetch closure that
calls `FullPull.fetchDetail(tripID:epoch:)` with the current epoch. `TripPageModel` also
exposes online/sync-completed hints, `awaitingSync`, selected-day/offset, time format,
language and hidden-category preferences. Trip actions, block details, editing, Settings,
My trips and Today navigation are callbacks owned by their respective phases.

The default view is Timeline; the navigation-bar toggle is transient. Each lazily mounted
day shares one static vector drawing across lazy Canvas strips. `PlanDecoder` decodes, lays out and prepares labels off-main, caching
by trip/input hash/detail version with a raw-payload guard. Block bucketing avoids scanning
the whole trip for every day. Calendar-based local dates avoid allocating date formatters
for every interval. Marks and preference changes invalidate presentation appropriately.

Scroll geometry is consumed by a plain tracker, outside SwiftUI/Observation state. The
relative offset is retained in an `@ObservationIgnored` field for plan replacement; the
observable anchor changes only when the day ID changes. The navigation subtitle changes
only at a header boundary. On iOS, the compact header's continuous fade updates the hosted
view's alpha directly, including Reduce Motion and accessibility visibility. The same
preference-based tracker works on iOS 17; it never publishes per-frame geometry.

Equatable day rows keep stable content, layout, language and action inputs. Clock readers
are isolated children observing a per-day clock projection. Only the active day changes on
a minute tick; crossing a UTC day boundary clears the previous day and updates the new one. `PlanDecoder` computes now text off-main for the active day once per
PlanClock tick (and after a content/preference change). A minute tick can move the now line
without invalidating the static drawing. The day navigation uses a lazy horizontal stack.

A worker records static day drawings as immutable **vector PDF display lists**, including
text, patterns, symbols, ticks, tiles and labelled zone dividers. Canvas draws these vectors
directly in lazy strips no taller than half the page viewport (with a touch-height floor).
There are no full-height app-owned RGBA day images. The actor cache is bounded by **4 MiB
of vector payload and four entries**, rather than four 13–16 MB rasters. Shared small symbol
images are the only app-owned rasters. Views release their vector drawing on disappearance.
Host regression tests traverse all 60 days at phone and Duo widths, enforce a 512 KiB
per-drawing ceiling and the cache limit, and verify cache reuse/invalidation. The latest
symbol-free host fixture drawing peaks at 39,081 bytes; this is a display-list size, not a
process-memory measurement. System Canvas backing and PDF/font caches still count toward
the unchanged 40 MiB **process-growth** budget below and require the optimized UI run.

Accessibility children use each tile's hit frame, gutter-marker position, zone-divider pill
and visible tick position. The now element occupies its drawn line/pill region. The pill
sizes to its localized text and scaled 600-weight tabular font, including 12-hour time.

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

## Four guarantee layers

1. **Host budgets in `make quick`.** Every cold preparation sample must stay below the
   absolute S3/30-day/60-day limit. Fixture, layout equivalence, bounded-vector/cache and
   metric-budget tests also run here. The limits apply unchanged to Debug and Release;
   an optimized build cannot loosen them.
2. **Optimized UI budgets in `make perf-timeline`.** Run this Release-optimized Perf
   scheme on 17e for **every change touching PlanUI or PlanCore**, including its layout,
   presentation, renderer or scrolling behavior. Also run after changing the fixture,
   Perf harness, tokens/fonts used by the timeline or these budgets. This is a required
   acceptance command; `make quick` cannot run the iOS rendering measurement. The
   ordinary `make check`/CI tier is unchanged and does not automatically run this command.
   Record the result below before accepting such a change.
3. **Invalidation guard in `make quick`.** `TimelineInvalidationTests` registers
   Observation probes around the actual `TripDayRow.body` and its actual clock child for
   all 60 days, in Timeline and List modes. 120 offset changes and an anchor boundary
   must invalidate **zero** static rows or clock children and preserve equatable row
   inputs. One minute tick must invalidate **zero** static rows and **one** clock child;
   crossing a day boundary must invalidate **zero** static rows and **two** clock children.
   The positive control observes the anchor change. This guards dependency fan-out,
   rather than simulating SwiftUI's render scheduler. All counters/probes live in the
   test target, with no Release instrumentation. The bounded drawing/cache tests cover
   static rendering separately.
4. **On-device Instruments review by the user.** Before release, and after material
   rendering changes, profile S3 and large60 with Animation Hitches, Time Profiler and
   Allocations on a physical iPhone. Scroll early/middle/late days, switch list/timeline,
   jump days and leave the page. Check 60 Hz (16.67 ms) and, on a Pro, 120 Hz (8.33 ms)
   frame pacing, main-thread preparation, backing-store allocations and memory recovery.
   Simulator budgets give repeatable regression gates, not a guarantee for every device
   or system load. Record device/OS/appearance/type size and mean/worst hitch ratio;
   aim for ≤ 1 ms/s and keep process growth within 40 MiB over the first visible frame.

## Why the old end-to-end swipe test timed out

`layoutDay` uses elapsed **UTC** minutes × `PlanMetrics.pointsPerMinute`, currently
40 pt/hour. The six-day cycle is **24, 24, 13.5, 25.5, 24, 24 hours**, giving
**960, 960, 540, 1,020, 960, 960 pt**. Ten cycles produce exactly **54,000 pt** of
fixed-height grids; caffeine density only affects columns, never that height.
`LargeTimelineFixtureTests.sixtyDayGridHeightMatchesTheRepeatedUTCSpans` enforces this.

The outer stack has 63 children (summary, day navigation, 60 days, end card), hence
**62 × 12 = 744 pt** of section gaps, plus 16 pt bottom padding. Each timeline day also
contains its collapsed header and lane headings. Using the design line heights at
standard type size: a normal header is approximately 26 + 4 + 44 + 2 × 8 = **90 pt**;
ten warning headers add approximately 24 pt each, and 60 lane headings add 14 pt each.
Thus the default timeline is approximately **61,224 pt + summary + day navigation +
end card + 16 pt**. Native font metrics, wrapping, expanded notices and Dynamic Type
make the text-sized parts variable; this is a layout estimate, not an iOS fitting-size
measurement. The grid and section-gap totals are exact.

**List mode is a replacement for the grids**, not additional content below them. The
fixture prepares **740 rows: 720 ordinary blocks and 20 zone-change cards**. Per-day
row gaps total (740 − 60) × 8 = **5,440 pt**. An ordinary one-line-title row has a nominal
design height of (20 + 4 + 18) + 2 × 12 = **66 pt**. Its list-body estimate is therefore
**47,520 pt + 5,440 pt + the 20 fitted zone cards**, with the same day headers, 744 pt
outer gaps, summary/navigation/end and bottom padding. Lane headings disappear. Text
wrapping increases row heights, and zone cards fit their instruction/comparison text;
there is no fixed 960 pt/day list height. The perf test explicitly starts in Timeline.

The fixture's minimum lane widths are only **252 or 268 pt**, below the 17e content width
(390 − 2 × 16 = 358 pt), so `DayTimelineView` does **not** insert its horizontal overflow
ScrollView there. Day navigation's horizontal scrolling is confined to the top day pills.
The sticky header only updates alpha; continuous geometry is not observed. The vertical
`ScrollViewReader` restores position at initial load, content revision/day-set replacement,
or an explicit day/toggle action. A clock tick does not change the prepared plan.
No unconditional per-swipe reset was found in app code.

The page is legitimately tens of thousands of points tall. XCTest `.fast` specifies
velocity, not a minimum distance: the old test neither measured progress nor guaranteed
that 240 gestures could cover it. Its log records about **2.7 s/gesture + 0.17 s/end query**;
240 gestures alone require about **689 s**, before launch and repeated iterations. Even
one complete guarded attempt cannot fit the 600 s allowance; three cannot yield metrics.
The old log has no offset samples, so it cannot establish the exact displacement of those
210 swipes or prove a gesture-routing defect. The replacement logs the opening/final day
and fails if 15 gestures do not advance, exposing that failure without another ten-minute
wait. No visual geometry was changed to satisfy an automation traversal limit.

## Host benchmarks

```sh
make quick
sh Scripts/swiftpm.sh test ChronoFlowKit --filter TimelinePerformanceTests
```

Each XCTest `measure` sample decodes the full detail bytes, calls `layoutPlan` (which calls
`indexTimeline`), and runs the exact `preparePlan` used by the observation model. Fixture
construction, file I/O and initial catalog loading are outside the sample. These are cold
model preparations, rather than cache hits. A monotonic `ContinuousClock` assertion gates
**every sample**, independently of XCTest's relative baseline UI. XCTest reports ten samples.

| Fixture | Absolute budget per sample, Debug and Release | Latest targeted host mean (2026-11-08) |
| --- | ---: | ---: |
| S3 | **40 ms** | 19 ms |
| 30 days | **100 ms** | 50 ms |
| 60 days | **200 ms** | 92 ms |

The limits provide approximately 2× headroom over the supplied 18/46/91 ms Debug means.
Using the same absolute ceilings in both configurations avoids conditional thresholds or
calibration that could hide a regression. Run on an otherwise idle Mac; investigate a
failure instead of automatically increasing limits. These are host-process measurements,
not device claims. The latest focused log is `build/timeline-guards.log`, and the complete
package run is `build/timeline-package.log`. Fresh runs supersede these observations.

## Optimized hosted UI run — user runs this

```sh
make perf-timeline
```

This generates the project and runs **only** `PerfUITests/TimelinePerfTests` in the optimized
Perf configuration on 17e. It does not run the seven-device matrix. `make perf` still runs
only the original launch benchmark. Each timeline test has a 300 s execution allowance.

`test60DayTimeToFirstTimelineFrame` measures the custom
`net.chronoflow.app.native` / `Timeline` / `time-to-first-timeline-frame` signpost and
`XCTApplicationLaunchMetric` over three iterations. The custom interval begins after
fixture/database seeding, before model creation. It includes repository observation,
decode, layout, preparation and the first day drawing. It ends after the splash has gone
and two display-link callbacks have passed with a ready timeline. Readiness/presentation
assertions also fail on a missing signpost or drawing. Launch time includes diagnostic
fixture setup and is reported separately, without a timeline-frame budget.

`test60DayScrollEndToEnd` now measures a **fixed 15 fast upward gestures per iteration**,
with three iterations and a fresh app launch each time. Readiness, resolving the scroll
frame and reading the selected day happen **before** `startMeasuring`. The measured block
contains only the gestures, using fixed app-relative coordinates; it does not resolve a
scroll-view query or query the end card for every gesture. It measures
`XCTOSSignpostMetric.scrollingAndDecelerationMetric` and `XCTMemoryMetric`. After
`stopMeasuring`, it asserts day progress and logs the starting/finishing labels. At the
old observed gesture cost this is roughly 122 s for three measured samples, plus setup
(and XCTest may perform a warm-up). This measures lazy scrolling on a 60-day plan without
requiring every iteration to travel its entire height.

`test60DayLastDayReachesEnd` separately launches, opens the real native day picker, selects
its last (index 59) entry, asserts that selection, and reaches `trip.plan.end` in at most
six vertical swipes. Native-menu scrolling is bounded to twelve gestures. These checks
are outside the scrolling measurement. They prove navigation across the full day range
and end-card reachability, not that all intermediate days were physically scrolled through.
The host renderer/cache test still traverses and prepares all 60 days at phone/Duo widths.

| Metric | Hard gate on each reported iteration | Aim |
| --- | ---: | ---: |
| First visible 60-day timeline frame | **≤ 0.8 s** | retain the supplied ~0.53 s |
| Scrolling hitch time ratio | **≤ 5 ms/s (0.5%)** | ≤ 1 ms/s |
| Process physical-memory growth during the 15 gestures | **≤ 40 MiB** over measurement start | stable after initial lazy allocations |
| Vector drawing / actor cache (host tests) | **≤ 512 KiB/drawing; ≤ 4 MiB and four entries** | bounded across all 60 days |

`TimelineBudgetMetric` is shared test-only source in PlanUITests and PerfUITests. It wraps
and copies the real XCTest metric, forwards its lifecycle, reads the actual
`XCTPerformanceMeasurement` values from `reportMeasurements(from:to:)`, and rejects any
sample over its absolute ceiling. Missing metrics, non-finite values and unknown units
also fail; they cannot silently disable a gate. Hitch ratios are normalized to ms/s
(0.5% = 5 ms/s). It checks the unadjusted `.animation.hitch.time.ratio` measurement, not
an adjusted/non-first-frame variant. Physical-memory growth is the delta measurement
`Memory Physical`, not the absolute or peak footprint. This is sampled net growth during
the fixed interval; transient peaks and full-trip process growth still need Instruments.
Budget violations call `XCTFail` while preserving the returned measurements. A host
`XCTExpectFailure` measurement injects 0.81 s and proves that the 0.8 s gate reaches
XCTest as an assertion failure. All raw values are logged as `Timeline metric:` and returned to XCTest for `.xcresult`
reporting. **No Xcode-recorded baseline plist is required.** Host tests exercise boundaries,
unit conversion, missing/bad data, copied delegate lifecycle and over-budget rejection.

The user supplied the following **pre-change** 17e/iOS 27.2 Perf results from
`build/test-results/17e/Perf-compare.log`. The changed UI tests have only been SDK
type-checked here; no simulator was run in this change.

| Result | Supplied run | New run — fill after `make perf-timeline` |
| --- | --- | --- |
| First-frame samples / average / worst | 0.528272, 0.525060, 0.535624 s / **0.530 s** / **0.536 s** | pending |
| AppLaunch average | **2.09 s** | pending |
| Scroll hitch ratio, samples / mean / worst (ms/s) | no completed measurement | pending |
| Scrolling duration, samples / total (s) | timed out after 600 s | pending |
| Physical-memory growth, samples / worst (MiB) | no completed measurement | pending |
| First/final day after each 15-gesture interval | old test did not record progress | pending |
| Last-day selection / end-card reachability | old traversal timed out | pending |
| On-device Instruments (device/OS/settings/results) | not run | pending |

Open the `.xcresult` Performance reports in Xcode and record mean/worst values above.
The runner prints bundle paths under `build/test-results/17e/`; build diagnostics are under
`build/test-results/build/Perf.log`. Search logs for `Timeline metric:`, `Timeline scroll
progress`, `measured` and `time-to-first-timeline-frame`. Compare the same runtime/profile,
appearance and host load. Do not promote the supplied successful first-frame result into
a claim that the new scrolling budgets have passed.

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

## Fix round 1 host verification, 2026-11-08

`make quick` passed strict lint and all package checks except the known sandbox EPERM in
`APICookieTests.realRedirectCookieHandlingIsDisabled`. Host preparation benchmarks remain
unchanged, with every sample inside its original budget (means above). The additional
pixel regression verifies that core-priority tiles differ from recommended tiles only in
the left bar, so the bar's alpha cannot leak into title/interval content. Token/asset tests
and the runner/resource checks skipped by make's package failure were run separately.
New regression suites are classified as host-only. The selector fixture now recognizes the
already registered Perf target and still rejects unknown suites. `PerfUITests/TimelinePerfTests`
is unchanged. No simulator, runtime performance claim or reference recording is included.

## Performance enforcement verification, 2026-11-08

Strict `make lint`, the focused preparation/fixture/invalidation/metric tests, 76 simulator
runner fixtures and 10 launch-resource checks pass. The complete Debug package run has
one failure: the existing sandbox `EPERM` in
`APICookieTests.realRedirectCookieHandlingIsDisabled`. PlanUI/PlanCore tests pass. The
expected-failure metric-reporting test passes and confirms that real XCTest measurements
fail when a budget is exceeded; its intentionally captured failures are not regressions.

An optional optimized **host** run was attempted with `swift test -c release` (and
`-debug-info-format none` to avoid sandbox-restricted dSYM generation). SwiftPM builds
all test targets even with a filter; the unrelated existing
`TripWizardTests/TripGenerationTests.swift:235` references Debug-only `MockAppSeed` and
fails to compile in Release. No Release host timing is claimed. This does not change the
Debug `make quick` gate or the separate iOS Perf target. No xcodebuild, simulator,
all-size snapshot recording or physical-device profiling was run. The simulator SDK
successfully type-checks the changed Perf tests and shared metric adapter.
