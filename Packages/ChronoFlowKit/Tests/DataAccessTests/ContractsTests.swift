import AppCore
import Foundation
import Testing

@testable import DataAccess

@Suite struct ContractsTests {
    @Test func signInVariantsAndMalformed() throws {
        let decoder = JSONDecoder()
        #expect(
            try decoder.decode(SignInResult.self, from: Data(#"{"kind":"two-factor","challengeId":"fake"}"#.utf8))
                == .twoFactor(challengeId: "fake"))
        for json in [
            #"{"kind":"unknown"}"#, #"{"kind":"two-factor"}"#, #"{"kind":"session","token":"fake"}"#,
            #"{"kind":"two-factor","challengeId":""}"#,
        ] {
            #expect(throws: (any Error).self) { try decoder.decode(SignInResult.self, from: Data(json.utf8)) }
        }
    }
    @Test func proofIsExclusive() throws {
        let input = TwoFactorInput(challengeId: "fake", proof: .recoveryCode("fake-recovery"))
        #expect(try JSONDecoder().decode(TwoFactorInput.self, from: JSONEncoder().encode(input)) == input)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(
                TwoFactorInput.self, from: Data(#"{"challengeId":"fake","code":"1","recovery_code":"2"}"#.utf8))
        }
    }
    @Test func passkeyNullAndEncoding() throws {
        let json =
            #"{"id":"AA","rawId":"AA==","type":"public-key","response":{"clientDataJSON":"AA","authenticatorData":"AA==","signature":"AA","userHandle":null}}"#
        let assertion = try JSONDecoder().decode(ApiPasskeyAssertion.self, from: Data(json.utf8))
        #expect(assertion.response.userHandle == nil)
        let input = ApiPasskeyLoginInput(
            challengeId: "fake", credential: assertion, deviceID: "fake-device", deviceName: "iPhone")
        #expect(try JSONDecoder().decode(ApiPasskeyLoginInput.self, from: JSONEncoder().encode(input)) == input)
        for bad in [
            json.replacingOccurrences(of: "public-key", with: "password"),
            json.replacingOccurrences(of: #""signature":"AA","#, with: ""),
        ] {
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(ApiPasskeyAssertion.self, from: Data(bad.utf8))
            }
        }
    }
    @Test func unknownJSONAndFailureInterpolation() throws {
        let value = try JSONDecoder().decode(
            JSONObject.self, from: Data(#"{"future":{"null":null,"list":[true,3.25,"x"]}}"#.utf8))
        #expect(try JSONDecoder().decode(JSONObject.self, from: JSONEncoder().encode(value)) == value)
        #expect(
            FieldMessage(key: "Use no more than :max characters.", arguments: ["max": .number(255)]).interpolationKey
                == "Use no more than %lld characters.")
        #expect(
            FieldMessage(key: "At least {{min}}.", arguments: ["min": .number(12)]).interpolationKey
                == "At least %lld.")
    }
}

extension ContractsTests {
    @Test func inputWireKeysAndOutboxRoundTrips() throws {
        let input = RegisterInput(
            name: "Test", email: "test@example.com", password: "artificial", passwordConfirmation: "artificial",
            deviceID: "test-device", deviceName: "iPhone", language: .nl, draftToken: "artificial-draft",
            inputRevision: 1, reviewRevision: 1, guestSecret: "artificial-secret")
        let data = try JSONEncoder().encode(input)
        let object = try JSONDecoder().decode(JSONObject.self, from: data)
        #expect(
            object["device_id"] == .string("test-device") && object["password_confirmation"] == .string("artificial"))
        #expect(object["deviceID"] == nil && object["draft_token"] == .string("artificial-draft"))
        #expect(try JSONDecoder().decode(RegisterInput.self, from: data) == input)
        let changes: [OutboxChange] = [
            .walkthrough, .profile(ProfileChange(name: "Test", email: "test@example.com")), .policies(version: "1.0"),
            .settings(section: .reminders, patch: JSONObject(["light": .bool(true)])),
            .checkOff(
                CheckOffChange(
                    tripID: "test", planInputHash: "fake", type: .sleep, localDate: "2026-11-10", ordinal: 1,
                    status: nil)), .unsupported(kind: .completeTrip, payload: JSONObject(["future": .null])),
        ]
        for change in changes {
            #expect(try JSONDecoder().decode(OutboxChange.self, from: JSONEncoder().encode(change)) == change)
        }
        #expect(
            FieldMessage(
                key: "From :min to {{max}} for :attribute.",
                arguments: ["min": .number(1), "max": .number(12), "attribute": .string("name")]
            ).interpolationKey == "From %3$lld to %2$lld for %1$@.")
    }
    @Test func nullablePasskeyUserHandleAndDiscriminators() throws {
        for member in ["", #", "userHandle":null"#, #", "userHandle":"""#] {
            let data = Data(
                "{\"clientDataJSON\":\"AA\",\"authenticatorData\":\"AA==\",\"signature\":\"AA\"\(member)}".utf8)
            let response = try JSONDecoder().decode(ApiPasskeyAssertionResponse.self, from: data)
            #expect(response.userHandle == nil || response.userHandle == "")
        }
        let options =
            #"{"challenge":"AA","rpId":"app.chronoflow.net","timeout":60000,"userVerification":"required","allowCredentials":[]}"#
        for invalid in [
            options.replacingOccurrences(of: "required", with: "preferred"),
            options.replacingOccurrences(of: "[]", with: "[{}]"),
        ] {
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(ApiPasskeyRequestOptions.self, from: Data(invalid.utf8))
            }
        }
    }
}
