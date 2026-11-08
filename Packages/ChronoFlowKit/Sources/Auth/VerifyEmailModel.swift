import AppCore
import Foundation
import Observation

nonisolated public struct VerificationContext: Sendable, Equatable {
    public let accountID: String
    public let email: String
    public let epoch: UInt64
    public init(accountID: String, email: String, epoch: UInt64) {
        self.accountID = accountID
        self.email = email
        self.epoch = epoch
    }
}

@MainActor @Observable public final class VerifyEmailModel {
    public enum State: Sendable { case waiting, failed }
    public private(set) var state: State = .waiting
    public let context: VerificationContext
    public let form = AuthFormModel(displayedFields: [], context: .verify)
    public private(set) var signOutFailure: DataFailure?
    public private(set) var sessionFailure: SessionFailure?
    public private(set) var hasStatus = false
    public private(set) var deadline: TimeInterval?
    public private(set) var now: TimeInterval
    public var remaining: Int { max(0, Int(ceil((deadline ?? now) - now))) }
    public var canResend: Bool { !form.busy && remaining == 0 && (hasStatus || state == .failed) }
    private let source: any DataSource
    private let clock: @Sendable () -> Date
    private let current: @MainActor () async -> VerificationContext?
    private let persist: @MainActor (VerificationContext) async throws -> Bool
    private let route: @MainActor () async -> Void
    private let discard: @MainActor () async throws -> Void
    private let mail: (@MainActor () async -> SignedVerificationInput?)?
    private var input: SignedVerificationInput?
    private var invalidLink = false
    private var active = true
    private var revision: UInt64 = 0
    private var linkPending = false
    private var completed = false
    public var isActive: Bool { active }

    public init(
        context: VerificationContext, source: any DataSource,
        now: @escaping @Sendable () -> Date = { Date() },
        current: @escaping @MainActor () async -> VerificationContext?,
        persist: @escaping @MainActor (VerificationContext) async throws -> Bool,
        route: @escaping @MainActor () async -> Void,
        discard: @escaping @MainActor () async throws -> Void,
        mail: (@MainActor () async -> SignedVerificationInput?)? = nil
    ) {
        self.context = context
        self.source = source
        clock = now
        self.now = now().timeIntervalSince1970
        self.current = current
        self.persist = persist
        self.route = route
        self.discard = discard
        self.mail = mail
    }
    public func receiveLink(_ input: SignedVerificationInput?) {
        guard active else { return }
        revision &+= 1
        self.input = input
        invalidLink = input == nil
        linkPending = true
    }
    public func tick() { now = clock().timeIntervalSince1970 }
    private func isCurrent(_ revision: UInt64) async -> Bool {
        guard active, self.revision == revision, !Task.isCancelled else { return false }
        let value = await current()
        return active && self.revision == revision && !Task.isCancelled && value == context
    }
    public func activate() async {
        tick()
        await check(silent: input == nil && !invalidLink)
    }
    public func check(silent: Bool = false) async {
        guard active, !completed, form.begin(.checkVerification) else { return }
        let revision = revision
        let submitted = input
        let malformed = invalidLink
        linkPending = false
        defer {
            form.finish()
            if active, linkPending { Task { [weak self] in await self?.check() } }
        }
        do {
            guard await isCurrent(revision) else { return }
            if malformed {
                invalidLink = false
                state = .failed
                return
            }
            let status: EmailVerificationStatus
            if let submitted {
                do { status = try await source.verifyEmail(submitted) } catch {
                    if await isCurrent(revision), case .validation = error as? DataFailure { input = nil }
                    throw error
                }
            } else {
                status = try await source.verificationStatus()
            }
            guard await isCurrent(revision), status.email == context.email else { return }
            input = nil
            try await accept(status, revision: revision)
            guard await isCurrent(revision) else { return }
            state = .waiting
        } catch {
            guard await isCurrent(revision), !(error is CancellationError) else { return }
            if let failure = error as? SessionFailure { sessionFailure = failure }
            if !silent { state = .failed }
        }
    }
    public func resend() async {
        tick()
        guard active, !completed, canResend, form.begin(.resendVerification) else { return }
        let revision = revision
        defer { form.finish() }
        do {
            guard await isCurrent(revision) else { return }
            let status = try await source.resendVerificationEmail()
            guard await isCurrent(revision), status.email == context.email else { return }
            try await accept(status, revision: revision)
            guard await isCurrent(revision) else { return }
            state = .waiting
        } catch {
            guard await isCurrent(revision), !(error is CancellationError) else { return }
            let failure = error as? DataFailure ?? .server(status: nil)
            if case .throttled(let seconds, _) = failure {
                tick()
                deadline = max(deadline ?? now, now + max(0, seconds))
            }
            form.receive(failure)
        }
    }
    private func accept(_ status: EmailVerificationStatus, revision: UInt64) async throws {
        guard await isCurrent(revision), status.email == context.email else { return }
        hasStatus = true
        tick()
        if !status.hasVerifiedEmail {
            deadline = max(deadline ?? now, now + TimeInterval(max(0, status.resendAfterSeconds)))
            return
        }
        let identity = try await source.fetchIdentity()
        guard await isCurrent(revision), identity.id == context.accountID, identity.email == context.email,
            identity.hasVerifiedEmail
        else { return }
        guard try await persist(context), await isCurrent(revision) else { return }
        completed = true
        await route()
    }
    public func openEmail(using open: @MainActor (URL) async -> Bool) async {
        guard active, !form.busy else { return }
        if let mail {
            if let input = await mail() {
                receiveLink(input)
                await check()
            }
        } else if let url = URL(string: "message://"), await open(url) {
            await check(silent: true)
        }
    }
    public func signOut() async {
        guard active, !form.busy, await current() == context, active, form.begin(.signOut) else { return }
        signOutFailure = nil
        revision &+= 1
        defer { form.finish() }
        do {
            try await discard()
            cancel()
        } catch { if active, !Task.isCancelled { signOutFailure = error as? DataFailure ?? .server(status: nil) } }
    }
    public func cancel() {
        active = false
        revision &+= 1
        input = nil
        invalidLink = false
        form.clear()
    }
}
