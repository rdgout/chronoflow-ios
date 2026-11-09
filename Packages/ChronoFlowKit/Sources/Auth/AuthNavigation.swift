import AppCore
import Observation

nonisolated public enum AuthDestination: Hashable, Sendable {
    case forgot, signUp, twoFactor
}

@MainActor @Observable public final class AuthNavigation {
    public var path: [AuthDestination] = []
    public private(set) var challengeID: String?
    public init() {}
    public func push(_ destination: AuthDestination) { path.append(destination) }
    public func twoFactor(challengeID: String) {
        guard !challengeID.isEmpty else { return }
        self.challengeID = challengeID
        path.append(.twoFactor)
    }
    public func discardChallenge() { challengeID = nil }
    public func reset() {
        path = []
        challengeID = nil
    }

    public static func route(for account: SessionAccount) -> Route {
        if !account.hasVerifiedEmail { return .verify }
        if account.policies.acceptedTermsVersion != account.policies.termsVersion { return .terms }
        if !account.walkthroughSeen { return .walkthrough }
        return .today
    }
}
