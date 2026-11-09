import AppCore
import Foundation
import GRDB
import Testing

@testable import LocalStore

#if os(macOS)
    import Darwin
#endif

let accountA = "019a562b-8000-7000-8000-000000000001"
let accountB = "019a562b-8000-7000-8000-000000000002"

func temporaryStoreRoot() throws -> URL {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("build/StoreTests/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

struct Column: Decodable, Equatable, Sendable {
    let name: String
    let type: String
    let notnull: Int
    let `default`: String?
    let pk: Int

    var normalized: Self {
        let value = self.default?.lowercased()
        return Self(
            name: name, type: type, notnull: notnull,
            default: value == "true" ? "1" : value == "false" ? "0" : value, pk: pk)
    }
}

struct ForeignKey: Decodable, Equatable, Sendable {
    let table: String
    let from: String
    let to: String
    let onDelete: String

    enum CodingKeys: String, CodingKey {
        case table, from, to
        case onDelete = "on_delete"
    }
}

struct SchemaTable: Decodable, Sendable {
    let columns: [Column]
    let foreignKeys: [ForeignKey]
}

func isBackupExcluded(_ directory: URL) throws -> Bool {
    #if os(macOS)
        let key = "com.apple.metadata:com_apple_backup_excludeItem"
        let length = getxattr(directory.path, key, nil, 0, 0, 0)
        guard length > 0 else { return false }
        var data = Data(count: length)
        let read = data.withUnsafeMutableBytes { getxattr(directory.path, key, $0.baseAddress, length, 0, 0) }
        guard read == length else { return false }
        return try PropertyListSerialization.propertyList(from: data, format: nil) as? String == "com.apple.backupd"
    #else
        return try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
    #endif
}
