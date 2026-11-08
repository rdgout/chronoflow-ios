import AppCore
import Foundation

public struct APIEndpoint: Sendable {
    public enum Access: Sendable { case publicRoute, authenticated }
    public let method: String
    public let path: [String]
    public let access: Access
    public let body: Data?
    public let query: [String: String]
    public let timeout: TimeInterval

    public init(
        method: String = "GET", path: [String], access: Access = .authenticated, body: Data? = nil,
        timeout: TimeInterval = 15, query: [String: String] = [:]
    ) {
        self.method = method
        self.path = path
        self.access = access
        self.body = body
        self.timeout = timeout
        self.query = query
    }
    public func url(relativeTo base: APIBaseURL) throws -> URL {
        var c = URLComponents(url: base.url, resolvingAgainstBaseURL: false)!
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_~")
        let encoded = try path.map { part in
            guard !part.isEmpty, let encoded = part.addingPercentEncoding(withAllowedCharacters: allowed) else {
                throw DataFailure.server(status: nil)
            }
            return encoded
        }
        c.percentEncodedPath =
            c.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
            ? "/" + encoded.joined(separator: "/")
            : "/" + c.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/"
                + encoded.joined(separator: "/")
        if !query.isEmpty {
            c.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        guard let url = c.url else { throw DataFailure.server(status: nil) }
        return url
    }
}
