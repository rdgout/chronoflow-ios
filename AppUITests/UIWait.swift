import XCTest

nonisolated struct FrameStability {
    private var previous: [CGRect]?
    private var equalSamples = 0
    let requiredSamples: Int

    init(requiredSamples: Int = 3) {
        precondition(requiredSamples >= 2)
        self.requiredSamples = requiredSamples
    }

    mutating func observe(_ frames: [CGRect]?) -> Bool {
        guard let frames, !frames.isEmpty,
            frames.allSatisfy({ !$0.isEmpty && !$0.isInfinite && !$0.isNull })
        else {
            equalSamples = 0
            previous = nil
            return false
        }
        equalSamples = frames == previous ? equalSamples + 1 : 1
        previous = frames
        return equalSamples >= requiredSamples
    }
}

#if os(iOS)
    @MainActor
    enum UIWait {
        static func stableFrames(_ elements: [XCUIElement], timeout: TimeInterval = 60) throws -> [CGRect] {
            var stability = FrameStability()
            var settled: [CGRect]?
            let predicate = NSPredicate { _, _ in
                do {
                    guard elements.allSatisfy({ $0.exists }) else {
                        _ = stability.observe(nil)
                        return false
                    }
                    let frames = elements.map(\.frame)
                    if stability.observe(frames) {
                        settled = frames
                        return true
                    }
                }
                return false
            }
            let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
            XCTAssertEqual(
                XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, "UI frames did not settle")
            return try XCTUnwrap(settled)
        }

        static func stringValue(of element: XCUIElement, timeout: TimeInterval = 10) throws -> String {
            let predicate = NSPredicate { _, _ in element.exists && element.value is String }
            let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
            XCTAssertEqual(
                XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, "UI measurement did not arrive")
            return try XCTUnwrap(element.value as? String)
        }
    }
#endif
