import XCTest

nonisolated final class TimelineBudgetMetric: NSObject, XCTMetric {
    enum Budget {
        case firstFrame, scrollingHitches, memoryGrowth

        var limit: Double {
            switch self {
            case .firstFrame: 0.8
            case .scrollingHitches: 5
            case .memoryGrowth: 40 * 1_024 * 1_024
            }
        }

        func matches(_ sample: XCTPerformanceMeasurement) -> Bool {
            switch self {
            case .firstFrame: sample.identifier.hasSuffix("time-to-first-timeline-frame.duration")
            case .scrollingHitches: sample.identifier.hasSuffix(".animation.hitch.time.ratio")
            case .memoryGrowth: sample.displayName.hasPrefix("Memory Physical")
            }
        }

        func normalized(_ sample: XCTPerformanceMeasurement) throws -> Double {
            let value = sample.doubleValue
            switch (self, sample.unitSymbol) {
            case (.firstFrame, "s"): return value
            case (.firstFrame, "ms"): return value / 1_000
            case (.scrollingHitches, "ms/s"): return value
            case (.scrollingHitches, "%"): return value * 10
            case (.scrollingHitches, "s/s"): return value * 1_000
            case (.memoryGrowth, "B"): return value
            case (.memoryGrowth, "kB"): return value * 1_000
            case (.memoryGrowth, "KiB"): return value * 1_024
            case (.memoryGrowth, "MB"): return value * 1_000_000
            case (.memoryGrowth, "MiB"): return value * 1_024 * 1_024
            default: throw Failure.unsupportedUnit(sample.identifier, sample.unitSymbol)
            }
        }

        func validate(_ samples: [XCTPerformanceMeasurement]) throws {
            let matched = samples.filter(matches)
            guard !matched.isEmpty else { throw Failure.missingMeasurement(String(describing: self)) }
            for sample in matched {
                let value = try normalized(sample)
                guard value.isFinite, value <= limit, self == .memoryGrowth || value >= 0 else {
                    throw Failure.overBudget(sample.identifier, value, limit)
                }
            }
        }
    }

    enum Failure: Error, LocalizedError {
        case missingMeasurement(String)
        case unsupportedUnit(String, String)
        case overBudget(String, Double, Double)

        var errorDescription: String? {
            switch self {
            case .missingMeasurement(let budget): "Timeline budget requires a measurement: \(budget)"
            case .unsupportedUnit(let id, let unit): "Timeline budget cannot normalize \(id) unit \(unit)"
            case .overBudget(let id, let value, let limit): "Timeline budget exceeded: \(id) = \(value), limit \(limit)"
            }
        }
    }

    private let metric: any XCTMetric
    private let budget: Budget

    init(_ metric: any XCTMetric, budget: Budget) {
        self.metric = metric
        self.budget = budget
    }

    func copy(with zone: NSZone? = nil) -> Any {
        TimelineBudgetMetric(metric.copy(with: zone) as! any XCTMetric, budget: budget)
    }

    func willBeginMeasuring() { metric.willBeginMeasuring?() }
    func didStopMeasuring() { metric.didStopMeasuring?() }

    // XCTest gates its timestamped lifecycle on a private protocol implemented by the wrapped metric.
    override func conforms(to aProtocol: Protocol) -> Bool {
        super.conforms(to: aProtocol) || metric.conforms(to: aProtocol)
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || metric.responds(to: selector)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        metric.responds(to: selector) ? metric : super.forwardingTarget(for: selector)
    }

    func reportMeasurements(
        from startTime: XCTPerformanceMeasurementTimestamp, to endTime: XCTPerformanceMeasurementTimestamp
    ) throws -> [XCTPerformanceMeasurement] {
        let samples = try metric.reportMeasurements(from: startTime, to: endTime)
        for sample in samples {
            print("Timeline metric: \(sample.identifier) = \(sample.doubleValue) \(sample.unitSymbol)")
        }
        do { try budget.validate(samples) } catch { XCTFail(error.localizedDescription) }
        return samples
    }
}
