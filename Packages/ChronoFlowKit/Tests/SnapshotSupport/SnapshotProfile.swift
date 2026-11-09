import AppCore
import Foundation

public nonisolated struct SnapshotProfile: Decodable, Sendable {
    public let dynamicType: [String]
    public let introTimes: [Int]
    public let launchFrames: [String]

    public static func current(model: String? = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"])
        throws
        -> Self
    {
        let catalog = try SnapshotCatalog.read()
        let key: String
        if let model {
            guard let device = catalog.devices[model] else { throw ProfileError.unknownModel(model) }
            key = device.profile
        } else {
            key = "full"
        }
        guard let profile = catalog.profiles[key] else { throw ProfileError.missingProfile(key) }
        return profile
    }

    enum ProfileError: Error {
        case unknownModel(String)
        case missingProfile(String)
    }
}

public nonisolated struct SnapshotDevice: Decodable, Sendable {
    public let alias: String
    public let profile: String
    public let width: CGFloat
    public let height: CGFloat
    public let scale: CGFloat
    public let insets: MoonTarget.Insets
    public var size: CGSize { CGSize(width: width, height: height) }
    public var name: String { "\(alias)-\(Int(width))x\(Int(height))-\(Int(scale))x" }

    public static func all() throws -> [SnapshotDevice] {
        try SnapshotCatalog.read().devices.values.sorted { $0.alias < $1.alias }
    }

    public var coverage: SnapshotProfile {
        get throws {
            let catalog = try SnapshotCatalog.read()
            guard let value = catalog.profiles[profile] else {
                throw SnapshotProfile.ProfileError.missingProfile(profile)
            }
            return value
        }
    }
}

private nonisolated struct SnapshotCatalog: Decodable {
    let devices: [String: SnapshotDevice]
    let profiles: [String: SnapshotProfile]

    static func read() throws -> Self {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("profiles.json")
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}
