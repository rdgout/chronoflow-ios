import Foundation

public nonisolated struct SnapshotProfile: Decodable, Sendable {
    public let dynamicType: [String]
    public let introTimes: [Int]
    public let launchFrames: [String]

    public static func current(model: String? = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"])
        throws
        -> Self
    {
        struct Catalog: Decodable {
            struct Device: Decodable { let profile: String }
            let devices: [String: Device]
            let profiles: [String: SnapshotProfile]
        }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("profiles.json")
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
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
