import Foundation

public typealias ApiTripPrice = ApiReviewPrice
public typealias ApiTripItinerary = ApiReviewItinerary

public struct ApiTripReviewInput: Encodable, Sendable, Equatable {
    public var input: ApiTripInput
    public var identity: ApiReviewIdentity?
    public var profile: JSONObject?

    public init(input: ApiTripInput, identity: ApiReviewIdentity? = nil, profile: JSONObject? = nil) {
        self.input = input
        self.identity = identity
        self.profile = profile
    }

    enum CodingKeys: String, CodingKey {
        case draftToken = "draft_token"
        case inputRevision = "input_revision"
        case reviewRevision = "review_revision"
        case sourceRevision = "source_revision"
        case profile
    }

    public func encode(to encoder: any Encoder) throws {
        try input.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identity?.token, forKey: .draftToken)
        try container.encode(identity?.inputRevision ?? 0, forKey: .inputRevision)
        try container.encode(identity?.reviewRevision, forKey: .reviewRevision)
        try container.encodeIfPresent(identity?.sourceRevision, forKey: .sourceRevision)
        try container.encodeIfPresent(profile.map(ProfilePreferences.request), forKey: .profile)
    }
}

public struct ApiTripSaveInput: Codable, Sendable, Equatable, Hashable {
    public let draftToken: String
    public let inputRevision: Int
    public let reviewRevision: Int

    public init(identity: ApiReviewIdentity) throws {
        guard !identity.token.isEmpty, identity.inputRevision > 0, let revision = identity.reviewRevision,
            revision > 0
        else { throw DataFailure.reviewExpired }
        draftToken = identity.token
        inputRevision = identity.inputRevision
        reviewRevision = revision
    }

    enum CodingKeys: String, CodingKey {
        case draftToken = "draft_token"
        case inputRevision = "input_revision"
        case reviewRevision = "review_revision"
    }
}
