import AppCore

@MainActor public final class VerificationLinkInbox {
    public private(set) var pending: SignedVerificationInput?
    private var presence: SessionPresence?
    private var epoch: UInt64?
    private var verified = false

    public init() {}

    public func sessionChanged(presence: SessionPresence, epoch: UInt64, hasVerifiedEmail: Bool = false) {
        if let previous = self.epoch {
            guard epoch >= previous else { return }
            if epoch != previous {
                let firstGuestSignIn: Bool
                if case .signedIn = presence {
                    firstGuestSignIn = self.presence == .signedOut && epoch == previous + 1
                } else {
                    firstGuestSignIn = false
                }
                if !firstGuestSignIn { pending = nil }
            }
        }
        self.presence = presence
        self.epoch = epoch
        verified = hasVerifiedEmail
        if verified { pending = nil }
        if case .signedIn(let id) = presence, let pending, !matches(pending.id, id) {
            self.pending = nil
        }
    }

    @discardableResult public func receive(_ input: SignedVerificationInput?) -> Bool {
        guard let input, !verified else { return false }
        if case .signedIn(let id) = presence, !matches(input.id, id) { return false }
        pending = input
        return true
    }

    public func take(for context: VerificationContext) -> SignedVerificationInput? {
        guard !verified, context.epoch == epoch,
            presence == .signedIn(accountID: context.accountID), let pending,
            matches(pending.id, context.accountID)
        else { return nil }
        self.pending = nil
        return pending
    }

    private func matches(_ first: String, _ second: String) -> Bool {
        guard let first = try? AccountID(first), let second = try? AccountID(second) else { return false }
        return first == second
    }
}
