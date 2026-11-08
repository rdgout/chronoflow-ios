import AppCore
import Auth
import Foundation
import Testing

extension ResetPasswordModelTests {
    private var link: ResetPasswordLink { ResetPasswordLink(token: "reset-token", email: "demo@example.com") }

    @Test(.timeLimit(.minutes(1))) func unresolvedLaunchWaitsForSignedOutRestore() async throws {
        let session = makeSession()
        let (opened, continuation) = AsyncStream<ResetPasswordLink>.makeStream()
        var iterator = opened.makeAsyncIterator()
        let router = GuestResetLinkRouter(session: session) { continuation.yield($0) }
        await router.receive(link)
        #expect(router.pending == link)
        _ = try await session.restore()
        #expect(await iterator.next() == link)
        #expect(router.pending == nil)
        continuation.finish()
        #expect(await iterator.next() == nil)
    }

    @Test func guestOpensImmediatelyAndDoesNotReplayOnLaterSessionUpdates() async throws {
        let session = makeSession()
        _ = try await session.restore()
        var opened: [ResetPasswordLink] = []
        let router = GuestResetLinkRouter(session: session) { opened.append($0) }
        await router.receive(link)
        #expect(opened == [link] && router.pending == nil)
        _ = try await session.restore()
        await router.receive(ResetPasswordLink(token: "", email: ""))
        #expect(opened == [link, ResetPasswordLink(token: "", email: "")])
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func activeSessionDefersLatestLinkUntilSignOut(verified: Bool) async throws {
        let session = makeSession()
        try await session.accept(
            SessionResult(
                token: "session-token",
                account: SessionAccount(
                    id: "0199a3c0-0000-7000-8000-000000000001", name: "Test", email: link.email,
                    hasVerifiedEmail: verified, policies: AccountPolicies(termsVersion: "1", privacyVersion: "1"),
                    walkthroughSeen: true)))
        let snapshot = await session.activeSession()
        let (opened, continuation) = AsyncStream<ResetPasswordLink>.makeStream()
        var iterator = opened.makeAsyncIterator()
        var count = 0
        let router = GuestResetLinkRouter(session: session) {
            count += 1
            continuation.yield($0)
        }
        await router.receive(link)
        let latest = ResetPasswordLink(token: "latest-token", email: link.email)
        await router.receive(latest)
        #expect(count == 0 && router.pending == latest)
        #expect(await session.activeSession() == snapshot)
        _ = try await session.signOut(discardPending: true, unauthorized: true)
        #expect(await iterator.next() == latest)
        #expect(count == 1 && router.pending == nil)
        continuation.finish()
        #expect(await iterator.next() == nil)
    }

    private func makeSession() -> SessionController {
        SessionController(credentials: ResetLinkCredentials(), accounts: ResetLinkAccounts())
    }
}

private actor ResetLinkCredentials: SessionStore {
    private var data: Data?
    func read() -> Data? { data }
    func write(_ data: Data) { self.data = data }
    func delete() { data = nil }
}

private actor ResetLinkAccounts: SessionAccountStore {
    func open(accountID: AccountID) {}
    func upsert(_ account: SessionAccount) {}
    func close() {}
}
