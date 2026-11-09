import Foundation

public actor DevicePreferences: DeviceIdentityPersistence {
    private let suiteName: String?

    public init(suiteName: String? = nil) { self.suiteName = suiteName }

    private func preferences() throws -> UserDefaults {
        assert(!Thread.isMainThread)
        guard let suiteName else { return .standard }
        guard let preferences = UserDefaults(suiteName: suiteName) else { throw Failure.unavailable }
        return preferences
    }

    public func readDeviceID() throws -> String? {
        guard let value = try preferences().object(forKey: "api.deviceId") else { return nil }
        guard let identity = value as? String else { throw DeviceIdentityFailure.invalidPersistedIdentity }
        return identity
    }

    public func writeDeviceID(_ value: String) throws {
        try preferences().set(value, forKey: "api.deviceId")
    }

    enum Failure: Error { case unavailable }
}
