import AppCore
import Foundation
import Testing

@testable import DataAccess

@Suite struct MockPasskeyManagementTests {
    private func state() throws -> MockServerState {
        var state = try scenarioState()
        state.accounts[demoID]?.passkeys = [
            ApiPasskey(id: 1, name: "iPhone 16", createdAt: "2026-09-14T08:00:00Z", lastUsedAt: "2026-11-02T08:00:00Z"),
            ApiPasskey(id: 2, name: "MacBook Pro", createdAt: "2026-10-02T08:00:00Z"),
        ]
        state.accounts[demoID]?.snapshot.security["passkeyCount"] = .number(2)
        return state
    }

    private func attestation(for challenge: ApiPasskeyRegistrationChallenge) -> ApiPasskeyAttestation {
        ApiPasskeyAttestation(
            id: "AQID", rawId: "AQID",
            response: ApiPasskeyAttestationResponse(
                clientDataJSON: challenge.options.challenge, attestationObject: "YXR0", transports: ["internal"]))
    }

    private func options(_ source: MockDataSource, password: String = fixturePassword) async throws
        -> ApiPasskeyRegistrationChallenge
    {
        guard
            case .passkeyCreation(let challenge) = try await source.accountSecurity(
                .passkeyCreationOptions(current: password))
        else {
            throw DataFailure.server(status: nil)
        }
        return challenge
    }

    private func list(_ source: MockDataSource) async throws -> [ApiPasskey] {
        guard case .passkeys(let list) = try await source.accountSecurity(.listPasskeys) else {
            throw DataFailure.server(status: nil)
        }
        return list
    }

    @Test func listReturnsPersistedPasskeysAndAnAccountWithoutAnyIsEmpty() async throws {
        let source = try mockSource(seed: state())
        _ = try await login(source)
        #expect(try await list(source).map(\.name) == ["iPhone 16", "MacBook Pro"])
        let bare = try mockSource()
        _ = try await login(bare)
        #expect(try await list(bare).isEmpty)
    }

    @Test func addRegistersOnceReturnsTheItemAndKeepsTheCountInTheSecuritySummary() async throws {
        let source = try mockSource(seed: state())
        _ = try await login(source)
        let challenge = try await options(source)
        #expect(challenge.options.rp.id == "app.chronoflow.net" && !challenge.options.user.name.isEmpty)
        #expect(challenge.challengeId.count == 64 && challenge.options.excludeCredentials.isEmpty)
        let input = ApiPasskeyRegistrationInput(
            challengeId: challenge.challengeId, name: " This phone ", credential: attestation(for: challenge))
        guard case .passkeyAdded(let added) = try await source.accountSecurity(.addPasskey(input)) else {
            Issue.record("Expected the new passkey")
            return
        }
        #expect(added.name == "This phone" && added.id == 3 && added.lastUsedAt == nil)
        #expect(try await list(source).map(\.name) == ["This phone", "iPhone 16", "MacBook Pro"])
        #expect(try await source.fetchAccount().security["passkeyCount"]?.int == 3)
        await #expect(throws: DataFailure.self) { try await source.accountSecurity(.addPasskey(input)) }
        #expect(try await list(source).count == 3)
        #expect(try await options(source).options.excludeCredentials.map(\.id) == ["AQID"])
    }

    @Test func aWrongPasswordFailsAtOptionsAndIssuesNoChallenge() async throws {
        let source = try mockSource(seed: state())
        _ = try await login(source)
        await #expect(
            throws: DataFailure.validation(
                fields: ["current_password": FieldMessage(key: "The provided password was incorrect.")], status: 422)
        ) { try await options(source, password: "wrong") }
    }

    @Test(arguments: ["challenge", "expired", "attestation", "padded", "duplicate", "name", "long"])
    func addRejectsEachBadInputWithoutRegistering(_ fault: String) async throws {
        let clock = MockClock()
        let source = try mockSource(clock: clock, seed: state())
        _ = try await login(source)
        if fault == "duplicate" {
            let first = try await options(source)
            let input = ApiPasskeyRegistrationInput(
                challengeId: first.challengeId, name: "One", credential: attestation(for: first))
            _ = try await source.accountSecurity(.addPasskey(input))
        }
        let challenge = try await options(source)
        var credential = attestation(for: challenge)
        var input = ApiPasskeyRegistrationInput(
            challengeId: challenge.challengeId, name: "Phone", credential: credential)
        switch fault {
        case "challenge": input.challengeId = "unknown"
        case "expired": clock.advance(121)
        case "attestation":
            credential.response.attestationObject = "not base64url!"
            input.credential = credential
        case "padded":
            credential.id = "AQID="
            input.credential = credential
        case "duplicate": break
        case "long": input.name = String(repeating: "a", count: 256)
        default: input.name = "  "
        }
        let before = try await list(source).count
        do {
            _ = try await source.accountSecurity(.addPasskey(input))
            Issue.record("Expected a validation failure")
        } catch let failure as DataFailure {
            guard case .validation(let fields, 422) = failure else {
                Issue.record("Unexpected \(failure)")
                return
            }
            switch fault {
            case "name": #expect(fields["name"]?.key == "Please fill this in.")
            case "long":
                #expect(
                    fields["name"]
                        == FieldMessage(key: "Use no more than :max characters.", arguments: ["max": .number(255)]))
            case "challenge", "expired":
                #expect(fields["challengeId"]?.key == "The passkey registration request expired. Please try again.")
            default: #expect(fields["credential"]?.key == "We couldn't register that passkey. Please try again.")
            }
        }
        #expect(try await list(source).count == before)
    }

    @Test func aFieldFailureKeepsTheChallengeButAFailedCredentialConsumesIt() async throws {
        let source = try mockSource(seed: state())
        _ = try await login(source)
        let challenge = try await options(source)
        var input = ApiPasskeyRegistrationInput(
            challengeId: challenge.challengeId, name: "", credential: attestation(for: challenge))
        await #expect(throws: DataFailure.self) { try await source.accountSecurity(.addPasskey(input)) }
        input.name = "Phone"
        input.credential.response.attestationObject = "not base64url!"
        await #expect(throws: DataFailure.self) { try await source.accountSecurity(.addPasskey(input)) }
        input.credential = attestation(for: challenge)
        do {
            _ = try await source.accountSecurity(.addPasskey(input))
            Issue.record("Expected the consumed challenge to fail")
        } catch let failure as DataFailure {
            guard case .validation(let fields, 422) = failure else {
                Issue.record("Unexpected \(failure)")
                return
            }
            #expect(fields["challengeId"] != nil)
        }
    }

    @Test func removeNeedsThePasswordAndRevokesOnlyTheOtherSessions() async throws {
        let store = MemoryMockStateStore()
        let source = try mockSource(store: store, seed: state())
        _ = try await login(source, device: "0199a3c0-0000-7000-8000-0000000000a1")
        let other = try await login(source, device: "0199a3c0-0000-7000-8000-0000000000b2")
        #expect(other.account.id == demoID)
        #expect(store.load()?.sessions.count == 2)
        await #expect(
            throws: DataFailure.validation(
                fields: ["current_password": FieldMessage(key: "The provided password was incorrect.")], status: 422)
        ) {
            try await source.accountSecurity(.removePasskey(id: 1, current: "wrong"))
        }
        #expect(try await list(source).count == 2)
        #expect(try await source.accountSecurity(.removePasskey(id: 1, current: fixturePassword)) == .changed)
        #expect(try await list(source).map(\.id) == [2])
        #expect(try await source.fetchAccount().security["passkeyCount"]?.int == 1)
        #expect(store.load()?.sessions.count == 1)
        for password in [fixturePassword, "wrong"] {
            await #expect(throws: DataFailure.server(status: 404)) {
                try await source.accountSecurity(.removePasskey(id: 99, current: password))
            }
        }
    }

    @Test func passkeyCallsHonourOfflineInjectedFailuresAndTheCredentialLimiter() async throws {
        let source = try mockSource(seed: state())
        _ = try await login(source)
        await source.setOffline(true)
        await #expect(throws: DataFailure.offline) { try await source.accountSecurity(.listPasskeys) }
        await source.setOffline(false)
        await source.failNext(method: .accountSecurity, error: .server(status: 503))
        await #expect(throws: DataFailure.server(status: 503)) { try await source.accountSecurity(.listPasskeys) }
        for _ in 0..<6 { _ = try await options(source) }
        do {
            _ = try await options(source)
            Issue.record("Expected the limiter")
        } catch let failure as DataFailure {
            guard case .throttled = failure else {
                Issue.record("Unexpected \(failure)")
                return
            }
        }
        #expect(try await list(source).count == 2)
    }
}
