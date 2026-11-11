#if DEBUG
    import AppCore
    import Foundation

    extension MemberWizardModel {
        public func freezeBoardCapture(ticks: Int, slow: Bool = false, failure: DataFailure? = nil, retry: Int = 0) {
            guard ProcessInfo.processInfo.environment["CF_WIZARD_BOARD_CAPTURE"] != nil,
                UUID(uuidString: ProcessInfo.processInfo.environment["CF_AUTH_TEST_ID"] ?? "") != nil
            else { return }
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
