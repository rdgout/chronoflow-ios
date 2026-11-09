import XCTest

@testable import ChronoFlow

nonisolated final class AppTabsSnapshotTests: XCTestCase {
    enum State: String { case tabs }
    @MainActor func testSystemTabs() async throws {
        try await planSnapshots("Tabs", states: [State.tabs]) { _ in AppTabs() }
    }
}
