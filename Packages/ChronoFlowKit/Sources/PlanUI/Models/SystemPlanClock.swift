import Foundation
import PlanCore

#if canImport(UIKit)
    import UIKit
#endif

public struct SystemPlanClock: PlanClock {
    public nonisolated init() {}

    public nonisolated func values() async -> AsyncStream<Date> {
        let (stream, continuation) = AsyncStream<Date>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let driver = MinuteClockDriver(continuation)
        let observers = ClockObservers(driver: driver)
        continuation.onTermination = { _ in
            observers.remove()
            Task { await driver.stop() }
        }
        await driver.refresh()
        return stream
    }
}

private actor MinuteClockDriver {
    let continuation: AsyncStream<Date>.Continuation
    var timer: Task<Void, Never>?
    var stopped = false
    init(_ continuation: AsyncStream<Date>.Continuation) { self.continuation = continuation }

    func refresh() {
        guard !stopped else { return }
        timer?.cancel()
        let now = Date()
        continuation.yield(now)
        let remainder = now.timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
        timer = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(60 - remainder)) } catch { return }
            await self?.refresh()
        }
    }

    func stop() {
        stopped = true
        timer?.cancel()
        timer = nil
    }
}

private nonisolated final class ClockObservers: @unchecked Sendable {
    let tokens: [any NSObjectProtocol]

    init(driver: MinuteClockDriver) {
        var names = [Notification.Name.NSSystemTimeZoneDidChange, Notification.Name.NSCalendarDayChanged]
        #if canImport(UIKit)
            names += [UIApplication.willEnterForegroundNotification, UIApplication.significantTimeChangeNotification]
        #endif
        tokens = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in
                Task { await driver.refresh() }
            }
        }
    }

    func remove() { for token in tokens { NotificationCenter.default.removeObserver(token) } }
}
