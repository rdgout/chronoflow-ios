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
