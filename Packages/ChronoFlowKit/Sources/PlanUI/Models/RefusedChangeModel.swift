import AppCore
import Observation
import PlanCore
import Sync

@MainActor @Observable public final class RefusedChangeModel {
    public private(set) var refusal: SyncRefusal?
    @ObservationIgnored private var pending: SyncRefusal?

    public init() {}

    public func receive(_ result: SyncResult) {
        if let latest = result.refusals.last(where: { $0.notice != nil }) { pending = latest }
        guard result.state == .idle, result.retryAfter == nil, let pending else { return }
        refusal = pending
        self.pending = nil
    }

    public func text(language: Language) -> String? {
        switch refusal?.notice {
        case .sleepTimes:
            return PlanStrings.text("Couldn't save your sleep times, so we undid the change.", language: language)
        case .stepDone(let type):
            guard let key = stepLabelKey(type) else { return nil }
            return PlanStrings.text(
                "Couldn't save \"{{step}}\" as done, so we undid it.", language: language,
                ["step": PlanStrings.text(key, language: language)])
        case nil: return nil
        }
    }

    public func clear() {
        pending = nil
        refusal = nil
    }
}
