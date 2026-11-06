#if !DEBUG
    import AppCore
    import Foundation
    import XCTest

    @testable import ChronoFlow

    private actor RecordingSessionStore: SessionStore {
        private(set) var reads = 0
        func read() -> Data? {
            reads += 1
            return Data(#"{"token":"test","accountId":"account"}"#.utf8)
        }
        func write(_ data: Data) {}
        func delete() {}
    }

    nonisolated final class ReleaseReadinessTests: XCTestCase {
        @MainActor
        func testReleaseIgnoresOverridesAndDoesNotReadKeychain() async {
            let parsed = LaunchArguments([
                "-cf.session", "in", "-cf.gate", "verify", "-cf.stored", "never", "-cf.readyDelay", "60",
                "-cf.mode", "slow", "-cf.freezeAt", "700", "-cf.mainThreadStall", "500",
            ])
            XCTAssertEqual(parsed.readiness, .init(session: .signedOut))
            XCTAssertNil(parsed.mode)
            XCTAssertNil(parsed.freezeAt)
            XCTAssertNil(parsed.mainThreadStall)
            let store = RecordingSessionStore()
            let source = StubReadiness(
                configuration: .init(session: .signedIn), store: store, clock: ManualLaunchClock())
            let session = await source.session()
            XCTAssertEqual(session, .signedOut)
            let reads = await store.reads
            XCTAssertEqual(reads, 0)
        }
    }
#endif
