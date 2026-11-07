import AppCore
import Foundation
import Observation

nonisolated public enum AuthDestination: Hashable, Sendable {
    case forgot, signUp, twoFactor
}

@MainActor @Observable public final class AuthNavigation {
    public var path: [AuthDestination] = []
    public private(set) var challengeID: String?
    public private(set) var forgotEmail = ""
    public init() {}
    public func push(_ destination: AuthDestination) { path.append(destination) }
    public func forgot(email: String = "") {
        forgotEmail = email
        path.append(.forgot)
    }
    public func twoFactor(challengeID: String) {
        guard !challengeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            cancelTwoFactor()
            return
        }
        self.challengeID = challengeID
        path.append(.twoFactor)
    }
    public func discardChallenge() { challengeID = nil }
    public func cancelTwoFactor() {
        challengeID = nil
        if let index = path.firstIndex(of: .twoFactor) { path.removeSubrange(index...) }
    }
    public func reset() {
        path = []
        challengeID = nil
        forgotEmail = ""
    }

    public static func route(for account: SessionAccount) -> Route {
        if !account.hasVerifiedEmail { return .verify }
        if account.policies.acceptedTermsVersion != account.policies.termsVersion { return .terms }
        if !account.walkthroughSeen { return .walkthrough }
        return .today
    }
}
