import AppCore
import Observation

@MainActor @Observable public final class TermsUpdateModel {
    public private(set) var policies: AccountPolicies?
    public private(set) var busy = false
    public private(set) var completed = false
    public private(set) var failed = false
    @ObservationIgnored private let save: @MainActor (String) async throws -> Void

    public init(policies: AccountPolicies? = nil, save: @escaping @MainActor (String) async throws -> Void) {
        self.policies = policies
        self.save = save
    }

    public func update(policies: AccountPolicies?) {
        if self.policies?.termsVersion != policies?.termsVersion {
            completed = false
            failed = false
        }
        self.policies = policies
    }

    public var canAccept: Bool {
        guard let policies else { return false }
        return !busy && !completed && policies.acceptedTermsVersion != policies.termsVersion
    }

    public func accept() async {
        guard canAccept, let policies else { return }
        busy = true
        failed = false
        defer { busy = false }
        do {
            try await save(policies.termsVersion)
            completed = self.policies?.termsVersion == policies.termsVersion
        } catch is CancellationError {
        } catch {
            failed = true
        }
    }
}
