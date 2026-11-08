import Foundation
import LocalStore
import Observation

@MainActor @Observable public final class SettingsProfileModel {
    public var name: String
    public private(set) var email: String
    public private(set) var busy = false
    public private(set) var saved = false
    public private(set) var errorKey: String?
    @ObservationIgnored private var storedName: String
    @ObservationIgnored private let save: @MainActor (String) async throws -> Void

    public init(account: AccountRecord, save: @escaping @MainActor (String) async throws -> Void) {
        name = account.name
        storedName = account.name
        email = account.email
        self.save = save
    }

    public func receive(_ account: AccountRecord) {
        if name == storedName { name = account.name }
        storedName = account.name
        email = account.email
    }

    public func submit() async {
        guard !busy else { return }
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 255 else {
            errorKey = "Enter your name."
            saved = false
            return
        }
        busy = true
        saved = false
        defer { busy = false }
        do {
            try await save(value)
            name = value
            storedName = value
            errorKey = nil
            saved = true
        } catch is CancellationError {
        } catch {
            errorKey = "We couldn't save your change. Please try again."
        }
    }
}
