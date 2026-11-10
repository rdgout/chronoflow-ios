public enum GuestSignupState: String, Sendable, Equatable {
    case ready, failed, retry, review

    public var title: String? {
        switch self {
        case .ready: nil
        case .failed: "We couldn't create your account."
        case .retry: "Your account is ready."
        case .review: "Your trip needs a new check."
        }
    }

    public var message: String? {
        switch self {
        case .ready: nil
        case .failed: "Try again in a moment."
        case .retry: "Try saving again shortly."
        case .review: "Review your trip again before creating your account."
        }
    }
}
