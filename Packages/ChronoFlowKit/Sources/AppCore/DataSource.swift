public protocol DataSource: Sendable {
    func passkeyOptions() async throws -> ApiPasskeyChallenge
    func passkeyLogin(_ input: ApiPasskeyLoginInput) async throws -> SessionResult
    func signIn(_ input: PasswordSignInInput) async throws -> SignInResult
    func completeTwoFactor(_ input: TwoFactorInput) async throws -> SessionResult
    func signUp(_ input: RegisterInput) async throws -> SessionResult
    func requestPasswordReset(email: String) async throws
    func resetPassword(_ input: ResetPasswordInput) async throws
    func verificationStatus() async throws -> EmailVerificationStatus
    func resendVerificationEmail() async throws -> EmailVerificationStatus
    func verifyEmail(_ input: SignedVerificationInput) async throws -> EmailVerificationStatus
    func signOut() async throws
    func deleteAccount(password: String) async throws
    func accountSecurity(_ change: AccountSecurityChange) async throws -> AccountSecurityResult
    func fetchIdentity() async throws -> AccountIdentity
    func fetchAccount() async throws -> AccountSnapshot
    func fetchTrips() async throws -> [TripListItem]
    func fetchTripDetail(id: String) async throws -> TripDetailResponse
    func searchAirports(query: String, limit: Int?) async throws -> [ApiAirportSuggestion]
    func reviewTrip(_ input: ApiTripReviewInput) async throws -> ApiTripReview
    func reviewGuestTrip(_ input: ApiGuestTripReviewInput) async throws -> ApiTripReview
    func reviewTripEdit(_ input: ApiTripReviewInput, id: String, sourceRevision: String) async throws -> ApiTripReview
    func saveTrip(identity: ApiTripSaveInput) async throws -> ApiTripSaveResult
    func updateTrip(id: String, identity: ApiTripSaveInput, sourceRevision: String) async throws -> ApiTripSaveResult
    func tripInput(id: String) async throws -> ApiTripInputSnapshot
    func send(_ change: OutboxChange) async throws -> MutationReceipt
}

extension DataSource {
    public func reviewGuestTrip(_ input: ApiGuestTripReviewInput) async throws -> ApiTripReview {
        throw DataFailure.unsupported(.profile)
    }

    public func deleteAccount(password: String) async throws { throw DataFailure.unsupported(.security) }

    public func accountSecurity(_ change: AccountSecurityChange) async throws -> AccountSecurityResult {
        throw DataFailure.unsupported(.security)
    }
}
