import AppCore
import CryptoKit
import Foundation

public enum MockMethod: String, Sendable, CaseIterable {
    case passkeyOptions, passkeyLogin, signIn, completeTwoFactor, signUp, requestPasswordReset, resetPassword
    case verificationStatus, resendVerificationEmail, verifyEmail, signOut, fetchIdentity, fetchAccount, fetchTrips,
        fetchTripDetail, send, searchAirports, reviewTrip, reviewTripEdit, saveTrip, updateTrip, tripInput
}

public actor MockDataSource: DataSource {
    public typealias AssertionProvider = @Sendable (ApiPasskeyAssertion, ApiPasskeyChallenge) -> String?
    private let store: any MockStateStore
    private let seed: MockServerState?
    private let now: @Sendable () -> Date
    private let delay: @Sendable () -> TimeInterval
    private let sleep: APIClient.Sleep
    private let id: @Sendable () -> String
    private let assertionProvider: AssertionProvider
    private let bearer: (@Sendable () async throws -> String?)?
    private var state: MockServerState?
    private var currentToken: String?
    private var requestToken: String?
    private var offline: Bool
    private let mutationsOffline: Bool
    private var failures: [MockMethod: DataFailure] = [:]

    public init(
        store: any MockStateStore = MemoryMockStateStore(), seed: MockServerState? = nil, offline: Bool = false,
        mutationsOffline: Bool = false,
        now: @escaping @Sendable () -> Date = { Date() },
        delay: @escaping @Sendable () -> TimeInterval = { Double.random(in: 0.3...0.8) },
        sleep: @escaping APIClient.Sleep = { try await Task.sleep(for: .seconds($0)) },
        id: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
        bearer: (@Sendable () async throws -> String?)? = nil,
        assertionProvider: @escaping AssertionProvider = { _, _ in nil }
    ) {
        self.store = store
        self.seed = seed
        self.offline = offline
        self.mutationsOffline = mutationsOffline
        self.now = now
        self.delay = delay
        self.sleep = sleep
        self.id = id
        self.bearer = bearer
        self.assertionProvider = assertionProvider
    }
    public func setOffline(_ offline: Bool) { self.offline = offline }
    public func failNext(method: MockMethod, error: DataFailure) { failures[method] = error }
    public func inbox() throws -> [MockMail] {
        try load()
        return state!.mail
    }

    private func load() throws {
        guard state == nil else { return }
        do {
            let restored: MockServerState?
            do {
                restored = try store.load()
            } catch is DecodingError where seed == nil {
                restored = nil
            }
            if let seed {
                state = restored ?? seed
                return
            }
            #if DEBUG
                if let restored, !restored.accounts.isEmpty,
                    restored.schemaVersion == MockServerState.currentSchemaVersion
                {
                    let refreshed = try MockAppSeed.refresh(restored, now: now())
                    if refreshed != restored { try store.save(refreshed) }
                    state = refreshed
                } else {
                    let initial = try MockAppSeed.make(now: now())
                    try store.save(initial)
                    state = initial
                }
            #else
                state = restored ?? MockServerState()
            #endif
        } catch {
            throw DataFailure.server(status: nil)
        }
    }
    private func begin(_ method: MockMethod) async throws {
        try Task.checkCancellation()
        try await sleep(min(0.8, max(0.3, delay())))
        try Task.checkCancellation()
        let token = try await bearer?()
        try Task.checkCancellation()
        if offline || (mutationsOffline && method == .send) { throw DataFailure.offline }
        if let failure = failures.removeValue(forKey: method) { throw failure }
        try load()
        requestToken = bearer == nil ? currentToken : token
    }
    private func update<T>(_ change: (inout MockServerState) throws -> T) throws -> T {
        var candidate = state!
        let result = try change(&candidate)
        do { try store.save(candidate) } catch { throw DataFailure.server(status: nil) }
        state = candidate
        return result
    }
    private func limit(_ key: String, count: Int = 5, seconds: TimeInterval = 60) throws {
        try update {
            try MockRateLimiter.hit(
                key, limit: count, seconds: seconds, now: now().timeIntervalSince1970, windows: &$0.rateWindows)
        }
    }
    private func validation(_ field: String, _ key: String, args: [String: JSONValue] = [:]) -> DataFailure {
        .validation(fields: [field: FieldMessage(key: key, arguments: args)], status: 422)
    }
    private func accountID(verified: Bool = false) throws -> String {
        let time = now().timeIntervalSince1970
        guard let token = requestToken, let session = state!.sessions[token], session.expiresAt > time,
            let account = state!.accounts[session.accountID]
        else { throw DataFailure.unauthorized(status: 401) }
        if verified && !account.snapshot.hasVerifiedEmail { throw DataFailure.emailUnverified(status: 403) }
        try update { $0.sessions[token]?.expiresAt = time + 90 * 86400 }
        return session.accountID
    }
    private func emailKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    private func find(email: String) -> String? {
        state!.accounts.first(where: { emailKey($0.value.snapshot.email) == emailKey(email) })?.key
    }
    private func device(_ deviceID: String, _ name: String) throws {
        guard UUID(uuidString: deviceID) != nil else {
            throw validation(
                "device_id", "The :attribute field must be a valid UUID.", args: ["attribute": .string("device_id")])
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw validation("device_name", "Please fill this in.")
        }
        guard name.unicodeScalars.count <= 255 else {
            throw validation("device_name", "Use no more than :max characters.", args: ["max": .number(255)])
        }
    }
    private func password(_ value: String, confirmation: String) throws {
        var fields: [String: FieldMessage] = [:]
        if value != confirmation {
            fields["password_confirmation"] = FieldMessage(key: "The passwords don't match yet.")
        }
        // Mock cannot query the production uncompromised-password service.
        if value.count < 12 {
            fields["password"] = FieldMessage(key: "Use at least :min characters.", arguments: ["min": .number(12)])
        } else if value.rangeOfCharacter(from: .uppercaseLetters) == nil
            || value.rangeOfCharacter(from: .lowercaseLetters) == nil
        {
            fields["password"] = FieldMessage(key: "Use both uppercase and lowercase letters.")
        } else if value.rangeOfCharacter(from: .decimalDigits) == nil {
            fields["password"] = FieldMessage(key: "Use at least one number.")
        } else if value.rangeOfCharacter(from: .symbols.union(.punctuationCharacters)) == nil {
            fields["password"] = FieldMessage(key: "Use at least one symbol.")
        }
        if !fields.isEmpty { throw DataFailure.validation(fields: fields, status: 422) }
    }
    private func authenticate(accountID: String, deviceID: String, draft: String? = nil, secret: String? = nil) throws
        -> SessionResult
    {
        let token = "mock-" + id()
        let account = state!.accounts[accountID]!
        var tripID: String?
        if let draft, let secret, let claim = state!.claims[draft], claim.secret == secret, claim.accountID == accountID
        {
            tripID = claim.tripID
        }
        try update {
            $0.sessions = $0.sessions.filter {
                !($0.value.accountID == accountID && $0.value.deviceID == deviceID.lowercased())
            }
            $0.sessions[token] = MockSession(
                accountID: accountID, deviceID: deviceID.lowercased(),
                expiresAt: now().timeIntervalSince1970 + 90 * 86400)
        }
        currentToken = token
        requestToken = token
        return SessionResult(token: token, account: account.identity, tripId: tripID)
    }
    public func signIn(_ input: PasswordSignInInput) async throws -> SignInResult {
        try await begin(.signIn)
        try limit("login:" + emailKey(input.email))
        try device(input.deviceID, input.deviceName)
        if emailKey(input.email).isEmpty { throw validation("email", "Please fill this in.") }
        if input.password.isEmpty { throw validation("password", "Please fill this in.") }
        guard let accountID = find(email: input.email), let account = state!.accounts[accountID],
            account.password == input.password
        else { throw validation("email", "These sign-in details don't match our records.") }
        if account.twoFactorCode != nil {
            let challenge = id().replacingOccurrences(of: "-", with: "") + id().replacingOccurrences(of: "-", with: "")
            try update {
                $0.twoFactor[challenge] = MockTwoFactor(
                    accountID: accountID, deviceID: input.deviceID, expiresAt: now().timeIntervalSince1970 + 300,
                    attempts: 0)
            }
            return .twoFactor(challengeId: challenge)
        }
        return .session(
            try authenticate(
                accountID: accountID, deviceID: input.deviceID, draft: input.draftToken, secret: input.guestSecret))
    }
    public func completeTwoFactor(_ input: TwoFactorInput) async throws -> SessionResult {
        try await begin(.completeTwoFactor)
        try limit("two-factor:" + input.challengeId)
        let value =
            switch input.proof {
            case .code(let value), .recoveryCode(let value): value
            }
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DataFailure.validation(
                fields: [
                    "code": FieldMessage(key: "Enter the 6-digit code from your authenticator app."),
                    "recovery_code": FieldMessage(
                        key: "Enter one of the recovery codes you saved when you set up two-factor authentication."),
                ], status: 422)
        }
        let field: String
        let key: String
        switch input.proof {
        case .code(let value):
            field = "code"
            guard value.count == 6, value.allSatisfy({ $0.isASCII && $0.isNumber }) else {
                throw validation(field, "Enter the 6-digit code from your authenticator app.")
            }
            key = "The authentication code was not accepted. Try again."
        case .recoveryCode:
            field = "recovery_code"
            key = "This recovery code was not accepted. Try another saved code."
        }
        guard let challenge = state!.twoFactor[input.challengeId], challenge.expiresAt > now().timeIntervalSince1970,
            let account = state!.accounts[challenge.accountID]
        else { throw validation(field, key) }
        let accepted: Bool
        switch input.proof {
        case .code(let value): accepted = value == account.twoFactorCode
        case .recoveryCode(let value): accepted = account.recoveryCodes.contains(value)
        }
        guard accepted else {
            try update {
                if challenge.attempts >= 4 {
                    $0.twoFactor.removeValue(forKey: input.challengeId)
                } else {
                    $0.twoFactor[input.challengeId]?.attempts += 1
                }
            }
            throw validation(field, key)
        }
        try update {
            $0.twoFactor.removeValue(forKey: input.challengeId)
            if case .recoveryCode(let code) = input.proof {
                $0.accounts[challenge.accountID]?.recoveryCodes.remove(code)
            }
        }
        return try authenticate(accountID: challenge.accountID, deviceID: challenge.deviceID)
    }
    public func signUp(_ input: RegisterInput) async throws -> SessionResult {
        try await begin(.signUp)
        try limit("registration")
        try device(input.deviceID, input.deviceName)
        guard !input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw validation("name", "Please fill this in.")
        }
        guard input.name.unicodeScalars.count <= 255 else {
            throw validation("name", "Use no more than :max characters.", args: ["max": .number(255)])
        }
        guard input.email.contains("@") else {
            throw validation("email", "Enter a valid email address, like name@example.com.")
        }
        guard find(email: input.email) == nil else {
            throw validation("email", "This email address is already in use.")
        }
        try password(input.password, confirmation: input.passwordConfirmation)
        let accountID = id()
        let snapshot = AccountSnapshot.mockRegistration(
            id: accountID, name: input.name, email: emailKey(input.email), language: input.language ?? .en, now: now())
        try update { $0.accounts[accountID] = MockServerAccount(snapshot: snapshot, password: input.password) }
        try sendVerification(accountID)
        return try authenticate(accountID: accountID, deviceID: input.deviceID)
    }
    public func requestPasswordReset(email: String) async throws {
        try await begin(.requestPasswordReset)
        try limit("forgot")
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw validation("email", "Please fill this in.")
        }
        guard email.contains("@") else {
            throw validation("email", "Enter a valid email address, like name@example.com.")
        }
        guard let accountID = find(email: email) else { return }
        let normalized = state!.accounts[accountID]!.snapshot.email
        let token = id()
        let time = now().timeIntervalSince1970
        try update {
            $0.resets[accountID] = MockReset(token: token, expiresAt: time + 3600)
            $0.mail.append(
                .passwordReset(
                    id: id(), to: normalized, sentAt: time,
                    input: ResetPasswordInput(token: token, email: normalized, password: "", passwordConfirmation: ""))
            )
        }
    }
    public func resetPassword(_ input: ResetPasswordInput) async throws {
        try await begin(.resetPassword)
        try limit("reset")
        try password(input.password, confirmation: input.passwordConfirmation)
        guard let accountID = find(email: input.email), let link = state!.resets[accountID], link.token == input.token,
            link.expiresAt > now().timeIntervalSince1970
        else { throw validation("token", "This password reset link is invalid or has expired.") }
        try update {
            $0.accounts[accountID]?.password = input.password
            $0.resets.removeValue(forKey: accountID)
            $0.sessions = $0.sessions.filter { $0.value.accountID != accountID }
            $0.twoFactor = $0.twoFactor.filter { $0.value.accountID != accountID }
        }
    }
    private func verification(_ accountID: String, identityOnly: Bool = false) -> EmailVerificationStatus {
        let account = state!.accounts[accountID]!
        return EmailVerificationStatus(
            email: account.snapshot.email, hasVerifiedEmail: account.snapshot.hasVerifiedEmail,
            resendAfterSeconds: identityOnly || account.snapshot.hasVerifiedEmail
                ? 0 : max(0, Int(ceil(account.resendAvailableAt - now().timeIntervalSince1970))))
    }
    public func verificationStatus() async throws -> EmailVerificationStatus {
        try await begin(.verificationStatus)
        return verification(try accountID(), identityOnly: true)
    }
    public func resendVerificationEmail() async throws -> EmailVerificationStatus {
        try await begin(.resendVerificationEmail)
        let accountID = try accountID()
        let status = verification(accountID)
        if status.resendAfterSeconds > 0 {
            throw DataFailure.throttled(retryAfterSeconds: Double(status.resendAfterSeconds), status: 429)
        }
        if !status.hasVerifiedEmail { try sendVerification(accountID) }
        return verification(accountID)
    }
    private func signature(id: String, hash: String, expires: Int) -> String {
        let url = "https://app.chronoflow.net/email/verify/\(id)/\(hash)?expires=\(expires)"
        return HMAC<SHA256>.authenticationCode(for: Data(url.utf8), using: SymmetricKey(data: state!.signingKey)).map {
            String(format: "%02x", $0)
        }.joined()
    }
    private func emailHash(_ email: String) -> String {
        Insecure.SHA1.hash(data: Data(email.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func sendVerification(_ accountID: String) throws {
        let email = state!.accounts[accountID]!.snapshot.email
        let expires = Int(now().timeIntervalSince1970) + 3600
        let hash = emailHash(email)
        let input = SignedVerificationInput(
            id: accountID, hash: hash, expires: expires,
            signature: signature(id: accountID, hash: hash, expires: expires))
        try update {
            $0.accounts[accountID]?.resendAvailableAt = now().timeIntervalSince1970 + 60
            $0.mail.append(.verification(id: id(), to: email, sentAt: now().timeIntervalSince1970, input: input))
        }
    }
    public func verifyEmail(_ input: SignedVerificationInput) async throws -> EmailVerificationStatus {
        try await begin(.verifyEmail)
        let accountID = try accountID()
        let account = state!.accounts[accountID]!
        guard input.id == accountID, input.hash == emailHash(account.snapshot.email),
            input.expires >= Int(now().timeIntervalSince1970),
            input.signature == signature(id: input.id, hash: input.hash, expires: input.expires)
        else { throw validation("signature", "This email verification link is invalid or has expired.") }
        try update { $0.accounts[accountID]?.snapshot.hasVerifiedEmail = true }
        return verification(accountID)
    }
    public func signOut() async throws {
        try await begin(.signOut)
        _ = try accountID()
        if let token = requestToken { try update { _ = $0.sessions.removeValue(forKey: token) } }
        currentToken = nil
        requestToken = nil
    }
    public func fetchIdentity() async throws -> AccountIdentity {
        try await begin(.fetchIdentity)
        return state!.accounts[try accountID()]!.identity
    }
    public func fetchAccount() async throws -> AccountSnapshot {
        try await begin(.fetchAccount)
        return state!.accounts[try accountID(verified: true)]!.snapshot
    }
    public func fetchTrips() async throws -> [TripListItem] {
        try await begin(.fetchTrips)
        return state!.accounts[try accountID(verified: true)]!.trips
    }
    public func fetchTripDetail(id: String) async throws -> TripDetailResponse {
        try await begin(.fetchTripDetail)
        guard let detail = state!.accounts[try accountID(verified: true)]!.details[id] else {
            throw DataFailure.server(status: 404)
        }
        return try TripDetailResponse(encoding: detail)
    }
    public func passkeyOptions() async throws -> ApiPasskeyChallenge {
        try await begin(.passkeyOptions)
        try limit("passkey-options", count: 10)
        let material = id() + id()
        let challengeID = SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
        let bytes = Data(SHA256.hash(data: Data(("challenge:" + material).utf8)))
        let challenge = bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(
            of: "/", with: "_"
        ).replacingOccurrences(of: "=", with: "")
        let result = ApiPasskeyChallenge(
            challengeId: challengeID,
            options: ApiPasskeyRequestOptions(challenge: challenge, rpId: "app.chronoflow.net", timeout: 60_000))
        try update {
            $0.passkeys[challengeID] = MockPasskey(challenge: result, expiresAt: now().timeIntervalSince1970 + 120)
        }
        return result
    }
    private func validateAssertion(_ credential: ApiPasskeyAssertion) throws {
        let r = credential.response
        let fields =
            [credential.id, credential.rawId, r.clientDataJSON, r.authenticatorData, r.signature]
            + (r.userHandle.map { [$0] } ?? [])
        let urlOnly = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let validURL: (String) -> Bool = {
            !$0.isEmpty && $0.unicodeScalars.allSatisfy(urlOnly.contains) && APIDataSource.base64URL($0) != nil
        }
        guard fields.allSatisfy({ $0.count <= 8192 }), validURL(credential.id), validURL(r.clientDataJSON),
            let raw = APIDataSource.base64URL(credential.rawId), !raw.isEmpty,
            raw == APIDataSource.base64URL(credential.id),
            let authenticator = APIDataSource.base64URL(r.authenticatorData), !authenticator.isEmpty,
            let signature = APIDataSource.base64URL(r.signature), !signature.isEmpty,
            r.userHandle == nil || r.userHandle == "" || APIDataSource.base64URL(r.userHandle!) != nil
        else {
            throw validation("credential", "We couldn't sign you in with that passkey. Please try again.")
        }
    }
    public func passkeyLogin(_ input: ApiPasskeyLoginInput) async throws -> SessionResult {
        try await begin(.passkeyLogin)
        let hash = SHA256.hash(data: Data(input.credential.id.utf8)).map { String(format: "%02x", $0) }.joined()
        try limit("passkey-login:" + hash)
        try limit("passkey-login-ip", count: 20)
        if let window = state!.rateWindows["passkey-failed:" + hash], window.expiresAt > now().timeIntervalSince1970,
            window.count >= 20
        {
            throw DataFailure.throttled(retryAfterSeconds: window.expiresAt - now().timeIntervalSince1970, status: 429)
        }
        do {
            try device(input.deviceID, input.deviceName)
            guard !input.challengeId.isEmpty else { throw validation("challengeId", "Please fill this in.") }
            guard input.challengeId.count <= 64 else {
                throw validation("challengeId", "Use no more than :max characters.", args: ["max": .number(64)])
            }
            for (field, value, maximum) in [
                ("draft_token", input.draftToken, 64), ("guest_secret", input.guestSecret, 128),
            ] {
                if let value, value.count > maximum {
                    throw validation(
                        field, "Use no more than :max characters.", args: ["max": .number(Decimal(maximum))])
                }
            }
            try validateAssertion(input.credential)
            guard let stored = state!.passkeys[input.challengeId], stored.expiresAt > now().timeIntervalSince1970 else {
                throw validation("challengeId", "The passkey request expired. Please try again.")
            }
            try update { _ = $0.passkeys.removeValue(forKey: input.challengeId) }
            guard let accountID = assertionProvider(input.credential, stored.challenge),
                state!.accounts[accountID] != nil
            else {
                throw validation("credential", "We couldn't sign you in with that passkey. Please try again.")
            }
            return try authenticate(
                accountID: accountID, deviceID: input.deviceID, draft: input.draftToken, secret: input.guestSecret)
        } catch let error as DataFailure {
            if case .validation = error { try limit("passkey-failed:" + hash, count: 20, seconds: 3600) }
            throw error
        }
    }
    public func send(_ change: OutboxChange) async throws -> MutationReceipt {
        try await begin(.send)
        if case .unsupported(let kind, _) = change { throw DataFailure.unsupported(kind) }
        let profile: Bool
        if case .profile = change { profile = true } else { profile = false }
        let accountID = try accountID(verified: !profile)
        switch change {
        case .profile(let input):
            guard !input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw validation("name", "Please fill this in.")
            }
            guard emailKey(input.email) == state!.accounts[accountID]!.snapshot.email else {
                throw validation("current_password", "Please fill this in.")
            }
            try update { $0.accounts[accountID]?.snapshot.name = input.name }
            return .identity(state!.accounts[accountID]!.identity)
        case .policies(let version):
            let policies = state!.accounts[accountID]!.snapshot.settings.policies
            guard version == policies.termsVersion else {
                throw validation("version", "The terms have changed. Read the current version and agree again.")
            }
            try update {
                $0.accounts[accountID]?.snapshot.settings.policies = AccountPolicies(
                    termsVersion: policies.termsVersion, privacyVersion: policies.privacyVersion,
                    acceptedTermsVersion: version, acceptedTermsAt: now().ISO8601Format())
            }
            return .acknowledged
        case .walkthrough:
            try update { $0.accounts[accountID]?.walkthroughSeen = true }
            return .acknowledged
        case .settings(let section, let patch):
            try MockSettings.validate(
                section: section, patch: patch, current: state!.accounts[accountID]!.snapshot.settings)
            try update {
                MockSettings.apply(patch, section: section, to: &$0.accounts[accountID]!.snapshot.settings)
                if section == .bodyClock {
                    let answers = $0.accounts[accountID]!.snapshot.settings.bodyClock
                    $0.accounts[accountID]?.snapshot.readiness = MockSettings.readiness(answers)
                }
            }
            return .account(state!.accounts[accountID]!.snapshot)
        case .checkOff(let input):
            guard (1...255).contains(input.ordinal) else {
                throw validation("ordinal", "This step cannot be checked off.")
            }
            guard input.localDate.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
                throw validation("local_date", "Choose a valid local date.")
            }
            guard var detail = state!.accounts[accountID]!.details[input.tripID] else {
                throw DataFailure.server(status: 404)
            }
            guard detail.checkState.planInputHash == input.planInputHash else {
                throw validation("form", "This plan has changed. Refresh it before marking this step.")
            }
            let key = CheckKey(type: input.type, localDate: input.localDate, ordinal: input.ordinal)
            let validKey = detail.plan.blocks.contains { $0.actionable && $0.checkKey == key }
            guard validKey else {
                throw validation("form", "This plan has changed. Refresh it before marking this step.")
            }
            if detail.checkState.marks.first(where: { $0.key == key })?.status == input.status {
                return .checks(TripCheckResult(checkState: detail.checkState, detailVersion: detail.detailVersion))
            }
            detail.checkState.marks.removeAll { $0.key == key }
            if let status = input.status {
                detail.checkState.marks.append(CheckMark(key: key, status: status, markedAt: now().ISO8601Format()))
            }
            detail.detailVersion = id()
            try update {
                $0.accounts[accountID]?.details[input.tripID] = detail
                if let index = $0.accounts[accountID]?.trips.firstIndex(where: { $0.card.id == input.tripID }
                ) {
                    $0.accounts[accountID]?.trips[index].checkState = detail.checkState
                    $0.accounts[accountID]?.trips[index].detailVersion = detail.detailVersion
                }
            }
            return .checks(TripCheckResult(checkState: detail.checkState, detailVersion: detail.detailVersion))
        case .unsupported(let kind, _): throw DataFailure.unsupported(kind)
        }
    }
}

extension MockDataSource {
    public func searchAirports(query: String, limit: Int? = nil) async throws -> [ApiAirportSuggestion] {
        try await begin(.searchAirports)
        let rawCount = query.count
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = limit ?? 8
        guard rawCount <= 60, (2...60).contains(query.count), (1...20).contains(count) else {
            throw validation((2...60).contains(query.count) ? "limit" : "query", "Choose one of the available options.")
        }
        return Array(
            try MockTripGeneration.airports().filter { airport in
                [airport.iata, airport.name, airport.city ?? "", airport.country].contains {
                    $0.localizedCaseInsensitiveContains(query)
                }
            }.prefix(count))
    }

    public func tripInput(id: String) async throws -> ApiTripInputSnapshot {
        try await begin(.tripInput)
        let owner = try accountID(verified: true)
        if let input = state!.wizardInputs?[owner + ":" + id] { return input }
        guard let detail = state!.accounts[owner]!.details[id] else { throw DataFailure.server(status: 404) }
        return try MockTripGeneration.snapshot(detail)
    }

    public func reviewTrip(_ input: ApiTripReviewInput) async throws -> ApiTripReview {
        try await begin(.reviewTrip)
        return try wizardReview(input, tripID: nil, sourceRevision: nil)
    }

    public func reviewTripEdit(_ input: ApiTripReviewInput, id: String, sourceRevision: String) async throws
        -> ApiTripReview
    {
        try await begin(.reviewTripEdit)
        return try wizardReview(input, tripID: id, sourceRevision: sourceRevision)
    }

    private func wizardReview(_ input: ApiTripReviewInput, tripID: String?, sourceRevision: String?) throws
        -> ApiTripReview
    {
        let owner = try accountID(verified: true)
        let time = now().timeIntervalSince1970
        try limit("review:" + owner, count: 30)
        if let tripID {
            guard state!.accounts[owner]?.details[tripID] != nil else { throw DataFailure.server(status: 404) }
            let revision =
                state!.wizardInputs?[owner + ":" + tripID]?.sourceRevision
                ?? state!.accounts[owner]!.details[tripID]?.plan.meta.inputHash
            guard revision == sourceRevision else {
                throw DataFailure.reviewExpired
            }
        }
        if let identity = input.identity {
            guard let previous = state!.wizardDrafts?[identity.token], previous.owner == owner,
                previous.tripID == tripID, previous.expiresAt > time,
                previous.review.identity.inputRevision == identity.inputRevision,
                previous.review.identity.reviewRevision == identity.reviewRevision
            else { throw DataFailure.reviewExpired }
        }
        var settings = state!.accounts[owner]!.snapshot.settings
        if let profile = input.profile, !profile.fields.isEmpty {
            do { try MockSettings.validate(section: .bodyClock, patch: profile, current: settings) } catch let failure
                as DataFailure
            {
                if case .validation(let fields, let status) = failure {
                    let prefixed = Dictionary(uniqueKeysWithValues: fields.map { ("profile." + $0.key, $0.value) })
                    throw TripWizardErrors.map(
                        .validation(fields: prefixed, status: status), outboundCount: input.input.outbound.legs.count)
                }
                throw failure
            }
            for (key, value) in profile.fields { settings.bodyClock[MockSettings.camel(key)] = value }
            if !Set(profile.fields.keys).isDisjoint(with: [
                "habitual_bed", "habitual_wake", "free_day_status", "free_day_bed", "free_day_wake", "chronotype",
            ]) {
                settings.sleepAnswered = true
            }
        }
        let identity = ApiReviewIdentity(
            token: input.identity?.token ?? id(), inputRevision: (input.identity?.inputRevision ?? 0) + 1,
            reviewRevision: (input.identity?.reviewRevision ?? 0) + 1, sourceRevision: sourceRevision)
        let review: ApiTripReview
        do {
            review = try MockTripGeneration.review(
                input.input, identity: identity, settings: settings, edit: tripID != nil,
                paidDirections: wizardPaidDirections(owner: owner, tripID: tripID))
        } catch let failure as DataFailure {
            throw TripWizardErrors.map(failure, outboundCount: input.input.outbound.legs.count)
        }
        try update { state in
            state.accounts[owner]!.snapshot.settings = settings
            state.accounts[owner]!.snapshot.readiness = MockSettings.readiness(settings.bodyClock)
            var drafts = state.wizardDrafts ?? [:]
            drafts = drafts.filter { $0.value.expiresAt > time }
            drafts[identity.token] = MockWizardDraft(
                owner: owner, tripID: tripID, input: input.input, review: review, profile: settings.bodyClock,
                expiresAt: time + 1800)
            state.wizardDrafts = drafts
        }
        return review
    }

    public func saveTrip(identity: ApiTripSaveInput) async throws -> ApiTripSaveResult {
        try await begin(.saveTrip)
        return try wizardSave(identity, tripID: nil, sourceRevision: nil)
    }

    public func updateTrip(id: String, identity: ApiTripSaveInput, sourceRevision: String) async throws
        -> ApiTripSaveResult
    {
        try await begin(.updateTrip)
        return try wizardSave(identity, tripID: id, sourceRevision: sourceRevision)
    }

    private func wizardSave(_ identity: ApiTripSaveInput, tripID: String?, sourceRevision: String?) throws
        -> ApiTripSaveResult
    {
        let owner = try accountID(verified: true)
        let time = now().timeIntervalSince1970
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let intent =
            String(decoding: try encoder.encode(identity), as: UTF8.self) + ":" + (tripID ?? "") + ":"
            + (sourceRevision ?? "")
        let key = owner + ":" + identity.draftToken
        if let receipt = state!.wizardReceipts?[key], receipt.expiresAt > time {
            guard receipt.intent == intent, state!.accounts[owner]!.details[receipt.tripID] != nil else {
                throw DataFailure.reviewExpired
            }
            return ApiTripSaveResult(tripId: receipt.tripID)
        }
        guard let draft = state!.wizardDrafts?[identity.draftToken], draft.owner == owner,
            draft.tripID == tripID, draft.expiresAt > time,
            draft.review.identity.inputRevision == identity.inputRevision,
            draft.review.identity.reviewRevision == identity.reviewRevision,
            draft.profile == state!.accounts[owner]!.snapshot.settings.bodyClock,
            draft.review.status == .ok || draft.review.status == .modified
        else { throw DataFailure.reviewExpired }
        if let tripID {
            let revision =
                state!.wizardInputs?[owner + ":" + tripID]?.sourceRevision
                ?? state!.accounts[owner]!.details[tripID]?.plan.meta.inputHash
            guard revision == sourceRevision,
                draft.review.identity.sourceRevision == sourceRevision
            else { throw DataFailure.reviewExpired }
        }
        let settings = state!.accounts[owner]!.snapshot.settings
        let currentReview = try MockTripGeneration.review(
            draft.input, identity: draft.review.identity, settings: settings, edit: tripID != nil,
            paidDirections: wizardPaidDirections(owner: owner, tripID: tripID))
        guard currentReview.canSave else { throw DataFailure.notEnoughCredits }
        try limit("trip-save:" + owner, count: 10)
        let id = tripID ?? identity.draftToken
        let (item, detail, input) = try MockTripGeneration.saved(draft, tripID: id)
        let previousPaid = wizardPaidDirections(owner: owner, tripID: tripID)
        try update { state in
            state.accounts[owner]!.trips.removeAll { $0.card.id == id }
            state.accounts[owner]!.trips.append(item)
            state.accounts[owner]!.details[id] = detail
            state.accounts[owner]!.snapshot.settings.planCredits["credits"] = .number(
                Decimal(currentReview.price.balance - currentReview.price.cost))
            var receipts = state.wizardReceipts ?? [:]
            receipts[key] = MockWizardReceipt(intent: intent, tripID: id, expiresAt: time + 86400)
            state.wizardReceipts = receipts
            state.wizardDrafts?[identity.draftToken] = nil
            var inputs = state.wizardInputs ?? [:]
            inputs[owner + ":" + id] = input
            state.wizardInputs = inputs
            var paid = state.wizardPaidDirections ?? [:]
            let directions: [TripDirection] = draft.input.return == nil ? [.outbound] : [.outbound, .return]
            paid[owner + ":" + id] = Array(
                Set(previousPaid + directions.filter { !currentReview.price.freeDirections.contains($0) }))
            state.wizardPaidDirections = paid
        }
        return ApiTripSaveResult(tripId: id)
    }
    private func wizardPaidDirections(owner: String, tripID: String?) -> [TripDirection] {
        guard let tripID else { return [] }
        if let paid = state!.wizardPaidDirections?[owner + ":" + tripID] { return paid }
        let hasReturn = state!.accounts[owner]?.details[tripID]?.trip.legs.contains { $0.returnLeg } ?? false
        return hasReturn ? [.outbound, .return] : [.outbound]
    }

}
