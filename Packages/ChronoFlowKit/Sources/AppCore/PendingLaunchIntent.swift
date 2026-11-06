import Foundation

public struct PendingLaunchIntent: Sendable, Equatable {
    public struct Notification: Sendable, Equatable {
        public let requestIdentifier: String
        public let actionIdentifier: String
        public let userInfoJSON: Data?
        public let userText: String?

        public init(requestIdentifier: String, actionIdentifier: String, userInfoJSON: Data?, userText: String?) {
            self.requestIdentifier = requestIdentifier
            self.actionIdentifier = actionIdentifier
            self.userInfoJSON = userInfoJSON
            self.userText = userText
        }
    }

    public let urls: Set<URL>
    public let notification: Notification?

    public init(urls: Set<URL> = [], notification: Notification? = nil) {
        self.urls = urls
        self.notification = notification
    }
}

public struct LaunchProcessState: Sendable {
    public private(set) var hasConnected = false

    public init() {}

    public mutating func claimOverlay() -> Bool {
        guard !hasConnected else { return false }
        hasConnected = true
        return true
    }
}
