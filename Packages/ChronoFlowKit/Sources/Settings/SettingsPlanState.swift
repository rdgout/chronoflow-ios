import AppCore
import Foundation

public struct SettingsPlanState: Sendable, Equatable {
    public let loaded: Bool
    public let offline: Bool
    public let credits: Int?
    public let unlimited: Bool
    public let subscription: JSONObject
    public let paymentPending: Bool
    public init(credits: JSONObject?, billing: JSONObject?, loaded: Bool, offline: Bool) {
        self.loaded = loaded
        self.offline = offline
        unlimited = credits?["unlimited"] == .bool(true)
        if case .number(let count) = credits?["credits"], !count.isNaN, count >= 0, count < Decimal(Int.max),
            Decimal(NSDecimalNumber(decimal: count).intValue) == count
        {
            self.credits = NSDecimalNumber(decimal: count).intValue
        } else {
            self.credits = nil
        }
        subscription = JSONObject(billing?["subscription"]?.object ?? [:])
        paymentPending = billing?["checkout"]?.object?["status"] == .string("pending")
    }
    public var hasBalance: Bool { unlimited || credits != nil }
    public var cancelled: Bool { subscription["canResume"] == .bool(true) }
    public var paymentFailed: Bool { subscription["paymentFailed"] == .bool(true) }
    public var date: String? { subscription[cancelled ? "endsAt" : "renewsAt"]?.string }
    public var interval: String { subscription["tier"]?.string == "annual" ? "yearly" : "monthly" }
}
