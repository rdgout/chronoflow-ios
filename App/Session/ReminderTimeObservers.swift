import Foundation
import Reminders
import UIKit

nonisolated final class ReminderTimeObservers: @unchecked Sendable {
    private let tokens: [any NSObjectProtocol]
    init(service: ReminderService) {
        tokens = [UIApplication.significantTimeChangeNotification, .NSSystemTimeZoneDidChange].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in
                Task { await service.reschedule() }
            }
        }
    }
    deinit { for token in tokens { NotificationCenter.default.removeObserver(token) } }
}
