import AppCore
import Foundation
import Observation

public struct ReminderTap: Sendable, Equatable {
    public var tripID: String
    public var blockID: String?
    public var accountID: String?
    public var inputHash: String?
    public init?(intent: PendingLaunchIntent) {
        guard intent.notification?.actionIdentifier != "com.apple.UNNotificationDismissActionIdentifier",
            let data = intent.notification?.userInfoJSON,
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let raw = object["url"] as? String, let url = URL(string: raw), url.scheme == "chronoflow",
            url.host == "trip",
            url.query == nil, url.fragment == nil, url.pathComponents.count == 2,
            let id = url.pathComponents.last, !id.isEmpty
        else { return nil }
        tripID = id
        blockID = object["blockID"] as? String
        accountID = object["accountID"] as? String
        inputHash = object["inputHash"] as? String
    }
}

@MainActor @Observable public final class ReminderTapRouter {
    public private(set) var pending: ReminderTap?
    public init() {}
    public func receive(_ intent: PendingLaunchIntent) { if let tap = ReminderTap(intent: intent) { pending = tap } }
    public func clear() { pending = nil }
}

#if DEBUG
    public actor MockReminderCenter: ReminderNotificationCenter {
        public var status: ReminderPermission
        public private(set) var permissionRequestCount = 0
        private var requests: [String: ReminderRequest] = [:]
        public init(permission: ReminderPermission) { status = permission }
        public func setStatus(_ status: ReminderPermission) { self.status = status }
        public func permission() -> ReminderPermission { status }
        public func requestPermission() -> ReminderPermission {
            permissionRequestCount += 1
            if status == .undetermined { status = .granted }
            return status
        }
        public func pending() -> [ReminderRequest] { Array(requests.values) }
        public func add(_ request: ReminderRequest) { requests[request.identifier] = request }
        public func remove(_ identifiers: [String]) { for id in identifiers { requests[id] = nil } }
        public func removeDelivered() {}
    }
#endif
