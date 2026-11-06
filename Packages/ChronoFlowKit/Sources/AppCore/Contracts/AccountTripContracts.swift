import Foundation

public struct AccountSnapshot: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var email: String
    public var hasVerifiedEmail: Bool
    public var settings: AccountSettings
    public var readiness: JSONObject
    public var billing: JSONObject
    public var security: JSONObject

    public init(
        id: String, name: String, email: String, hasVerifiedEmail: Bool, settings: AccountSettings,
        readiness: JSONObject, billing: JSONObject, security: JSONObject
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.hasVerifiedEmail = hasVerifiedEmail
        self.settings = settings
        self.readiness = readiness
        self.billing = billing
        self.security = security
    }
}

public struct AccountSettings: Codable, Sendable, Equatable {
    public var bodyClock: JSONObject
    public var sleepAnswered: Bool
    public var preferences: JSONObject
    public var reminders: JSONObject
    public var planCredits: JSONObject
    public var policies: AccountPolicies

    public init(
        bodyClock: JSONObject, sleepAnswered: Bool, preferences: JSONObject, reminders: JSONObject,
        planCredits: JSONObject, policies: AccountPolicies
    ) {
        self.bodyClock = bodyClock
        self.sleepAnswered = sleepAnswered
        self.preferences = preferences
        self.reminders = reminders
        self.planCredits = planCredits
        self.policies = policies
    }
}

public struct TripListItem: Codable, Sendable, Equatable {
    public var card: JSONObject
    public var planInputHash: String
    public var planStartUtc: String
    public var planStartZone: String
    public var planEndUtc: String
    public var planEndDate: String
    public var preparationDays: Int
    public var adaptation: JSONObject?
    public var keepOffline: Bool
    public var detailVersion: String?
    public var checkState: CheckState?

    public init(
        card: JSONObject, planInputHash: String, planStartUtc: String, planStartZone: String, planEndUtc: String,
        planEndDate: String, preparationDays: Int, adaptation: JSONObject? = nil, keepOffline: Bool,
        detailVersion: String? = nil, checkState: CheckState? = nil
    ) {
        self.card = card
        self.planInputHash = planInputHash
        self.planStartUtc = planStartUtc
        self.planStartZone = planStartZone
        self.planEndUtc = planEndUtc
        self.planEndDate = planEndDate
        self.preparationDays = preparationDays
        self.adaptation = adaptation
        self.keepOffline = keepOffline
        self.detailVersion = detailVersion
        self.checkState = checkState
    }
}

public struct TripDetail: Codable, Sendable, Equatable {
    public var trip: JSONObject
    public var plan: JSONObject
    public var notices: JSONObject
    public var timeline: JSONObject
    public var checkState: CheckState
    public var detailVersion: String

    public init(
        trip: JSONObject, plan: JSONObject, notices: JSONObject, timeline: JSONObject, checkState: CheckState,
        detailVersion: String
    ) {
        self.trip = trip
        self.plan = plan
        self.notices = notices
        self.timeline = timeline
        self.checkState = checkState
        self.detailVersion = detailVersion
    }
}

public struct CheckState: Codable, Sendable, Equatable {
    public var planInputHash: String
    public var marks: [CheckMark]
    public var days: [JSONObject]

    public init(planInputHash: String, marks: [CheckMark], days: [JSONObject]) {
        self.planInputHash = planInputHash
        self.marks = marks
        self.days = days
    }
}

public struct CheckMark: Codable, Sendable, Equatable {
    public var key: CheckKey
    public var status: CheckStatus
    public var markedAt: String

    public init(key: CheckKey, status: CheckStatus, markedAt: String) {
        self.key = key
        self.status = status
        self.markedAt = markedAt
    }
}

public struct CheckKey: Codable, Sendable, Equatable {
    public var type: BlockType
    public var localDate: String
    public var ordinal: Int

    public init(type: BlockType, localDate: String, ordinal: Int) {
        self.type = type
        self.localDate = localDate
        self.ordinal = ordinal
    }
}

public struct TripCheckResult: Codable, Sendable, Equatable {
    public var checkState: CheckState
    public var detailVersion: String

    public init(checkState: CheckState, detailVersion: String) {
        self.checkState = checkState
        self.detailVersion = detailVersion
    }
}

public enum CheckStatus: String, Codable, Sendable { case done, skipped }
public enum BlockType: String, Codable, Sendable {
    case flight, layover, transfer, sleep, nap, rest, note
    case movementBreak = "movement_break"
    case zoneChange = "zone_change"
    case avoidLight = "avoid_light"
    case seekLight = "seek_light"
    case lightOK = "light_ok"
    case lightNeutral = "light_neutral"
    case caffeineServing = "caffeine_serving"
    case caffeineOK = "caffeine_ok"
    case caffeineRoutine = "caffeine_routine"
    case noCaffeine = "no_caffeine"
}
