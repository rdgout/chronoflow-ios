public struct GuestClaim: Sendable, Equatable {
    public let draftToken: String
    public let inputRevision: Int
    public let reviewRevision: Int
    public let guestSecret: String

    public init(draftToken: String, inputRevision: Int, reviewRevision: Int, guestSecret: String) {
        self.draftToken = draftToken
        self.inputRevision = inputRevision
        self.reviewRevision = reviewRevision
        self.guestSecret = guestSecret
    }
}
