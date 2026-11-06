import Foundation
import OSLog

@MainActor
public final class LaunchSignposts {
    public enum Interval: String, CaseIterable, Sendable {
        case launch
        case firstCommit = "first-commit"
    }

    public enum Event: String, Sendable {
        case sceneConnect, overlayFirstCommit, rootFirstLayout, overlayRemoved, fontRegistrationFailed
    }

    public private(set) var events: [Event] = []
    public private(set) var activeIntervals: Set<Interval> = []
    private let signposter: OSSignposter
    private var intervals: [Interval: OSSignpostIntervalState] = [:]

    public init() {
        signposter = OSSignposter(subsystem: "net.chronoflow.app.native", category: .pointsOfInterest)
    }

    public func begin(_ interval: Interval) {
        guard activeIntervals.insert(interval).inserted else { return }
        let id = signposter.makeSignpostID()
        switch interval {
        case .launch: intervals[interval] = signposter.beginInterval("launch", id: id)
        case .firstCommit: intervals[interval] = signposter.beginInterval("first-commit", id: id)
        }
    }

    public func end(_ interval: Interval) {
        guard let state = intervals.removeValue(forKey: interval) else { return }
        activeIntervals.remove(interval)
        switch interval {
        case .launch: signposter.endInterval("launch", state)
        case .firstCommit: signposter.endInterval("first-commit", state)
        }
    }

    public func event(_ event: Event) {
        events.append(event)
        switch event {
        case .sceneConnect: signposter.emitEvent("scene-connect")
        case .overlayFirstCommit: signposter.emitEvent("overlay-first-commit")
        case .rootFirstLayout: signposter.emitEvent("root-first-layout")
        case .overlayRemoved: signposter.emitEvent("overlay-removed")
        case .fontRegistrationFailed: signposter.emitEvent("font-registration-failed")
        }
    }
}
