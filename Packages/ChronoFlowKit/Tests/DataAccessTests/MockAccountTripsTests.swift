import AppCore
import Foundation
import Testing

@testable import DataAccess

@Suite struct MockAccountTripsTests {
    @Test func readsIsolationAndSupportedMutations() async throws {
        let source = try mockSource()
        _ = try await login(source)
        let snapshot = try await source.fetchAccount()
        #expect(snapshot.id == demoID)
        #expect(try await source.fetchTrips().count == 1)
        #expect(
            try await source.fetchTripDetail(id: demoTripID).checkState.planInputHash
                == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        #expect(
            try await source.send(.profile(ProfileChange(name: "Changed", email: "demo@example.com")))
                == .identity(
                    AccountIdentity(
                        id: demoID, name: "Changed", email: "demo@example.com", hasVerifiedEmail: true,
                        policies: snapshot.settings.policies, walkthroughSeen: false)))
        _ = try await source.send(.walkthrough)
        #expect(try await source.fetchIdentity().walkthroughSeen)
        _ = try await source.send(.policies(version: "1.0"))
        #expect(try await source.fetchIdentity().policies.acceptedTermsAt != nil)
        for (section, patch, responseKey) in [
            (SettingsSection.preferences, JSONObject(["time_format": .string("12")]), "timeFormat"),
            (.reminders, JSONObject(["lead_min": .number(15)]), "leadMin"),
            (.bodyClock, JSONObject(["habitual_bed": .string("22:00")]), "habitualBed"),
        ] {
            guard case .account(let result) = try await source.send(.settings(section: section, patch: patch)) else {
                Issue.record("Expected account")
                return
            }
            switch section {
            case .preferences: #expect(result.settings.preferences[responseKey] == .string("12"))
            case .reminders: #expect(result.settings.reminders[responseKey] == .number(15))
            case .bodyClock: #expect(result.settings.bodyClock[responseKey] == .string("22:00"))
            }
        }
        _ = try await source.signIn(passwordInput(email: "twofactor@example.com"))
        let options = try await source.passkeyOptions()
        _ = try await source.passkeyLogin(passkeyInput(options, credentialID: "AQ"))
        #expect(try await source.fetchTrips().isEmpty)
        #expect(try await source.fetchIdentity().name == "Demo Traveller")
        await #expect(throws: DataFailure.server(status: 404)) { try await source.fetchTripDetail(id: demoTripID) }
        try await source.signOut()
        await #expect(throws: DataFailure.unauthorized(status: 401)) { try await source.fetchIdentity() }
    }
    @Test func absoluteChecksClearAndStaleHash() async throws {
        let source = try mockSource()
        _ = try await login(source)
        var change = CheckOffChange(
            tripID: demoTripID, planInputHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            type: .sleep, localDate: "2026-11-10", ordinal: 1, status: .done)
        _ = try await source.send(.checkOff(change))
        _ = try await source.send(.checkOff(change))
        #expect(try await source.fetchTripDetail(id: demoTripID).checkState.marks.count == 1)
        change.status = nil
        _ = try await source.send(.checkOff(change))
        #expect(try await source.fetchTripDetail(id: demoTripID).checkState.marks.isEmpty)
        change.planInputHash = "stale"
        await #expect(
            throws: DataFailure.validation(
                fields: ["form": FieldMessage(key: "This plan has changed. Refresh it before marking this step.")],
                status: 422)
        ) { try await source.send(.checkOff(change)) }
    }
    @Test func unsupportedAndSensitivePatchRefusal() async throws {
        let source = try mockSource()
        _ = try await login(source)
        for kind in [OutboxKind.completeTrip, .dataExport, .security] {
            await #expect(throws: DataFailure.unsupported(kind)) {
                try await source.send(.unsupported(kind: kind, payload: JSONObject()))
            }
        }
        for section in [SettingsSection.bodyClock, .preferences, .reminders] {
            await #expect(throws: (any Error).self) {
                try await source.send(.settings(section: section, patch: JSONObject(["password": .string("secret")])))
            }
            await #expect(throws: (any Error).self) {
                try await source.send(.settings(section: section, patch: JSONObject()))
            }
        }
        await #expect(throws: (any Error).self) { try await source.send(.policies(version: "stale")) }
        await #expect(throws: (any Error).self) {
            try await source.send(.profile(ProfileChange(name: "Changed", email: "other@example.com")))
        }
    }
    @Test func claimIsAccountAndSecretBound() async throws {
        var seed = try scenarioState()
        seed.claims["test-draft"] = MockClaim(accountID: demoID, tripID: demoTripID, secret: "test-secret")
        let source = try mockSource(seed: seed)
        var input = passwordInput()
        input.draftToken = "test-draft"
        input.guestSecret = "test-secret"
        guard case .session(let result) = try await source.signIn(input) else {
            Issue.record("Expected session")
            return
        }
        #expect(result.tripId == demoTripID)
        input.guestSecret = "wrong"
        guard case .session(let wrong) = try await source.signIn(input) else {
            Issue.record("Expected session")
            return
        }
        #expect(wrong.tripId == nil)
        var passkey = passkeyInput(try await source.passkeyOptions(), credentialID: "AQ")
        passkey.draftToken = "test-draft"
        passkey.guestSecret = "test-secret"
        #expect(try await source.passkeyLogin(passkey).tripId == nil)
    }
    @Test func sameDeviceReplacesOnlyItsToken() async throws {
        let clock = MockClock()
        let store = MemoryMockStateStore()
        let source = try mockSource(clock: clock, store: store)
        let first = try await login(source)
        let otherDevice = try await login(source, device: twoFactorID)
        _ = try await login(source)
        let old = try mockSource(clock: clock, store: store, bearer: { first.token })
        await #expect(throws: DataFailure.unauthorized(status: 401)) { try await old.fetchIdentity() }
        let retained = try mockSource(clock: clock, store: store, bearer: { otherDevice.token })
        #expect(try await retained.fetchIdentity().id == demoID)
        clock.advance(89 * 86400)
        _ = try await retained.fetchIdentity()
        clock.advance(89 * 86400)
        _ = try await retained.fetchIdentity()
        clock.advance(90 * 86400)
        await #expect(throws: DataFailure.unauthorized(status: 401)) { try await retained.fetchIdentity() }
    }
}

extension MockAccountTripsTests {
    @Test func invalidSettingsAndMergedBodyClock() async throws {
        let source = try mockSource()
        _ = try await login(source)
        for (section, patch) in [
            (SettingsSection.preferences, JSONObject(["time_format": .string("13")])),
            (.preferences, JSONObject(["hidden_categories": .array([.string("fake")])])),
            (.preferences, JSONObject(["show_optional_items": .null])),
            (.reminders, JSONObject(["light": .string("yes")])), (.reminders, JSONObject(["lead_min": .number(10)])),
            (.bodyClock, JSONObject(["habitual_bed": .string("25:00")])),
            (.bodyClock, JSONObject(["habitual_bed": .string("07:00")])),
            (.bodyClock, JSONObject(["cups_tea": .number(1)])),
            (.bodyClock, JSONObject(["free_day_status": .string("declared")])),
            (.bodyClock, JSONObject(["cups_tea": .number(21)])),
            (.bodyClock, JSONObject(["caffeine_habit": .string("cups")])),
            (.bodyClock, JSONObject(["caffeine_sensitive": .null])),
            (.bodyClock, JSONObject(["blue_blockers": .string("rated")])),
        ] {
            await #expect(throws: (any Error).self) { try await source.send(.settings(section: section, patch: patch)) }
        }
        _ = try await source.send(
            .settings(
                section: .bodyClock,
                patch: JSONObject([
                    "free_day_status": .string("declared"), "free_day_bed": .string("23:30"),
                    "free_day_wake": .string("08:00"), "caffeine_habit": .string("cups"), "cups_tea": .number(1),
                    "blue_blockers": .string("rated"), "blue_blocker_mdfd": .number(Decimal(string: "1.3")!),
                ])))
        #expect(try await source.fetchAccount().settings.bodyClock["blueBlockerMdfd"] == .string("1.3"))
        _ = try await source.send(
            .settings(
                section: .bodyClock,
                patch: JSONObject(["free_day_status": .string("same_as_workdays"), "blue_blockers": .string("no")])))
        #expect(try await source.fetchAccount().settings.bodyClock["freeDayBed"] == .null)
        #expect(try await source.fetchAccount().settings.bodyClock["blueBlockerMdfd"] == .null)
    }
    @Test func checkReplayKeepsTimestampAndVersionAndRejectsMissingStep() async throws {
        let clock = MockClock()
        let source = try mockSource(clock: clock)
        _ = try await login(source)
        var change = CheckOffChange(
            tripID: demoTripID, planInputHash: String(repeating: "a", count: 64), type: .sleep,
            localDate: "2026-11-10", ordinal: 1, status: .done)
        let first = try await source.send(.checkOff(change))
        clock.advance(3600)
        #expect(try await source.send(.checkOff(change)) == first)
        change.ordinal = 2
        await #expect(throws: (any Error).self) { try await source.send(.checkOff(change)) }
        change.ordinal = 0
        await #expect(throws: (any Error).self) { try await source.send(.checkOff(change)) }
    }
}
