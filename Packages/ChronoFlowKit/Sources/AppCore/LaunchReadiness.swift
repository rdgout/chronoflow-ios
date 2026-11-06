import CoreGraphics
import Foundation

public enum LaunchEnding: Sendable, Equatable { case welcome, app }
public enum SessionPresence: Sendable, Equatable {
    case signedIn(accountID: String)
    case signedOut
}
public enum Gate: String, Sendable, Equatable, CaseIterable {
    case verify, terms, walkthrough, app

    public var route: Route {
        switch self {
        case .verify: .verify
        case .terms: .terms
        case .walkthrough: .walkthrough
        case .app: .today
        }
    }
}

public protocol LaunchReadiness: Sendable {
    func session() async -> SessionPresence
    func gate() async -> Gate
    func gateUpdates() async -> AsyncStream<Gate>
    func hasStoredData() async -> Bool
    func storedDataUpdates() async -> AsyncStream<Bool>
    func allowFirstLoad() async
}

extension LaunchReadiness {
    public func gateUpdates() async -> AsyncStream<Gate> {
        AsyncStream { continuation in
            let task = Task {
                let gate = await gate()
                guard !Task.isCancelled else { return }
                continuation.yield(gate)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func storedDataUpdates() async -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let task = Task {
                let stored = await hasStoredData()
                guard !Task.isCancelled else { return }
                continuation.yield(stored)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

public struct LaunchState: Sendable, Equatable {
    public internal(set) var ending: LaunchEnding?
    public internal(set) var session: SessionPresence?
    public internal(set) var gate: Gate?
    public internal(set) var hasStoredData: Bool?
    public internal(set) var isReady = false
    public internal(set) var showsStatus = false
    public internal(set) var statusStart: Duration?
    public internal(set) var exitStart: Duration?
    public internal(set) var moonTarget: CGRect?
    public internal(set) var now: Duration = .zero
    public internal(set) var didForceReady = false
    public internal(set) var didCommitExit = false
    public internal(set) var isComplete = false
    public let fallbackTarget: CGRect
    public let pendingIntent: PendingLaunchIntent

    public init(fallbackTarget: CGRect = .zero, pendingIntent: PendingLaunchIntent = .init()) {
        self.fallbackTarget = fallbackTarget
        self.pendingIntent = pendingIntent
    }

    public var route: Route? {
        switch session {
        case .signedOut: .welcome
        case .signedIn: (gate ?? (didForceReady ? .app : nil))?.route
        case nil: nil
        }
    }

    public var welcomeDeadline: Duration? {
        ending == .welcome ? exitStart.map { max(.zero, $0 - .milliseconds(50)) } : nil
    }
}

public enum LaunchEvent: Sendable {
    case session(SessionPresence)
    case gate(Gate)
    case storedData(Bool)
    case moonAnchor(CGRect)
    case reached(Duration)
    case exitCompleted
}

public enum LaunchEffect: Sendable, Equatable {
    case commitStatus(at: Duration)
    case cancelStatus
    case commitExit(LaunchEnding, at: Duration, moonTarget: CGRect?)
    case forceReady
}

public func reduce(_ state: inout LaunchState, _ event: LaunchEvent, reduceMotion: Bool) -> [LaunchEffect] {
    guard !state.isComplete else { return [] }
    var effects: [LaunchEffect] = []
    var anchorChanged = false
    switch event {
    case .session(let session):
        if state.session == nil {
            state.session = session
            state.ending = session == .signedOut ? .welcome : .app
            if session == .signedOut {
                state.exitStart = reduceMotion ? state.now : max(.milliseconds(1600), state.now)
            }
        }
    case .gate(let gate):
        if !state.didForceReady { state.gate = gate }
    case .storedData(let stored):
        if !state.didForceReady { state.hasStoredData = stored }
    case .reached(let time): state.now = max(state.now, time)
    case .moonAnchor(let rect):
        if !rect.isInfinite && !rect.isNull && rect.size.width > 0 && rect.size.height > 0,
            [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height].allSatisfy(\.isFinite),
            state.exitStart == nil || state.now < state.exitStart!
        {
            anchorChanged = state.moonTarget != rect
            state.moonTarget = rect
        }
    case .exitCompleted:
        state.isComplete = true
        return []
    }

    if let start = state.statusStart, state.now >= start { state.showsStatus = true }
    if state.now >= .seconds(8) && !state.isReady {
        state.didForceReady = true
        if state.session == nil {
            state.session = .signedOut
            state.ending = .welcome
            state.exitStart = reduceMotion ? state.now : max(.milliseconds(1600), state.now)
        }
        state.isReady = true
        if case .signedIn = state.session { effects.append(.forceReady) }
    }
    state.isReady =
        state.isReady || state.session == .signedOut
        || (state.session != nil && state.gate != nil && (state.gate != .app || state.hasStoredData == true))

    if state.isReady && !state.showsStatus && state.statusStart != nil {
        state.statusStart = nil
        effects.append(.cancelStatus)
    }
    if !state.isReady && state.hasStoredData == false && state.session != nil && state.statusStart == nil {
        let start = max(.seconds(2), state.now)
        state.statusStart = start
        state.showsStatus = state.now >= start
        effects.append(.commitStatus(at: start))
    }

    if state.isReady, let ending = state.ending {
        switch ending {
        case .app:
            if !state.didCommitExit {
                let start = reduceMotion ? state.now : max(.milliseconds(1500), state.now)
                state.exitStart = start
                state.didCommitExit = true
                effects.append(.commitExit(.app, at: start, moonTarget: nil))
            }
        case .welcome:
            let start = state.exitStart!
            let fallbackDue = state.now >= max(.zero, start - .milliseconds(50))
            if !state.didCommitExit || (anchorChanged && state.now < start) {
                if reduceMotion || state.moonTarget != nil || fallbackDue {
                    state.didCommitExit = true
                    effects.append(
                        .commitExit(.welcome, at: start, moonTarget: state.moonTarget ?? state.fallbackTarget))
                }
            }
        }
    }
    return effects
}
