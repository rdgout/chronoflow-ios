import Foundation

public enum GuestRecoveryGate {
    public enum Decision: Sendable, Equatable { case none, wait, expire, wizard, signIn }

    public static func decision(
        updatedAt: Date?, now: Date, handoffFinished: Bool, introFinished: Bool, signingIn: Bool
    ) -> Decision {
        guard let updatedAt else { return .none }
        guard now.timeIntervalSince(updatedAt) < 30 * 60 else { return .expire }
        guard handoffFinished, introFinished else { return .wait }
        return signingIn ? .signIn : .wizard
    }
}
