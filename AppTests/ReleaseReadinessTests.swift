#if !DEBUG
    import AppCore
    import DataAccess
    import Foundation
    import Launch
    import UIKit
    import XCTest

    @testable import ChronoFlow

    private actor RecordingSessionStore: SessionStore {
        private(set) var reads = 0
        func read() -> Data? {
            reads += 1
            return Data(#"{"token":"test","accountId":"019a562b-8000-7000-8000-000000000001"}"#.utf8)
        }
        func write(_ data: Data) {}
        func delete() {}
    }

    private actor ReleaseSessionAccounts: SessionAccountStore {
        func open(accountID: AccountID) { XCTAssertFalse(Thread.isMainThread) }
        func upsert(_ account: SessionAccount) {}
        func close() {}
    }

    nonisolated final class ReleaseReadinessTests: XCTestCase {
        func testReleaseDefaultMockDoesNotSeedAccounts() async throws {
            let store = MemoryMockStateStore()
            let source = MockDataSource(store: store, sleep: { _ in })
            _ = try await source.inbox()
            XCTAssertTrue(store.load()?.accounts.isEmpty ?? true)
            let session = try await source.signUp(
                RegisterInput(
                    name: "Release test", email: "release@example.test", password: "ReleasePassword12!",
                    passwordConfirmation: "ReleasePassword12!", deviceID: UUID().uuidString, deviceName: "iPhone"))
            let accounts = try XCTUnwrap(store.load()?.accounts)
            XCTAssertEqual(Set(accounts.keys), [session.account.id])
        }

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
            XCTAssertEqual(parsed.readiness, .init())
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
        func testReleaseIgnoresArgumentsRestoresNativeSessionAndKeepsPerfIsolated() async {
            let parsed = LaunchArguments([
                "-cf.session", "in", "-cf.gate", "verify", "-cf.stored", "never", "-cf.readyDelay", "60",
                "-cf.mode", "slow", "-cf.freezeAt", "700", "-cf.mainThreadStall", "500",
            ])
            XCTAssertEqual(parsed.readiness, .init())
            XCTAssertNil(parsed.mode)
            XCTAssertNil(parsed.freezeAt)
            XCTAssertEqual(parsed.mainThreadStall, .milliseconds(500))
            let store = RecordingSessionStore()
            let accounts = ReleaseSessionAccounts()
            let controller = SessionController(credentials: store, accounts: accounts)
            let source = StoredDataReadiness(
                controller: controller, values: { _ in AsyncThrowingStream { $0.finish() } })
            let session = await source.session()
            XCTAssertEqual(session, .signedIn(accountID: "019a562b-8000-7000-8000-000000000001"))
            let reads = await store.reads
            XCTAssertEqual(reads, 1)
            XCTAssertFalse(parsed.usesInjectedReadiness)
            XCTAssertFalse(try! AppServices(info: ["CHRONOFLOW_READINESS": "native"], testing: true).signedOutReadiness)
            XCTAssertTrue(
                try! AppServices(info: ["CHRONOFLOW_READINESS": "signed-out"], testing: true).signedOutReadiness)
            let perf = SignedOutReadiness()
            XCTAssertEqual(perf.session(), .signedOut)
            let after = await store.reads
            XCTAssertEqual(after, 1)
            XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CHRONOFLOW_READINESS") as? String, "native")
        }
    }
#endif
