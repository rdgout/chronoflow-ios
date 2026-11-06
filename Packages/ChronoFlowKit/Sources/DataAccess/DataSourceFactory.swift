import AppCore
import Foundation

public enum DataSourceConfigurationFailure: Error, Sendable, Equatable { case invalidSource, invalidBaseURL }

public struct APIBaseURL: Sendable, Equatable {
    public let url: URL
    public init(_ value: String, release: Bool) throws {
        guard let c = URLComponents(string: value), let scheme = c.scheme,
            ["http", "https"].contains(scheme), !release || scheme == "https",
            let host = c.host, !host.isEmpty, c.port == nil || (1...65535).contains(c.port!), c.user == nil,
            c.password == nil,
            c.query == nil, c.fragment == nil, let url = c.url,
            !c.path.split(separator: "/").contains(where: { [".", ".."].contains(String($0)) })
        else { throw DataSourceConfigurationFailure.invalidBaseURL }
        self.url = url
    }
}

public struct DataSourceFactory: Sendable {
    public enum Source: String, Sendable { case mock, api }
    public let source: Source
    public let baseURL: APIBaseURL
    public var namespace: StorageNamespace { source == .mock ? .mock : .api }
    public init(
        setting: String = "mock", baseURL: String = "https://api.chronoflow.net/v1", release: Bool, testing: Bool
    ) throws {
        guard let requested = Source(rawValue: setting) else { throw DataSourceConfigurationFailure.invalidSource }
        self.baseURL = try APIBaseURL(baseURL, release: release)
        source = testing ? .mock : requested
    }
    public func make(mock: () throws -> any DataSource, api: () throws -> any DataSource) rethrows -> any DataSource {
        switch source {
        case .mock: try mock()
        case .api: try api()
        }
    }
}
