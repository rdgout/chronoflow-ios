import AppCore
import Foundation
import Testing

@testable import DataAccess

@Suite struct DataSourceParityTests {
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
            #expect(try await source.fetchTrips().first?.card["id"]?.string == demoTripID)
            #expect(
                try await source.fetchTripDetail(id: demoTripID)
                    == JSONDecoder().decode(TripDetail.self, from: fixture("trips/detail.json")))
            let options = try await source.passkeyOptions()
            #expect(options.options.rpId == "app.chronoflow.net" && options.options.timeout == 60_000)
            #expect(try await source.passkeyLogin(passkeyInput(options)).account == expectedSession.account)
        }
    }
}
