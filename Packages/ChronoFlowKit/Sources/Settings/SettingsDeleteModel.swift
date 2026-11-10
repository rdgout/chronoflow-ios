import AppCore
import Foundation
import Observation

@MainActor @Observable public final class SettingsDeleteModel {
    public enum Stage: Sendable { case confirmation, password, deleted }
    public private(set) var stage: Stage = .confirmation
    public var password = ""
    public private(set) var busy = false
    public private(set) var errorKey: String?
    public private(set) var retryAt: Date?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let delete: @MainActor (String) async throws -> Void
    public init(delete: @escaping @MainActor (String) async throws -> Void) { self.delete = delete }
    public func confirmDeletion() {
        guard !busy else { return }
        stage = .password
    }
    public func submit(now: Date = .now) async {
        guard !busy, stage == .password, retryAt.map({ $0 <= now }) ?? true else { return }
        guard !password.isEmpty else {
            errorKey = "Enter your password."
            return
        }
        let value = password
        password = ""
        let started = generation
        busy = true
        errorKey = nil
        defer { if generation == started { busy = false } }
        do {
            try await delete(value)
            guard generation == started else { return }
            stage = .deleted
        } catch is CancellationError {
        } catch {
            guard generation == started else { return }
            switch error as? DataFailure {
            case .offline: errorKey = "Needs a connection."
            case .throttled(let seconds, _):
                retryAt = now.addingTimeInterval(max(0, seconds))
                errorKey = "Too many attempts."
            case .validation(let fields, _):
                errorKey =
                    fields["billing"] != nil
                    ? "Your subscription could not be cancelled. Please try deleting your account again."
                    : fields["password"]?.key == "The provided password was incorrect."
                        ? "The provided password was incorrect." : "Check the highlighted field."
            default: errorKey = "Something went wrong"
            }
        }
    }
    public func stop() {
        generation += 1
        password = ""
        stage = .confirmation
        busy = false
        errorKey = nil
    }
}
