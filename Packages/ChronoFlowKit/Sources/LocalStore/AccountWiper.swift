import AppCore
import Foundation

public actor AccountWiper {
    private let applicationSupport: URL
    private let namespace: StorageNamespace
    private let credentials: any SessionStore
    private let remove: @Sendable (URL) throws -> Void

    public init(
        applicationSupport: URL, namespace: StorageNamespace, credentials: any SessionStore,
        remove: @escaping @Sendable (URL) throws -> Void = { url in
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    ) {
        self.applicationSupport = applicationSupport
        self.namespace = namespace
        self.credentials = credentials
        self.remove = remove
    }

    private var root: URL { applicationSupport.appendingPathComponent(namespace.directoryName, isDirectory: true) }
    private var marker: URL { root.appendingPathComponent("pending-wipe.json") }

    public func begin(_ id: AccountID) throws {
        assert(!Thread.isMainThread)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(id.rawValue).write(to: marker, options: .atomic)
        var url = marker
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        #if os(iOS)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: marker.path)
        #endif
    }

    public func recover() async throws {
        assert(!Thread.isMainThread)
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        let id = try AccountID(JSONDecoder().decode(String.self, from: Data(contentsOf: marker)))
        try erase(id)
        try await credentials.delete()
        try finish()
    }

    public func erase(_ id: AccountID) throws {
        assert(!Thread.isMainThread)
        let directory = root.appendingPathComponent("Accounts", isDirectory: true)
            .appendingPathComponent(id.rawValue, isDirectory: true)
        try remove(directory)
    }

    public func finish() throws {
        if FileManager.default.fileExists(atPath: marker.path) { try FileManager.default.removeItem(at: marker) }
    }
}
