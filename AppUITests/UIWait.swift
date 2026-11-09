import XCTest

#if os(iOS)
    @MainActor
    enum UIWait {
        static func stableFrames(_ elements: [XCUIElement], timeout: TimeInterval = 60) throws -> [CGRect] {
            var stability = FrameStability()
            var settled: [CGRect]?
            let predicate = NSPredicate { _, _ in
                guard elements.allSatisfy({ $0.exists }) else {
                    _ = stability.observe(nil)
                    return false
                }
                let frames = elements.map(\.frame)
                if stability.observe(frames) {
                    settled = frames
                    return true
                }
                return false
            }
            let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
            let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
            return try XCTUnwrap(settled, "UI frames did not settle: \(result)")
        }
    }
#endif
