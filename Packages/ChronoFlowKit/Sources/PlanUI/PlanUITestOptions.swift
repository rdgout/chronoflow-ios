#if DEBUG
    import SwiftUI

    public struct PlanUITestOptions: Sendable {
        public var largeStepSheet: Bool
        public var startAtSummary: Bool
        public var refreshCounter: Bool

        public init(largeStepSheet: Bool = false, startAtSummary: Bool = false, refreshCounter: Bool = false) {
            self.largeStepSheet = largeStepSheet
            self.startAtSummary = startAtSummary
            self.refreshCounter = refreshCounter
        }
    }

    private struct PlanUITestOptionsKey: EnvironmentKey {
        static let defaultValue = PlanUITestOptions()
    }

    extension EnvironmentValues {
        public var planUITestOptions: PlanUITestOptions {
            get { self[PlanUITestOptionsKey.self] }
            set { self[PlanUITestOptionsKey.self] = newValue }
        }
    }
#endif
