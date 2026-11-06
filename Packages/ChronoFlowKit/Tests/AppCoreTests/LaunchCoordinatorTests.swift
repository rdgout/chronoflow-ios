import Foundation
import Testing

@testable import AppCore

private actor TestReadiness: LaunchReadiness {
    let presence: SessionPresence
    let stored: Bool
    private(set) var forced = 0
    init(_ presence: SessionPresence = .signedIn(accountID: "a"), stored: Bool = false) {
        self.presence = presence
        self.stored = stored
    }
    func session() -> SessionPresence { presence }
    func gate() -> Gate { .app }
    func hasStoredData() -> Bool { stored }
    func allowFirstLoad() { forced += 1 }
}

private struct UpdatingReadiness: LaunchReadiness {
    let clock: any LaunchClock
    func session() async -> SessionPresence { .signedIn(accountID: "a") }
    func gate() async -> Gate { .app }
    func hasStoredData() async -> Bool { false }
    func allowFirstLoad() async {}
    func storedDataUpdates() async -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let task = Task {
                continuation.yield(false)
                do { try await clock.sleep(until: .milliseconds(3500)) } catch { return }
                continuation.yield(true)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private actor SuspendedSessionReadiness: LaunchReadiness {
    private(set) var waiting = false
    private(set) var cancelled = false

    func session() async -> SessionPresence {
        waiting = true
        do {
            while true { try await Task.sleep(for: .seconds(3600)) }
        } catch {
            cancelled = Task.isCancelled
        }
        return .signedOut
    }

    func gate() -> Gate { .app }
    func hasStoredData() -> Bool { false }
    func allowFirstLoad() { Issue.record("Stopped coordinator forced readiness") }
}

@MainActor
struct LaunchCoordinatorTests {
    @Test func manualClockResumesAtDeadlinesAndCancelsSleep() async throws {
        let clock = ManualLaunchClock()
        let early = Task { try await clock.sleep(until: .seconds(2)) }
        let late = Task { try await clock.sleep(until: .seconds(8)) }
        while clock.pendingSleeps != 2 { await Task.yield() }
        clock.advance(to: .seconds(2))
        try await early.value
        #expect(clock.pendingSleeps == 1)
        late.cancel()
        do {
            try await late.value
            Issue.record("Cancelled sleep returned")
        } catch is CancellationError {} catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(clock.pendingSleeps == 0)
    }

    @Test func coordinatorForcesOnlyItsSourceOnce() async {
        let clock = ManualLaunchClock()
        let source = TestReadiness()
        var exits = 0
        let coordinator = LaunchCoordinator(readiness: source, clock: clock, reduceMotion: false) { _, effects in
            exits += effects.filter { if case .commitExit = $0 { true } else { false } }.count
        }
        coordinator.start()
        coordinator.start()
        for _ in 0..<200 where coordinator.state.hasStoredData == nil { await Task.yield() }
        #expect(coordinator.state.hasStoredData == false)
        clock.advance(to: .seconds(8))
        for _ in 0..<200 where await source.forced == 0 { await Task.yield() }
        #expect(await source.forced == 1)
        #expect(exits == 1)
        coordinator.send(.reached(.seconds(9)))
        #expect(await source.forced == 1)
        coordinator.stop()
        for _ in 0..<200 where clock.pendingSleeps > 0 { await Task.yield() }
        #expect(clock.pendingSleeps == 0)
    }

    @Test(arguments: [false, true])
    func stopCancelsPendingTimersBeforeAnyDeadline(signedOut: Bool) async throws {
        let clock = ManualLaunchClock()
        var changes = 0
        let coordinator = LaunchCoordinator(
            readiness: TestReadiness(signedOut ? .signedOut : .signedIn(accountID: "a")),
            clock: clock, reduceMotion: false
        ) { _, _ in changes += 1 }
        defer { coordinator.stop() }
        coordinator.start()
        let expectedSleeps = signedOut ? 3 : 2
        for _ in 0..<2000 where clock.pendingSleeps != expectedSleeps || coordinator.state.session == nil {
            await Task.yield()
        }
        try #require(coordinator.state.session != nil)
        try #require(clock.pendingSleeps == expectedSleeps)
        #expect(clock.now == .zero)
        coordinator.stop()
        let changesAtStop = changes
        let stateAtStop = coordinator.state
        for _ in 0..<2000 where clock.pendingSleeps != 0 { await Task.yield() }
        try #require(clock.pendingSleeps == 0)
        clock.advance(to: .seconds(8))
        for _ in 0..<200 { await Task.yield() }
        #expect(changes == changesAtStop)
        #expect(coordinator.state == stateAtStop)
    }

    @Test func stopCancelsAnUnresolvedSessionTask() async throws {
        let clock = ManualLaunchClock()
        let source = SuspendedSessionReadiness()
        var changes = 0
        let coordinator = LaunchCoordinator(readiness: source, clock: clock, reduceMotion: false) { _, _ in
            changes += 1
        }
        defer { coordinator.stop() }
        coordinator.start()
        for _ in 0..<2000 where !(await source.waiting) || clock.pendingSleeps != 2 { await Task.yield() }
        try #require(await source.waiting)
        try #require(clock.pendingSleeps == 2)
        #expect(coordinator.state.session == nil)
        coordinator.stop()
        for _ in 0..<2000 where !(await source.cancelled) || clock.pendingSleeps != 0 { await Task.yield() }
        try #require(await source.cancelled)
        try #require(clock.pendingSleeps == 0)
        clock.advance(to: .seconds(8))
        for _ in 0..<200 { await Task.yield() }
        #expect(changes == 0)
        #expect(coordinator.state.session == nil)
    }

    @Test func signedOutUsesFallbackAtDeadlineAndFinishesOnce() async {
        let clock = ManualLaunchClock()
        let target = CGRect(x: 55, y: 76, width: 28, height: 28)
        var effects: [LaunchEffect] = []
        let coordinator = LaunchCoordinator(
            readiness: TestReadiness(.signedOut), clock: clock, reduceMotion: false,
            state: .init(fallbackTarget: target)
        ) { _, emitted in effects += emitted }
        coordinator.start()
        for _ in 0..<200 where coordinator.state.session == nil { await Task.yield() }
        #expect(coordinator.state.isReady)
        #expect(effects.isEmpty)
        for _ in 0..<200 where clock.pendingSleeps < 3 { await Task.yield() }
        clock.advance(to: .milliseconds(1550))
        for _ in 0..<200 where effects.isEmpty { await Task.yield() }
        #expect(effects == [.commitExit(.welcome, at: .milliseconds(1600), moonTarget: target)])
        coordinator.send(.exitCompleted)
        coordinator.stop()
        let complete = coordinator.state
        coordinator.send(.session(.signedIn(accountID: "later")))
        #expect(coordinator.state == complete)
    }

    @Test func storedDataStreamHandsOffAtReadinessBeforeTimeout() async {
        let clock = ManualLaunchClock()
        var effects: [LaunchEffect] = []
        let coordinator = LaunchCoordinator(
            readiness: UpdatingReadiness(clock: clock), clock: clock,
            reduceMotion: false
        ) { _, emitted in effects += emitted }
        coordinator.start()
        for _ in 0..<500 where coordinator.state.hasStoredData == nil { await Task.yield() }
        #expect(coordinator.state.hasStoredData == false)
        #expect(effects == [.commitStatus(at: .seconds(2))])
        clock.advance(to: .seconds(2))
        for _ in 0..<500 where !coordinator.state.showsStatus { await Task.yield() }
        #expect(coordinator.state.showsStatus)
        clock.advance(to: .milliseconds(3500))
        for _ in 0..<500 where !coordinator.state.didCommitExit { await Task.yield() }
        #expect(coordinator.state.exitStart == .milliseconds(3500))
        #expect(
            effects == [
                .commitStatus(at: .seconds(2)),
                .commitExit(.app, at: .milliseconds(3500), moonTarget: nil),
            ])
        #expect(!coordinator.state.didForceReady)
        coordinator.stop()
    }

    @Test func mediaClockUsesPassedCommitEpoch() {
        let uptime = ProcessInfo.processInfo.systemUptime
        let clock = MediaLaunchClock(t0: uptime - 0.5)
        #expect(clock.now >= .milliseconds(500))
        #expect(clock.now < .seconds(2))
    }
}
