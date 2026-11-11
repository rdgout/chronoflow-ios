import Foundation

public struct ApiGuestTripReviewInput: Encodable, Sendable, Equatable {
    public var input: ApiTripInput
    public var identity: ApiReviewIdentity?
    public var profile: JSONObject
    public var deviceID: String
    public var guestSecret: String?

    public init(
        input: ApiTripInput, identity: ApiReviewIdentity? = nil, profile: JSONObject, deviceID: String,
        guestSecret: String? = nil
    ) {
        self.input = input
        self.identity = identity
        self.profile = profile
        self.deviceID = deviceID
        self.guestSecret = guestSecret
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(input.outbound, forKey: .outbound)
        try c.encode("one_way", forKey: .tripEndKind)
        try c.encode(input.preparationDays, forKey: .preparationDays)
        try c.encode(input.fastDelayOptIn, forKey: .fastDelayOptIn)
        try c.encode(input.latestWake, forKey: .latestWake)
        try c.encode(input.feasibleNightBed, forKey: .feasibleNightBed)
        try c.encode(input.feasibleNightWake, forKey: .feasibleNightWake)
        try c.encode(input.preDepartureBusyAnswered, forKey: .preDepartureBusyAnswered)
        try c.encode(input.preDepartureBusyIntervals, forKey: .preDepartureBusyIntervals)
        try c.encode(identity?.token, forKey: .draftToken)
        try c.encode(identity?.inputRevision ?? 0, forKey: .inputRevision)
        try c.encode(identity?.reviewRevision, forKey: .reviewRevision)
        try c.encode(ProfilePreferences.request(profile), forKey: .profile)
        try c.encode(deviceID, forKey: .deviceID)
        try c.encodeIfPresent(guestSecret, forKey: .guestSecret)
    }

    enum CodingKeys: String, CodingKey {
        case outbound, profile
        case tripEndKind = "trip_end_kind"
        case preparationDays = "preparation_days"
        case fastDelayOptIn = "fast_delay_opt_in"
        case latestWake = "latest_wake"
        case feasibleNightBed = "feasible_night_bed"
        case feasibleNightWake = "feasible_night_wake"
        case preDepartureBusyAnswered = "pre_departure_busy_answered"
        case preDepartureBusyIntervals = "pre_departure_busy_intervals"
        case draftToken = "draft_token"
        case inputRevision = "input_revision"
        case reviewRevision = "review_revision"
        case deviceID = "device_id"
        case guestSecret = "guest_secret"
    }
}
