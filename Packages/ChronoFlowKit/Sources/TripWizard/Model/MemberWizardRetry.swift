import Foundation

extension MemberWizardModel {
    func updateRetrySeconds() {
        guard !closed else {
            retrySeconds = 0
            return
        }
        switch draft.state.step {
        case .checking where checking.failure != nil:
            retrySeconds = checking.retrySeconds(at: checkingClock.now())
            if retrySeconds == 0 { checking.retryAt = nil }
        case .ready:
            retrySeconds = draft.state.saveFailure?.seconds(at: now()) ?? 0
            if retrySeconds == 0 { draft.state.saveFailure?.retryAt = nil }
        default: retrySeconds = 0
        }
    }

    private var retryDelay: TimeInterval {
        switch draft.state.step {
        case .checking: min(1, max(0, (checking.retryAt ?? checkingClock.now()) - checkingClock.now()))
        case .ready: min(1, max(0, draft.state.saveFailure?.retryAt?.timeIntervalSince(now()) ?? 0))
        default: 0
        }
    }

    func restartRetryCountdown() {
        retryTask?.cancel()
        retryTask = nil
        let id = UUID()
        retryID = id
        updateRetrySeconds()
        guard retrySeconds > 0 else { return }
        retryTask = Task { [weak self, checkingClock] in
            while !Task.isCancelled {
                let delay = self?.retryDelay ?? 0
                if delay > 0 {
                    do { try await checkingClock.sleepUntil(checkingClock.now() + delay) } catch { return }
                }
                guard let self, self.retryID == id, !Task.isCancelled else { return }
                self.updateRetrySeconds()
                if self.retrySeconds == 0 {
                    self.retryTask = nil
                    return
                }
            }
        }
    }
}
