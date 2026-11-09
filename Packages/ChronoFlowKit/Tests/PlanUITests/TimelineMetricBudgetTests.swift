import Testing
import XCTest

nonisolated struct TimelineMetricBudgetTests {
    private func sample(_ id: String, _ value: Double, _ unit: String, name: String = "") -> XCTPerformanceMeasurement {
        XCTPerformanceMeasurement(identifier: id, displayName: name, doubleValue: value, unitSymbol: unit)
    }

    @Test func budgetsRejectRegressionsMissingMetricsAndUnknownUnits() throws {
        let frame = "com.apple.dt.XCTMetric_OSSignpost-time-to-first-timeline-frame.duration"
        let hitch = "com.apple.dt.XCTMetric_OSSignpost-Scrolling.animation.hitch.time.ratio"
        try TimelineBudgetMetric.Budget.firstFrame.validate([sample(frame, 0.8, "s")])
        try TimelineBudgetMetric.Budget.scrollingHitches.validate([sample(hitch, 5, "ms/s")])
        try TimelineBudgetMetric.Budget.scrollingHitches.validate([sample(hitch, 0.5, "%")])
        try TimelineBudgetMetric.Budget.scrollingHitches.validate([sample(hitch, 0.005, "s/s")])
        #expect(throws: (any Error).self) {
            try TimelineBudgetMetric.Budget.firstFrame.validate([sample(frame, 0.801, "s")])
        }
        for value in [5.01, .infinity, .nan, -1] {
            #expect(throws: (any Error).self) {
                try TimelineBudgetMetric.Budget.scrollingHitches.validate([sample(hitch, value, "ms/s")])
            }
        }
        #expect(throws: (any Error).self) { try TimelineBudgetMetric.Budget.scrollingHitches.validate([]) }
        #expect(throws: (any Error).self) {
            try TimelineBudgetMetric.Budget.scrollingHitches.validate([sample(hitch, 0, "unknown")])
        }
        #expect(throws: (any Error).self) {
            try TimelineBudgetMetric.Budget.scrollingHitches.validate([sample(hitch + ".adjusted", 0, "ms/s")])
        }
        let peak = "com.apple.dt.XCTMetric_Memory-net.chronoflow.app.native.physical_peak"
        try TimelineBudgetMetric.Budget.memoryPeak.validate([sample(peak, 150 * 1_024, "KiB")])
        try TimelineBudgetMetric.Budget.memoryPeak.validate([sample(peak, 57_903_624, "byte")])
        #expect(throws: (any Error).self) {
            try TimelineBudgetMetric.Budget.memoryPeak.validate([sample(peak, 151, "MiB")])
        }
        #expect(throws: (any Error).self) {
            try TimelineBudgetMetric.Budget.memoryPeak.validate([
                sample(peak.replacingOccurrences(of: "_peak", with: ""), 1, "MiB")
            ])
        }
    }

    @Test func nanosecondFirstFrameSamplesAreNormalized() throws {
        let frame = "com.apple.dt.XCTMetric_OSSignpost-time-to-first-timeline-frame.duration"
        try TimelineBudgetMetric.Budget.firstFrame.validate([sample(frame, 341_935_417, "ns")])
        #expect(throws: (any Error).self) {
            try TimelineBudgetMetric.Budget.firstFrame.validate([sample(frame, 810_000_000, "ns")])
        }
    }

    @Test func copiedMetricForwardsLifecycleAndReturnsMeasurements() throws {
        let fake = FixtureMetric()
        let metric = TimelineBudgetMetric(fake, budget: .firstFrame)
        let copy = try #require(metric.copy() as? TimelineBudgetMetric)
        #expect(copy !== metric)
        #expect(fake.copies.count == 1)
        let delegate = fake.copies[0]
        copy.willBeginMeasuring()
        copy.didStopMeasuring()
        #expect(delegate.started && delegate.stopped)
        let timestamp = XCTPerformanceMeasurementTimestamp()
        for selector in [
            #selector(FixtureMetric.willBeginMeasuringAtEstimatedTimestamp(_:)),
            #selector(FixtureMetric.didStartMeasuringAtTimestamp(_:)),
            #selector(FixtureMetric.didStopMeasuringAtTimestamp(_:)),
        ] {
            try #require(copy.responds(to: selector))
            copy.perform(selector, with: timestamp)
        }
        #expect(delegate.estimatedStart === timestamp)
        #expect(delegate.measurementStart === timestamp)
        #expect(delegate.measurementStop === timestamp)
        #expect(fake.estimatedStart == nil && fake.measurementStart == nil && fake.measurementStop == nil)
        delegate.samples = [sample("time-to-first-timeline-frame.duration", 0.53, "s")]
        #expect(try copy.reportMeasurements(from: timestamp, to: timestamp).count == 1)
        delegate.samples.append(sample("time-to-first-timeline-frame.duration", 0.81, "s"))
        #expect(throws: (any Error).self) { try TimelineBudgetMetric.Budget.firstFrame.validate(delegate.samples) }
    }
}

nonisolated private final class FixtureMetric: NSObject, XCTMetric {
    var copies: [FixtureMetric] = []
    var started = false
    var stopped = false
    var estimatedStart: XCTPerformanceMeasurementTimestamp?
    var measurementStart: XCTPerformanceMeasurementTimestamp?
    var measurementStop: XCTPerformanceMeasurementTimestamp?
    var prepared = false
    var samples: [XCTPerformanceMeasurement] = []

    // Match built-in metrics so XCTest exercises its timestamped lifecycle.
    override func conforms(to aProtocol: Protocol) -> Bool {
        NSStringFromProtocol(aProtocol) == "XCTMetric_Private" || super.conforms(to: aProtocol)
    }

    func copy(with zone: NSZone? = nil) -> Any {
        let copy = FixtureMetric()
        copy.samples = samples
        copy.prepared = prepared
        copies.append(copy)
        return copy
    }
    func willBeginMeasuring() { started = true }
    func didStopMeasuring() { stopped = true }
    @objc func prepareToMeasureWithOptions(_ options: AnyObject) { prepared = true }
    @objc func willBeginMeasuringAtEstimatedTimestamp(_ timestamp: XCTPerformanceMeasurementTimestamp) {
        estimatedStart = timestamp
    }
    @objc func didStartMeasuringAtTimestamp(_ timestamp: XCTPerformanceMeasurementTimestamp) {
        measurementStart = timestamp
    }
    @objc func didStopMeasuringAtTimestamp(_ timestamp: XCTPerformanceMeasurementTimestamp) {
        measurementStop = timestamp
    }
    func reportMeasurements(
        from startTime: XCTPerformanceMeasurementTimestamp, to endTime: XCTPerformanceMeasurementTimestamp
    ) throws -> [XCTPerformanceMeasurement] { samples }
}

nonisolated final class TimelineMetricReportingTests: XCTestCase {
    func testAutomaticMeasurementForwardsTimestampedLifecycle() { checkLifecycle(manual: false) }
    func testManualMeasurementForwardsTimestampedLifecycle() { checkLifecycle(manual: true) }

    private func checkLifecycle(manual: Bool) {
        let metric = FixtureMetric()
        metric.samples = [
            XCTPerformanceMeasurement(
                identifier: "time-to-first-timeline-frame.duration", displayName: "First frame",
                doubleValue: 0.53, unitSymbol: "s")
        ]
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        if manual { options.invocationOptions = [.manuallyStart, .manuallyStop] }
        measure(metrics: [TimelineBudgetMetric(metric, budget: .firstFrame)], options: options) {
            if manual {
                startMeasuring()
                stopMeasuring()
            }
        }
        XCTAssertFalse(metric.copies.isEmpty)
        for copy in metric.copies {
            XCTAssertTrue(copy.prepared)
            XCTAssertNotNil(copy.estimatedStart)
            XCTAssertNotNil(copy.measurementStart)
            XCTAssertNotNil(copy.measurementStop)
        }
    }

    func testOverBudgetReportFailsTheXCTestMeasurement() {
        let options = XCTExpectedFailure.Options()
        options.issueMatcher = { $0.compactDescription.contains("Timeline budget exceeded") }
        XCTExpectFailure("An over-budget metric must fail the performance test", options: options)
        let metric = FixtureMetric()
        metric.samples = [
            XCTPerformanceMeasurement(
                identifier: "time-to-first-timeline-frame.duration", displayName: "First frame",
                doubleValue: 0.81, unitSymbol: "s")
        ]
        let measureOptions = XCTMeasureOptions()
        measureOptions.iterationCount = 1
        measure(metrics: [TimelineBudgetMetric(metric, budget: .firstFrame)], options: measureOptions) {}
    }
}
