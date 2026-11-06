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

    @Test func coordinatorForcesOnlyItsSourceOnceAndStopCancelsTimers() async {
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
