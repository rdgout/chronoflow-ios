import AppCore
import Foundation

@testable import DataAccess

let demoID = MockScenarioValues.demoID
let twoFactorID = MockScenarioValues.twoFactorID
let demoTripID = "0199a3c0-0000-7000-8000-000000000010"
let mockDeviceID = "0199a3c0-0000-7000-8000-000000000100"
let fixturePassword = MockScenarioValues.password
let fixtureRecovery = MockScenarioValues.recoveryCode
let newPassword = "NewPassword12!"

final class MockClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time = Date(timeIntervalSince1970: 1_793_923_200)
    private var sequence = 200
    private var recordedDelays: [Double] = []
    func now() -> Date { lock.withLock { time } }
    func advance(_ seconds: Double) { lock.withLock { time += seconds } }
    func id() -> String {
        lock.withLock {
            sequence += 1
            return String(format: "0199a3c0-0000-7000-8000-%012d", sequence)
        }
    }
    func sleep(_ delay: Double) async throws {
        try Task.checkCancellation()
        lock.withLock { recordedDelays.append(delay) }
    }
    var delays: [Double] { lock.withLock { recordedDelays } }
}

func scenarioState() throws -> MockServerState {
    let decoder = JSONDecoder()
    let snapshot = try decoder.decode(AccountSnapshot.self, from: fixture("account/snapshot.json"))
    struct List: Decodable { let trips: [TripListItem] }
    let trips = try decoder.decode(List.self, from: fixture("trips/list.json")).trips
    let detail = try decoder.decode(TripDetail.self, from: fixture("trips/detail.json"))
    let demo = MockServerAccount(
        snapshot: snapshot, password: fixturePassword, trips: trips, details: [demoTripID: detail])
    var otherSnapshot = snapshot
    otherSnapshot.id = twoFactorID
    otherSnapshot.email = MockScenarioValues.twoFactorEmail
    let other = MockServerAccount(
        snapshot: otherSnapshot, password: fixturePassword, twoFactorCode: MockScenarioValues.twoFactorCode,
        recoveryCodes: [fixtureRecovery])
    return MockServerState(accounts: [demo, other], signingKey: Data("artificial-mock-signing-key".utf8))
}

func mockSource(
    clock: MockClock = MockClock(), store: any MockStateStore = MemoryMockStateStore(), seed: MockServerState? = nil,
    bearer: (@Sendable () async throws -> String?)? = nil
) throws -> MockDataSource {
    MockDataSource(
        store: store, seed: try seed ?? scenarioState(), now: clock.now, delay: { 0.5 }, sleep: clock.sleep,
        id: clock.id, bearer: bearer,
        assertionProvider: { assertion, challenge in
            guard assertion.response.signature == "c2ln",
                assertion.response.clientDataJSON == challenge.options.challenge
            else { return nil }
            switch assertion.id {
            case "AA": return demoID
            case "AQ": return twoFactorID
            default: return nil
            }
        })
}
func passwordInput(
    email: String = MockScenarioValues.demoEmail, password: String = fixturePassword, device: String = mockDeviceID
) -> PasswordSignInInput {
    PasswordSignInInput(email: email, password: password, deviceID: device, deviceName: "iPhone")
}
func login(_ source: any DataSource, email: String = MockScenarioValues.demoEmail, device: String = mockDeviceID)
    async throws
    -> SessionResult
{
    guard case .session(let session) = try await source.signIn(passwordInput(email: email, device: device)) else {
        throw DataFailure.server(status: nil)
    }
    return session
}
func passkeyInput(_ challenge: ApiPasskeyChallenge, credentialID: String = "AA", signature: String = "c2ln")
    -> ApiPasskeyLoginInput
{
    ApiPasskeyLoginInput(
        challengeId: challenge.challengeId,
        credential: ApiPasskeyAssertion(
            id: credentialID, rawId: credentialID == "AA" ? "AA==" : "AQ==",
            response: ApiPasskeyAssertionResponse(
                clientDataJSON: challenge.options.challenge, authenticatorData: "AA==", signature: signature)),
        deviceID: mockDeviceID, deviceName: "iPhone")
}
func registration(_ email: String = "new@example.com") -> RegisterInput {
    RegisterInput(
        name: "New Traveller", email: email, password: newPassword, passwordConfirmation: newPassword,
        deviceID: mockDeviceID, deviceName: "iPhone", language: .nl)
}
