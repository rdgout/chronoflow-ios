import AppCore
import Foundation
import Testing

@testable import DataAccess

@Suite struct SettingsDeleteAPITests {
    @Test func deletionSendsPasswordUnderTheBackendFieldAndPreservesBillingFailure() async throws {
        let server = StubServer { request in
            #expect(request.httpMethod == "DELETE" && request.url?.path == "/v1/account")
            let body = try requestJSON(request)
            #expect(body == JSONObject(["password": .string("password")]))
            return .init(204)
        }
        try await APIDataSource(client: server.client()).deleteAccount(password: "password")
        let failed = StubServer { _ in
            .init(
                422,
                "{\"code\":\"validation_failed\",\"message\":\"Invalid\",\"errors\":{\"billing\":\"Your subscription could not be cancelled. Please try deleting your account again.\"}}"
            )
        }
        await #expect(
            throws: DataFailure.validation(
                fields: [
                    "billing": FieldMessage(
                        key: "Your subscription could not be cancelled. Please try deleting your account again.")
                ], status: 422)
        ) {
            try await APIDataSource(client: failed.client()).deleteAccount(password: "password")
        }
    }
    @Test func mockDeletionRequiresPasswordAndActuallyRemovesAccount() async throws {
        let source = try mockSource()
        let session = try await login(source)
        await #expect(
            throws: DataFailure.validation(
                fields: ["password": FieldMessage(key: "The provided password was incorrect.")], status: 422)
        ) {
            try await source.deleteAccount(password: "wrong")
        }
        #expect(try await source.fetchIdentity().id == session.account.id)
        await source.setOffline(true)
        await #expect(throws: DataFailure.offline) { try await source.deleteAccount(password: "password") }
        await source.setOffline(false)
        #expect(try await source.fetchIdentity().id == session.account.id)
        try await source.deleteAccount(password: "password")
        await #expect(throws: DataFailure.unauthorized(status: 401)) { try await source.fetchIdentity() }
    }
}
