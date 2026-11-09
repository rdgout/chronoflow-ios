import AppCore
import Auth
import DataAccess
import Foundation
import Testing

extension VerifyEmailModelTests {
    private var account: String { "0199a3c0-0000-7000-8000-000000000001" }
    private var other: String { "0199a3c0-0000-7000-8000-000000000002" }

    private func link(_ id: String) -> SignedVerificationInput {
        SignedVerificationInput(id: id, hash: "hash", expires: 1_800_000_000, signature: "signature")
    }
    private func context(_ id: String, epoch: UInt64) -> VerificationContext {
        VerificationContext(accountID: id, email: "demo@example.com", epoch: epoch)
    }

    @Test func guestLinkIsConsumedOnceByTheMatchingFirstSignIn() {
        let inbox = VerificationLinkInbox()
        inbox.sessionChanged(presence: .signedOut, epoch: 1)
        let input = link(account.uppercased())
        #expect(inbox.receive(input))
        #expect(inbox.take(for: context(account, epoch: 1)) == nil)
        inbox.sessionChanged(presence: .signedIn(accountID: account), epoch: 2)
        #expect(inbox.take(for: context(account, epoch: 1)) == nil)
        #expect(inbox.take(for: context(account, epoch: 2)) == input)
        #expect(inbox.take(for: context(account, epoch: 2)) == nil)
    }

    @Test func foreignFirstSignInDropsTheLinkAndCannotApplyItLater() {
        let inbox = VerificationLinkInbox()
        inbox.sessionChanged(presence: .signedOut, epoch: 1)
        inbox.receive(link(account))
        inbox.sessionChanged(presence: .signedIn(accountID: other), epoch: 2)
        #expect(inbox.pending == nil)
        #expect(inbox.take(for: context(other, epoch: 2)) == nil)
        inbox.sessionChanged(presence: .signedIn(accountID: account), epoch: 3)
        #expect(inbox.take(for: context(account, epoch: 3)) == nil)
    }

    @Test func verifiedSignInAndRepeatedOldLinksHaveNoVerificationDestination() {
        let inbox = VerificationLinkInbox()
        inbox.sessionChanged(presence: .signedOut, epoch: 1)
        inbox.receive(link(account))
        inbox.sessionChanged(presence: .signedIn(accountID: account), epoch: 2, hasVerifiedEmail: true)
        #expect(inbox.pending == nil)
        #expect(!inbox.receive(link(account)))
        #expect(inbox.take(for: context(account, epoch: 2)) == nil)
        inbox.sessionChanged(presence: .signedOut, epoch: 3)
        inbox.sessionChanged(presence: .signedIn(accountID: other), epoch: 4)
        #expect(inbox.take(for: context(other, epoch: 4)) == nil)
    }

    @Test func signOutAndSessionReplacementClearPendingInput() {
        for next in [SessionPresence.signedOut, .signedIn(accountID: account), .signedIn(accountID: other)] {
            let inbox = VerificationLinkInbox()
            inbox.sessionChanged(presence: .signedIn(accountID: account), epoch: 5)
            inbox.receive(link(account))
            inbox.sessionChanged(presence: next, epoch: 6)
            #expect(inbox.pending == nil)
        }
        let inbox = VerificationLinkInbox()
        inbox.sessionChanged(presence: .signedOut, epoch: 1)
        inbox.receive(link(account))
        inbox.sessionChanged(presence: .signedOut, epoch: 2)
        #expect(inbox.pending == nil)
    }

    @Test func coalescedUpdatesCannotCarryGuestInputAcrossAMissedSignOut() {
        let inbox = VerificationLinkInbox()
        inbox.sessionChanged(presence: .signedOut, epoch: 1)
        inbox.receive(link(account))
        inbox.sessionChanged(presence: .signedIn(accountID: account), epoch: 4)
        #expect(inbox.pending == nil)
        #expect(inbox.take(for: context(account, epoch: 4)) == nil)
        inbox.sessionChanged(presence: .signedOut, epoch: 2)
        #expect(inbox.receive(link(account)))
        #expect(inbox.take(for: context(account, epoch: 4)) == link(account))
    }

    @Test func liveForeignAndMalformedInputsDoNotReplaceAMatchingPendingLink() {
        let inbox = VerificationLinkInbox()
        inbox.sessionChanged(presence: .signedIn(accountID: account), epoch: 1)
        #expect(inbox.receive(link(account)))
        #expect(!inbox.receive(link(other)))
        #expect(!inbox.receive(nil))
        #expect(inbox.take(for: context(account, epoch: 1)) == link(account))
    }

    @Test func foreignGuestLinkLeavesTheNewAccountsFirstVerifyScreenWaiting() async throws {
        let source = try authTestSource(verified: false)
        guard
            case .session(let accepted) = try await source.signIn(
                PasswordSignInInput(
                    email: "demo@example.com", password: "Password123!", deviceID: account, deviceName: "test"))
        else { throw DataFailure.server(status: nil) }
        let context = context(accepted.account.id, epoch: 2)
        let inbox = VerificationLinkInbox()
        inbox.sessionChanged(presence: .signedOut, epoch: 1)
        inbox.receive(link(other))
        inbox.sessionChanged(presence: .signedIn(accountID: context.accountID), epoch: context.epoch)
        let model = VerifyEmailModel(
            context: context, source: source, current: { context },
            persist: { _ in
                Issue.record("Foreign link persisted")
                return false
            }, route: { Issue.record("Foreign link routed") }, discard: {})
        if let input = inbox.take(for: context) { model.receiveLink(input) }
        await model.activate()
        #expect(model.state == .waiting && model.hasStatus)
        #expect(try await !source.fetchIdentity().hasVerifiedEmail)
    }
}
