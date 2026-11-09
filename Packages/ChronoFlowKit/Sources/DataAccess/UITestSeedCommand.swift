#if DEBUG
    import Foundation

    public struct UITestSeedCommand: Codable, Sendable, Equatable {
        public let authorization: String
        public let nonce: String
        public let environment: [String: String]
        public let arguments: [String]

        public init(
            authorization: String, nonce: String = UUID().uuidString, environment: [String: String], arguments: [String]
        ) {
            self.authorization = authorization
            self.nonce = nonce
            self.environment = environment
            self.arguments = arguments
        }

        public func preservesLaunchSettings(in processArguments: [String]) -> Bool {
            func value(_ key: String, in values: [String]) -> String? {
                guard let index = values.firstIndex(of: key), values.indices.contains(index + 1) else { return nil }
                return values[index + 1]
            }
            return ["-AppleLanguages", "-AppleLocale", "-AppleInterfaceStyle", "-UIPreferredContentSizeCategoryName"]
                .allSatisfy {
                    value($0, in: arguments) == value($0, in: processArguments)
                }
        }

        public func url() throws -> URL {
            var parts = URLComponents()
            parts.scheme = "chronoflow-uitest"
            parts.host = "reseed"
            parts.queryItems = [
                URLQueryItem(name: "payload", value: try JSONEncoder().encode(self).base64EncodedString())
            ]
            guard let url = parts.url else { throw URLError(.badURL) }
            return url
        }

        public init?(url: URL, authorizedID: String) {
            guard url.scheme == "chronoflow-uitest", url.host == "reseed", url.path.isEmpty,
                let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
                let items = parts.queryItems, items.count == 1, items[0].name == "payload",
                let value = items[0].value, value.utf8.count < 32_768,
                let data = Data(base64Encoded: value), let command = try? JSONDecoder().decode(Self.self, from: data),
                UUID(uuidString: authorizedID) != nil, command.authorization == authorizedID,
                UUID(uuidString: command.nonce) != nil,
                let rawID = command.environment["CF_AUTH_TEST_ID"], UUID(uuidString: rawID) != nil,
                command.environment["CF_UI_TEST_PROFILE"] == "screen",
                command.environment.keys.allSatisfy({ $0.hasPrefix("CF_") })
            else { return nil }
            self = command
        }
    }
#endif
