import AppCore
import Foundation
import Testing
import TripWizard

@Suite struct WizardCheckingTests {
    @Test @MainActor func ticksMinimumAndFinalPauseUseInjectedClock() async throws {
        let clock = CheckingTestClock()
        let result = TripGenerationReviewResult(
            input: ApiTripReviewInput(input: try generationInput()), review: try generationReview(), edit: nil)
        var ticks: [Int] = []
        var completed = false
        let task = Task {
            await WizardChecking.run(clock: clock.clock, request: { result }) { event in
                if case .tick(let count) = event { ticks.append(count) }
                if case .complete = event { completed = true }
            }
        }
        try await eventually { clock.waiterCount >= 2 }
        clock.advance(to: 0.399)
        #expect(ticks.isEmpty)
        clock.advance(to: 0.4)
        try await eventually { ticks == [1] }
        clock.advance(to: 0.8)
        try await eventually { ticks == [1, 2] }
        clock.advance(to: 1.199)
        #expect(!completed && ticks == [1, 2])
        clock.advance(to: 1.2)
        try await eventually { ticks == [1, 2, 3] && clock.deadlines.contains(1.5) }
        #expect(!completed)
        clock.advance(to: 1.5)
        await task.value
        #expect(completed)
        #expect(clock.waiterCount == 0)
    }

    @Test @MainActor func slowAtTenSecondsAndTimeoutIsServerFailureAtThirty() async throws {
        let clock = CheckingTestClock()
        var slow = false
        var failure: DataFailure?
        let task = Task {
            await WizardChecking.run(
                clock: clock.clock,
                request: {
                    try await clock.clock.sleepUntil(100)
                    throw DataFailure.offline
                }
            ) { event in
                if case .slow = event { slow = true }
                if case .failed(let value) = event { failure = value }
            }
        }
        try await eventually { clock.waiterCount == 2 }
        clock.advance(to: 9.999)
        try await eventually { clock.deadlines.contains(10) }
        #expect(!slow && failure == nil)
        clock.advance(to: 10)
        try await eventually { slow && clock.deadlines.contains(30) }
        clock.advance(to: 29.999)
        #expect(failure == nil)
        clock.advance(to: 30)
        await task.value
        #expect(failure == .server(status: nil))
        #expect(clock.waiterCount == 0)
    }

    @Test @MainActor func cancellationDropsLateResponseAndTimers() async throws {
        let clock = CheckingTestClock()
        var events = 0
        let task = Task {
            await WizardChecking.run(
                clock: clock.clock,
                request: {
                    try await clock.clock.sleepUntil(100)
                    throw DataFailure.offline
                }
            ) { _ in events += 1 }
        }
        try await eventually { clock.waiterCount == 2 }
        task.cancel()
        await task.value
        clock.advance(to: 100)
        #expect(events == 0 && clock.waiterCount == 0)
    }
}

final class CheckingTestClock: Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var instant = 0.0
    nonisolated(unsafe) private var waiters: [UUID: (Double, CheckedContinuation<Void, any Error>)] = [:]
    nonisolated(unsafe) private var cancelled: Set<UUID> = []
    var now: Double { lock.withLock { instant } }
    var waiterCount: Int { lock.withLock { waiters.count } }
    var deadlines: [Double] { lock.withLock { waiters.values.map(\.0) } }
    var clock: WizardCheckingClock {
        WizardCheckingClock(now: { self.now }, sleepUntil: { try await self.sleep(until: $0) })
    }
    func advance(to value: Double) {
        let ready = lock.withLock {
            instant = value
            let ready = waiters.filter { $0.value.0 <= value }
            for key in ready.keys { waiters[key] = nil }
            return ready.values.map(\.1)
        }
        for waiter in ready { waiter.resume() }
    }
    private func sleep(until deadline: Double) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                lock.withLock {
                    if cancelled.remove(id) != nil || Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else if deadline <= instant {
                        continuation.resume()
                    } else {
                        waiters[id] = (deadline, continuation)
                    }
                }
            }
        } onCancel: {
            let waiter = self.lock.withLock {
                self.cancelled.insert(id)
                return self.waiters.removeValue(forKey: id)?.1
            }
            waiter?.resume(throwing: CancellationError())
        }
    }
}

@MainActor func eventually(_ condition: @MainActor () async -> Bool) async throws {
    for _ in 0..<10000 {
        if await condition() { return }
        await Task.yield()
    }
    try #require(await condition())
}
