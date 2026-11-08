import Observation

@MainActor @Observable public final class WalkthroughModel {
    public enum Mode: Sendable { case firstRun, replay }
    public enum Page: Int, CaseIterable, Sendable {
        case timeline, categories, progress

        public var title: String {
            switch self {
            case .timeline: "Your plan on one timeline"
            case .categories: "Know each step at a glance"
            case .progress: "Tick off what you did"
            }
        }

        public var detail: String {
            switch self {
            case .timeline: "Sleep, light, caffeine and your flights side by side, each at the right local time."
            case .categories:
                "Every kind of step has its own icon and pattern, so you never need colour to tell them apart."
            case .progress:
                "Checking off changes your progress, never your plan. Turn on reminders to get a nudge before each step."
            }
        }
    }

    public let mode: Mode
    public private(set) var page: Page = .timeline
    public private(set) var busy = false
    public private(set) var completed = false
    public private(set) var failure: (any Error)?
    @ObservationIgnored private let complete: @MainActor () async throws -> Void
    @ObservationIgnored private let onFinish: @MainActor () -> Void

    public init(
        mode: Mode = .firstRun, complete: @escaping @MainActor () async throws -> Void,
        onFinish: @escaping @MainActor () -> Void = {}
    ) {
        self.mode = mode
        self.complete = complete
        self.onFinish = onFinish
    }

    public func advance() async {
        guard !busy, !completed else { return }
        if let next = Page(rawValue: page.rawValue + 1) {
            page = next
        } else {
            await skip()
        }
    }

    public func skip() async {
        guard !busy, !completed else { return }
        busy = true
        defer { busy = false }
        do {
            if mode == .firstRun { try await complete() }
            failure = nil
            completed = true
            onFinish()
        } catch {
            failure = error
        }
    }
}
