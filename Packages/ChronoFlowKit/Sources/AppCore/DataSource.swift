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
    func fetchIdentity() async throws -> AccountIdentity
    func fetchAccount() async throws -> AccountSnapshot
    func fetchTrips() async throws -> [TripListItem]
    func fetchTripDetail(id: String) async throws -> TripDetailResponse
    func send(_ change: OutboxChange) async throws -> MutationReceipt
}
