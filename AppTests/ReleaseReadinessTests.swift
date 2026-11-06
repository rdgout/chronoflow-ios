#if !DEBUG
    import AppCore
    import Foundation
    import Launch
    import UIKit
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
        func testReleaseKeepsOnlyReadyPlaybackAndStallDiagnostics() {
            let parsed = LaunchArguments([
                "-cf.mode", "ready", "-cf.mainThreadStall", "500", "-cf.freezeAt", "700", "-cf.readyAt", "9000",
                "-cf.session", "in", "-cf.gate", "verify", "-cf.stored", "never", "-cf.readyDelay", "60",
            ])
            XCTAssertEqual(parsed.mode, .ready)
            XCTAssertEqual(parsed.mainThreadStall, .milliseconds(500))
            XCTAssertNil(parsed.freezeAt)
            XCTAssertEqual(parsed.readyAt, .milliseconds(4600))
            XCTAssertEqual(parsed.readiness, .init(session: .signedOut))
            let opening = LaunchTimeline.opening(size: UIScreen.main.bounds.size, reduceMotion: false)
            XCTAssertEqual(
                parsed.timeline(opening: opening, safeAreaInsets: .init(top: 0, left: 0, bottom: 0, right: 0)),
                opening.withReadyExit(at: .milliseconds(1500)))
            for mode in ["slow", "welcome", "unknown", ""] {
                XCTAssertNil(LaunchArguments(["-cf.mode", mode]).mode)
            }
            XCTAssertNil(LaunchArguments([]).mode)
            XCTAssertNil(LaunchArguments([]).mainThreadStall)
            for value in ["nan", "inf", "-1", "60001", "invalid"] {
                XCTAssertNil(LaunchArguments(["-cf.mainThreadStall", value]).mainThreadStall)
            }
            for value in [0, 500, 60000] {
                XCTAssertEqual(
                    LaunchArguments(["-cf.mainThreadStall", String(value)]).mainThreadStall, .milliseconds(value))
            }
        }

        @MainActor
        func testReleaseIgnoresReadinessOverridesAndDoesNotReadKeychain() async {
            let parsed = LaunchArguments([
                "-cf.session", "in", "-cf.gate", "verify", "-cf.stored", "never", "-cf.readyDelay", "60",
                "-cf.mode", "slow", "-cf.freezeAt", "700", "-cf.mainThreadStall", "500",
            ])
            XCTAssertEqual(parsed.readiness, .init(session: .signedOut))
            XCTAssertNil(parsed.mode)
            XCTAssertNil(parsed.freezeAt)
            XCTAssertEqual(parsed.mainThreadStall, .milliseconds(500))
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
