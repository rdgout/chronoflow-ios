#if canImport(UserNotifications)
    import Foundation
    import UserNotifications

    public actor SystemReminderCenter: ReminderNotificationCenter {
        private let center: UNUserNotificationCenter
        public init(center: UNUserNotificationCenter = .current()) { self.center = center }
        public static func permission(_ status: UNAuthorizationStatus) -> ReminderPermission {
            switch status {
            case .notDetermined: .undetermined
            case .denied: .blocked
            case .authorized, .provisional: .granted
            #if os(iOS)
                case .ephemeral: .granted
            #endif
            @unknown default: .unsupported
            }
        }
        public func permission() async -> ReminderPermission {
            Self.permission(await center.notificationSettings().authorizationStatus)
        }
        public func requestPermission() async throws -> ReminderPermission {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
            return await permission()
        }
        public func pending() async -> [ReminderRequest] {
            await center.pendingNotificationRequests().compactMap { request in
                let url = request.content.userInfo["url"] as? String ?? ""
                guard request.identifier.hasPrefix("chronoflow.") || url.hasPrefix("chronoflow://trip/") else {
                    return nil
                }
                if let encoded = request.content.userInfo["reminder"] as? String,
                    let data = encoded.data(using: .utf8),
                    var value = try? JSONDecoder().decode(ReminderRequest.self, from: data)
                {
                    value.title = request.content.title
                    value.body = request.content.body
                    return value
                }
                return ReminderRequest(
                    identifier: request.identifier, title: request.content.title, body: request.content.body,
                    sendAt: .distantPast, tripID: "", blockID: "", inputHash: "", memberKeys: [])
            }
        }
        public func add(_ request: ReminderRequest) async throws {
            let content = UNMutableNotificationContent()
            content.title = request.title
            content.body = request.body
            content.userInfo = [
                "url": "chronoflow://trip/\(request.tripID)", "tripID": request.tripID,
                "accountID": request.accountID ?? "", "blockID": request.blockID, "inputHash": request.inputHash,
                "reminder": String(decoding: try JSONEncoder().encode(request), as: UTF8.self),
            ]
            let trigger = Self.trigger(for: request.sendAt)
            try await center.add(
                UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger))
        }
        public static func trigger(for date: Date) -> UNCalendarNotificationTrigger {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .gmt
            var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            parts.timeZone = .gmt
            return UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        }
        public func remove(_ identifiers: [String]) async {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
        public func removeDelivered() async {
            let ids = await center.deliveredNotifications().filter {
                $0.request.identifier.hasPrefix("chronoflow.")
                    || ($0.request.content.userInfo["url"] as? String ?? "").hasPrefix("chronoflow://trip/")
            }.map(\.request.identifier)
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }
#endif
