import GRDB

public struct DraftRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static var databaseTableName: String { "drafts" }

    public var id: String
    public var tripId: String?
    public var form: JSONDocument
    public var baseForm: JSONDocument?
    public var dirty: Bool
    public var review: JSONDocument?
    public var token: String?
    public var inputRevision: Int
    public var reviewRevision: Int?
    public var wizardSourceRevision: String?
    public var wizardReview: JSONDocument?
    public var furthestStep: String?
    public var wizardState: JSONDocument?
    public var sourceRevision: JSONDocument?
    public var saveFailure: JSONDocument?
    public var fieldErrors: JSONDocument?
    public var updatedAt: String

    public init(
        id: String, tripId: String? = nil, form: JSONDocument, baseForm: JSONDocument? = nil, dirty: Bool = true,
        review: JSONDocument? = nil, token: String? = nil, inputRevision: Int = 0, reviewRevision: Int? = nil,
        wizardSourceRevision: String? = nil, wizardReview: JSONDocument? = nil, furthestStep: String? = nil,
        wizardState: JSONDocument? = nil, sourceRevision: JSONDocument? = nil, saveFailure: JSONDocument? = nil,
        fieldErrors: JSONDocument? = nil, updatedAt: String
    ) {
        self.id = id
        self.tripId = tripId
        self.form = form
        self.baseForm = baseForm
        self.dirty = dirty
        self.review = review
        self.token = token
        self.inputRevision = inputRevision
        self.reviewRevision = reviewRevision
        self.wizardSourceRevision = wizardSourceRevision
        self.wizardReview = wizardReview
        self.furthestStep = furthestStep
        self.wizardState = wizardState
        self.sourceRevision = sourceRevision
        self.saveFailure = saveFailure
        self.fieldErrors = fieldErrors
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case tripId = "trip_id"
        case form = "form"
        case baseForm = "base_form"
        case dirty = "dirty"
        case review = "review"
        case token = "token"
        case inputRevision = "input_revision"
        case reviewRevision = "review_revision"
        case wizardSourceRevision = "wizard_source_revision"
        case wizardReview = "wizard_review"
        case furthestStep = "furthest_step"
        case wizardState = "wizard_state"
        case sourceRevision = "source_revision"
        case saveFailure = "save_failure"
        case fieldErrors = "field_errors"
        case updatedAt = "updated_at"
    }
}
