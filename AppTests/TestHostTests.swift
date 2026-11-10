import SwiftUI
import XCTest

nonisolated final class TestHostTests: XCTestCase {
    override func setUp() {
        super.setUp()
        executionTimeAllowance = 60
    }

    @MainActor func testSettleTimeoutIsRecordedBeforeCleanupErrors() async throws {
        let host = try AuthTestHost(Color.clear, size: CGSize(width: 466, height: 678))
        defer { host.close() }
        var failures: [String] = []
        let options = XCTExpectedFailure.Options()
        options.issueMatcher = { issue in
            let message = issue.compactDescription
            guard message.contains("didNotSettle") || message.contains("cleanupProbe") else { return false }
            failures.append(message)
            return true
        }
        XCTExpectFailure("Exercise timeout reporting followed by a distinct cleanup error", options: options)
        await host.recordFailures {
            try await host.settle("Original settle diagnostic", timeout: .zero) { false }
        }
        enum CleanupFailure: Error { case cleanupProbe }
        await host.recordFailures { throw CleanupFailure.cleanupProbe }
        XCTAssertEqual(failures.count, 2)
        XCTAssertTrue(failures.first?.contains("Original settle diagnostic") == true)
        XCTAssertTrue(failures.last?.contains("cleanupProbe") == true)
    }
}
