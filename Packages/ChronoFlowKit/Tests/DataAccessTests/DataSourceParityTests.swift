import AppCore
import Foundation
import Testing

@testable import DataAccess

@Suite struct DataSourceParityTests {
    @Test(arguments: [SettingsSection.reminders, .preferences, .bodyClock])
    func invalidSettingsReturnEveryField(section: SettingsSection) async throws {
        let patch: JSONObject
        switch section {
        case .reminders: patch = JSONObject(["lead_min": .number(45), "light": .string("x"), "winddown": .bool(true)])
        case .preferences:
            patch = JSONObject(["time_format": .string("13"), "show_optional_items": .string("x")])
        case .bodyClock: patch = JSONObject(["habitual_bed": .string("25:00"), "habitual_wake": .string("99:00")])
        }
        let fields = patch.fields.keys.filter { $0 != "winddown" }
        let message = section == .bodyClock ? "Enter a valid time." : "Choose one of the available options."
        let expected = DataFailure.validation(
            fields: Dictionary(uniqueKeysWithValues: fields.map { ($0, FieldMessage(key: message)) }), status: 422)
        let body = try JSONSerialization.data(withJSONObject: [
            "code": "validation_failed", "message": "The given data was invalid.",
            "errors": Dictionary(uniqueKeysWithValues: fields.map { ($0, message) }),
        ])
        let server = StubServer { _ in .init(422, String(decoding: body, as: UTF8.self)) }
        let api = APIDataSource(client: try server.client())
        let mock = try mockSource()
        _ = try await login(mock)
        let before = try await mock.fetchAccount()
        let keys = patch.fields.keys.sorted()
        for source: any DataSource in [api, mock] {
            for order in [keys, Array(keys.reversed())] {
                let reordered = JSONObject(Dictionary(uniqueKeysWithValues: order.map { ($0, patch[$0]!) }))
                await #expect(throws: expected) { try await source.send(.settings(section: section, patch: reordered)) }
            }
        }
        #expect(try await mock.fetchAccount() == before)
    }

    @Test func wrongCredentialsMatchBackendValidation() async throws {
        let server = StubServer { _ in
            .init(422, try fixtureText("errors/wrong_credentials.json"))
        }
        let api = APIDataSource(client: try server.client())
        let mock = try mockSource()
        let expected = DataFailure.validation(
            fields: ["email": FieldMessage(key: "These sign-in details don't match our records.")], status: 422)
        for source: any DataSource in [api, mock] {
            await #expect(throws: expected) { try await source.signIn(passwordInput(password: "wrong")) }
        }
    }

    @Test func sharedRecordedContract() async throws {
        let server = StubServer { request in
            switch request.url!.path {
            case "/v1/auth/login": return .init(200, try fixtureText("auth/session.json"))
            case "/v1/auth/passkey/options": return .init(200, try fixtureText("auth/passkey-options.json"))
            case "/v1/auth/passkey/login": return .init(200, try fixtureText("auth/session.json"))
            case "/v1/users/me": return .init(200, try fixtureText("account/identity.json"))
            case "/v1/account": return .init(200, try fixtureText("account/snapshot.json"))
            case "/v1/trips": return .init(200, try fixtureText("trips/list.json"))
            case "/v1/trips/\(demoTripID)": return .init(200, try fixtureText("trips/detail.json"))
            default:
                Issue.record("Unmatched parity route")
                return .init(500)
            }
        }
        let api = APIDataSource(client: try server.client())
        let mock = try mockSource()
        let expectedSession = try JSONDecoder().decode(SessionResult.self, from: fixture("auth/session.json"))
        let expectedSnapshot = try JSONDecoder().decode(AccountSnapshot.self, from: fixture("account/snapshot.json"))
        for source: any DataSource in [api, mock] {
            let session = try await login(source)
            #expect(session.account == expectedSession.account && session.tripId == expectedSession.tripId)
            #expect(try await source.fetchIdentity() == expectedSession.account)
            #expect(try await source.fetchAccount() == expectedSnapshot)
            #expect(try await source.fetchTrips().first?.card.id == demoTripID)
            #expect(
                try await source.fetchTripDetail(id: demoTripID).detail
                    == JSONDecoder().decode(TripDetail.self, from: fixture("trips/detail.json")))
            let options = try await source.passkeyOptions()
            #expect(options.options.rpId == "app.chronoflow.net" && options.options.timeout == 60_000)
            #expect(try await source.passkeyLogin(passkeyInput(options)).account == expectedSession.account)
        }
    }
}
