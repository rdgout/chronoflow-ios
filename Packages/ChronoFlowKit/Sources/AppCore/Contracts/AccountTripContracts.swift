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
        self.readiness = ProfilePreferences.readiness(readiness, bodyClock: settings.bodyClock)
        self.billing = billing
        self.security = security
    }
    enum CodingKeys: String, CodingKey {
        case id, name, email, hasVerifiedEmail, settings, readiness, billing, security
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            name: try c.decode(String.self, forKey: .name),
            email: try c.decode(String.self, forKey: .email),
            hasVerifiedEmail: try c.decode(Bool.self, forKey: .hasVerifiedEmail),
            settings: try c.decode(AccountSettings.self, forKey: .settings),
            readiness: try c.decode(JSONObject.self, forKey: .readiness),
            billing: try c.decode(JSONObject.self, forKey: .billing),
            security: try c.decode(JSONObject.self, forKey: .security)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(email, forKey: .email)
        try c.encode(hasVerifiedEmail, forKey: .hasVerifiedEmail)
        try c.encode(settings, forKey: .settings)
        try c.encode(ProfilePreferences.readiness(readiness, bodyClock: settings.bodyClock), forKey: .readiness)
        try c.encode(billing, forKey: .billing)
        try c.encode(security, forKey: .security)
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
        self.bodyClock = ProfilePreferences.bodyClock(bodyClock)
        self.sleepAnswered = sleepAnswered
        self.preferences = preferences
        self.reminders = reminders
        self.planCredits = planCredits
        self.policies = policies
    }
    enum CodingKeys: String, CodingKey {
        case bodyClock, sleepAnswered, preferences, reminders, planCredits, policies
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            bodyClock: try c.decode(JSONObject.self, forKey: .bodyClock),
            sleepAnswered: try c.decode(Bool.self, forKey: .sleepAnswered),
            preferences: try c.decode(JSONObject.self, forKey: .preferences),
            reminders: try c.decode(JSONObject.self, forKey: .reminders),
            planCredits: try c.decode(JSONObject.self, forKey: .planCredits),
            policies: try c.decode(AccountPolicies.self, forKey: .policies)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ProfilePreferences.bodyClock(bodyClock), forKey: .bodyClock)
        try c.encode(sleepAnswered, forKey: .sleepAnswered)
        try c.encode(preferences, forKey: .preferences)
        try c.encode(reminders, forKey: .reminders)
        try c.encode(planCredits, forKey: .planCredits)
        try c.encode(policies, forKey: .policies)
    }

}
