#if DEBUG
    import AppCore
    import Foundation

    extension MemberWizardModel {
        public func freezeCompletionBoard(
            reviewing: Bool = false, answerError: String? = nil, retry: Int = 0, discardConfirmation: Bool = false
        ) {
            boardDiscardConfirmation = discardConfirmation
            boardFrozen = true
            resumed = true
            self.reviewing = reviewing
            boardAnswerError = answerError
            retrySeconds = retry
            draft.state.checkedInput = inputFingerprint
        }

        public func freezeBoardCapture(ticks: Int, slow: Bool = false, failure: DataFailure? = nil, retry: Int = 0) {
            cancelCheck()
            checking.ticks = ticks
            checking.slow = slow
            checking.failure = failure
            retrySeconds = retry
            // Hold the real screen at the board's transient state without starting a request on appearance.
            checkTask = Task {}
        }
    }
#endif
