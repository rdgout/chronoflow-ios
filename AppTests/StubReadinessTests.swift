import AppCore
import XCTest

@testable import ChronoFlow

nonisolated final class StubReadinessTests: XCTestCase {
    @MainActor
    func testFalseBecomesTrueAtTheSharedLaunchDeadline() async {
        await checkDelayedStream(throughProtocol: false)
    }

    @MainActor
    func testProtocolDispatchUsesTheSameInjectedDeadline() async {
        await checkDelayedStream(throughProtocol: true)
    }

    @MainActor
    private func checkDelayedStream(throughProtocol: Bool) async {
        let registered = expectation(description: "Stub sleeps on the injected clock")
        let clock = ObservedLaunchClock(registered: registered)
        clock.manual.advance(to: .seconds(2))
        let source = StubReadiness(
            configuration: .init(session: .signedIn, stored: .no, readyDelay: .milliseconds(3500)),
            store: KeychainSessionStore(), clock: clock)
        let stream: AsyncStream<Bool>
        if throughProtocol {
            let readiness: any LaunchReadiness = source
            stream = await readiness.storedDataUpdates()
        } else {
            stream = await source.storedDataUpdates()
        }
        let completed = expectation(description: "Both stored-data values arrive and the stream finishes")
        let result = collect(stream, completed: completed)
        defer { result.cancel() }
        await fulfillment(of: [registered], timeout: 2)
        XCTAssertEqual(clock.deadlines, [.milliseconds(3500)])
        XCTAssertEqual(clock.manual.pendingSleeps, 1)
        clock.manual.advance(to: .milliseconds(3499))
        XCTAssertEqual(clock.manual.pendingSleeps, 1)
        clock.manual.advance(to: .milliseconds(3500))
        await fulfillment(of: [completed], timeout: 2)
        result.cancel()
        let values = await result.value
        XCTAssertEqual(values, [false, true])
        XCTAssertEqual(clock.manual.pendingSleeps, 0)
        await source.allowFirstLoad()
        await source.allowFirstLoad()
        let firstLoadCount = await source.firstLoadCount
        XCTAssertEqual(firstLoadCount, 1)
    }

    @MainActor
    func testPassedDeadlineEmitsReadinessWithoutAnotherDelay() async {
        let clock = ManualLaunchClock()
        clock.advance(to: .seconds(4))
        let source = StubReadiness(
            configuration: .init(stored: .no, readyDelay: .milliseconds(3500)),
            store: KeychainSessionStore(), clock: clock)
        let completed = expectation(description: "A passed absolute deadline finishes immediately")
        let result = collect(await source.storedDataUpdates(), completed: completed)
        await fulfillment(of: [completed], timeout: 2)
        result.cancel()
        let values = await result.value
        XCTAssertEqual(values, [false, true])
        XCTAssertEqual(clock.pendingSleeps, 0)
    }

    @MainActor
    func testCancellingTheStreamCancelsItsClockSleep() async {
        let registered = expectation(description: "Delayed stream registers its sleep")
        let cancelled = expectation(description: "Producer returns from its cancelled sleep")
        let clock = ObservedLaunchClock(registered: registered, returned: cancelled)
        let source = StubReadiness(
            configuration: .init(stored: .no, readyDelay: .seconds(8)),
            store: KeychainSessionStore(), clock: clock)
        let completed = expectation(description: "Cancelled consumer finishes")
        let result = collect(await source.storedDataUpdates(), completed: completed)
        await fulfillment(of: [registered], timeout: 2)
        XCTAssertEqual(clock.manual.pendingSleeps, 1)
        result.cancel()
        await fulfillment(of: [completed, cancelled], timeout: 2)
        let values = await result.value
        XCTAssertEqual(values, [false])
        XCTAssertEqual(clock.manual.pendingSleeps, 0)
    }

    nonisolated private func collect(
        _ stream: AsyncStream<Bool>, completed: XCTestExpectation
    ) -> Task<[Bool], Never> {
        Task.detached {
            var values: [Bool] = []
            for await value in stream { values.append(value) }
            completed.fulfill()
            return values
        }
    }

    @MainActor
    func testReadinessArgumentsHaveExplicitUnitsAndRejectInvalidValues() {
        let arguments = LaunchArguments([
            "-cf.session", "in", "-cf.gate", "terms", "-cf.stored", "no", "-cf.readyDelay", "3.5",
        ])
        XCTAssertEqual(
            arguments.readiness,
            .init(
                session: .signedIn, gate: .terms, stored: .no,
                readyDelay: .milliseconds(3500)))
        for invalid in ["-1", "nan", "inf", "61", "wrong"] {
            XCTAssertEqual(LaunchArguments(["-cf.readyDelay", invalid]).readiness.readyDelay, .zero)
        }
        XCTAssertEqual(LaunchArguments(["-cf.session", "never"]).readiness.session, .never)
        XCTAssertEqual(LaunchArguments(["-cf.stored", "never"]).readiness.stored, .never)
        XCTAssertEqual(LaunchArguments(["-cf.session", "out"]).readiness.session, .signedOut)
        XCTAssertEqual(LaunchArguments(["-cf.session", "bad"]).readiness.session, .native)
    }
}

@MainActor
private final class ObservedLaunchClock: LaunchClock {
    let manual = ManualLaunchClock()
    private(set) var deadlines: [Duration] = []
    private let registered: XCTestExpectation
    private let returned: XCTestExpectation?

    init(registered: XCTestExpectation, returned: XCTestExpectation? = nil) {
        self.registered = registered
        self.returned = returned
    }

    var now: Duration { manual.now }

    func sleep(until deadline: Duration) async throws {
        deadlines.append(deadline)
        registered.fulfill()
        defer { returned?.fulfill() }
        try await manual.sleep(until: deadline)
    }
}
