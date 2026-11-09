#if DEBUG
    import Foundation

    public struct UITestSeedCommand: Codable, Sendable, Equatable {
        public enum Rejection: String, Error, Sendable {
            case invalidEndpoint, invalidPayload, malformedCommand, missingAuthorization, foreignAuthorization
            case invalidNonce, invalidTestID, invalidProfile, foreignEnvironment
        }

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

        public func changedLaunchSettings(
            arguments processArguments: [String], environment processEnvironment: [String: String]
        ) -> [String] {
            func values(_ key: String, in arguments: [String]) -> [String] {
                arguments.indices.filter { arguments[$0] == key }.map { index in
                    let next = index + 1
                    return arguments.indices.contains(next) && !arguments[next].hasPrefix("-") ? arguments[next] : ""
                }
            }
            let keys = Set((arguments + processArguments).filter { $0.hasPrefix("-Apple") || $0.hasPrefix("-UI") })
                .union([
                    "-cf.settings.language", "-cf.settings.theme", "-cf.reduceMotion", "-cf.mode", "-cf.freezeAt",
                    "-cf.readyAt", "-cf.mainThreadStall",
                ])
            let changedArguments = keys.filter { values($0, in: arguments) != values($0, in: processArguments) }
            let environmentKeys = Set(environment.keys).union(processEnvironment.keys).filter {
                !$0.hasPrefix("CF_") || $0 == "CF_UI_TEST_PROFILE"
            }
            return (Array(changedArguments) + environmentKeys.filter { environment[$0] != processEnvironment[$0] })
                .sorted()
        }

        public func preservesLaunchSettings(in processArguments: [String]) -> Bool {
            changedLaunchSettings(arguments: processArguments, environment: environment).isEmpty
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
            guard let command = try? Self(validating: url, authorizedID: authorizedID) else { return nil }
            self = command
        }

        public init(validating url: URL, authorizedID: String?) throws {
            guard url.scheme == "chronoflow-uitest", url.host == "reseed", url.path.isEmpty,
                url.user == nil, url.password == nil, url.port == nil, url.fragment == nil
            else { throw Rejection.invalidEndpoint }
            guard
                let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
                let items = parts.queryItems, items.count == 1, items[0].name == "payload",
                let value = items[0].value, value.utf8.count < 32_768,
                let data = Data(base64Encoded: value)
            else { throw Rejection.invalidPayload }
            guard let command = try? JSONDecoder().decode(Self.self, from: data) else {
                throw Rejection.malformedCommand
            }
            guard let authorizedID, let authorized = UUID(uuidString: authorizedID) else {
                throw Rejection.missingAuthorization
            }
            guard UUID(uuidString: command.authorization) == authorized else { throw Rejection.foreignAuthorization }
            guard UUID(uuidString: command.nonce) != nil else { throw Rejection.invalidNonce }
            guard let rawID = command.environment["CF_AUTH_TEST_ID"], UUID(uuidString: rawID) != nil else {
                throw Rejection.invalidTestID
            }
            guard command.environment["CF_UI_TEST_PROFILE"] == "screen" else { throw Rejection.invalidProfile }
            guard command.environment.keys.allSatisfy({ $0.hasPrefix("CF_") }) else {
                throw Rejection.foreignEnvironment
            }
            self = command
        }
    }
#endif
