import AppCore
import DataAccess
import Foundation
import TripWizard

actor GenerationSource: DataSource {
    let mock: MockDataSource?
    let reviewValue: ApiTripReview
    var counts: [String: Int] = [:]
    var reviewFailure: DataFailure?
    var saveFailure: DataFailure?
    var lastEdit: TripEditContext?
    var beforeReview: @Sendable () async throws -> Void = {}
    var beforeSave: @Sendable () async throws -> Void = {}
    var waiters: [(String, Int, CheckedContinuation<Void, Never>)] = []
    init(mock: MockDataSource? = nil) throws {
        self.mock = mock
        reviewValue = try generationReview()
    }
    func configure(
        reviewFailure: DataFailure? = nil, saveFailure: DataFailure? = nil,
        beforeReview: @escaping @Sendable () async throws -> Void = {},
        beforeSave: @escaping @Sendable () async throws -> Void = {}
    ) {
        self.reviewFailure = reviewFailure
        self.saveFailure = saveFailure
        self.beforeReview = beforeReview
        self.beforeSave = beforeSave
    }
    func count(_ method: String) -> Int { counts[method, default: 0] }
    func record(_ method: String) {
        counts[method, default: 0] += 1
        let ready = waiters.filter { $0.0 == method && $0.1 <= counts[method, default: 0] }
        waiters.removeAll { $0.0 == method && $0.1 <= counts[method, default: 0] }
        for waiter in ready { waiter.2.resume() }
    }
    func waitForReviews(_ count: Int) async { await waitFor("review", count: count) }
    func waitForSaves(_ count: Int) async { await waitFor("save", count: count) }
    private func waitFor(_ method: String, count: Int) async {
        if counts[method, default: 0] >= count { return }
        await withCheckedContinuation { waiters.append((method, count, $0)) }
    }
    func reviewTrip(_ input: ApiTripReviewInput) async throws -> ApiTripReview {
        record("review")
        try await beforeReview()
        if let reviewFailure { throw reviewFailure }
        if let mock { return try await mock.reviewTrip(input) }
        return reviewValue
    }
    func reviewTripEdit(_ input: ApiTripReviewInput, id: String, sourceRevision: String) async throws -> ApiTripReview {
        lastEdit = TripEditContext(tripID: id, sourceRevision: sourceRevision)
        return try await reviewTrip(input)
    }
    func saveTrip(identity: ApiTripSaveInput) async throws -> ApiTripSaveResult {
        record("save")
        try await beforeSave()
        if let saveFailure { throw saveFailure }
        if let mock { return try await mock.saveTrip(identity: identity) }
        return ApiTripSaveResult(tripId: "created")
    }
    func updateTrip(id: String, identity: ApiTripSaveInput, sourceRevision: String) async throws -> ApiTripSaveResult {
        record("update")
        lastEdit = TripEditContext(tripID: id, sourceRevision: sourceRevision)
        return ApiTripSaveResult(tripId: id)
    }
    func fetchTrips() async throws -> [TripListItem] {
        record("trips")
        return try await mock!.fetchTrips()
    }
    func fetchTripDetail(id: String) async throws -> TripDetailResponse {
        record("detail")
        return try await mock!.fetchTripDetail(id: id)
    }
    func searchAirports(query: String, limit: Int?) throws -> [ApiAirportSuggestion] {
        throw DataFailure.server(status: nil)
    }
    func tripInput(id: String) throws -> ApiTripInputSnapshot { throw DataFailure.server(status: nil) }
    func passkeyOptions() throws -> ApiPasskeyChallenge { throw DataFailure.server(status: nil) }
    func passkeyLogin(_ input: ApiPasskeyLoginInput) throws -> SessionResult { throw DataFailure.server(status: nil) }
    func signIn(_ input: PasswordSignInInput) throws -> SignInResult { throw DataFailure.server(status: nil) }
    func completeTwoFactor(_ input: TwoFactorInput) throws -> SessionResult { throw DataFailure.server(status: nil) }
    func signUp(_ input: RegisterInput) throws -> SessionResult { throw DataFailure.server(status: nil) }
    func requestPasswordReset(email: String) throws { throw DataFailure.server(status: nil) }
    func resetPassword(_ input: ResetPasswordInput) throws { throw DataFailure.server(status: nil) }
    func verificationStatus() throws -> EmailVerificationStatus { throw DataFailure.server(status: nil) }
    func resendVerificationEmail() throws -> EmailVerificationStatus { throw DataFailure.server(status: nil) }
    func verifyEmail(_ input: SignedVerificationInput) throws -> EmailVerificationStatus {
        throw DataFailure.server(status: nil)
    }
    func signOut() throws { throw DataFailure.server(status: nil) }
    func fetchIdentity() throws -> AccountIdentity { throw DataFailure.server(status: nil) }
    func fetchAccount() throws -> AccountSnapshot { throw DataFailure.server(status: nil) }
    func send(_ change: OutboxChange) throws -> MutationReceipt { throw DataFailure.server(status: nil) }
}
