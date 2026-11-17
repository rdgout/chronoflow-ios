import AppCore
import Foundation
import Testing

@Suite struct PasskeyManagementContractsTests {
    @Test func registrationChallengeDecodesTheDocumentedOptions() throws {
        let json = """
            {"challengeId":"c1","options":{"challenge":"Y2g","timeout":60000,
            "rp":{"id":"app.chronoflow.net","name":"app.chronoflow.net"},
            "user":{"id":"dXNlcg","name":"demo@example.com","displayName":"Demo"},
            "pubKeyCredParams":[{"type":"public-key","alg":-7},{"type":"public-key","alg":-257}],
            "authenticatorSelection":{"requireResidentKey":true,"userVerification":"required","residentKey":"required"},
            "attestation":"none",
            "excludeCredentials":[{"type":"public-key","id":"AQID"}]}}
            """
        let challenge = try JSONDecoder().decode(ApiPasskeyRegistrationChallenge.self, from: Data(json.utf8))
        #expect(challenge.challengeId == "c1" && challenge.options.timeout == 60_000)
        #expect(challenge.options.rp == ApiPasskeyRelyingParty(id: "app.chronoflow.net"))
        #expect(
            challenge.options.user == ApiPasskeyUserEntity(id: "dXNlcg", name: "demo@example.com", displayName: "Demo"))
        #expect(challenge.options.pubKeyCredParams.map(\.alg) == [-7, -257])
        #expect(challenge.options.authenticatorSelection == ApiPasskeyAuthenticatorSelection())
        #expect(challenge.options.attestation == "none")
        #expect(challenge.options.excludeCredentials == [ApiPasskeyCredentialDescriptor(id: "AQID")])
        let missing = #"{"challengeId":"c2","options":{"challenge":"Y2g","rp":{"id":"a","name":"a"}}}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ApiPasskeyRegistrationChallenge.self, from: Data(missing.utf8))
        }
    }

    @Test func registrationInputEncodesTheDocumentedBodyWithoutAPassword() throws {
        let input = ApiPasskeyRegistrationInput(
            challengeId: "c1", name: "iPhone",
            credential: ApiPasskeyAttestation(
                id: "AQID", rawId: "AQID",
                response: ApiPasskeyAttestationResponse(
                    clientDataJSON: "Y2Q", attestationObject: "YXR0", transports: ["internal", "hybrid"])))
        let object = try JSONDecoder().decode(JSONObject.self, from: JSONEncoder().encode(input))
        #expect(Set(object.fields.keys) == ["challengeId", "name", "credential"])
        let credential = try #require(object["credential"]?.object)
        #expect(Set(credential.keys) == ["id", "rawId", "type", "response"])
        #expect(credential["type"] == .string("public-key") && credential["id"] == .string("AQID"))
        #expect(credential["rawId"] == .string("AQID"))
        let response = try #require(credential["response"]?.object)
        #expect(response["clientDataJSON"] == .string("Y2Q") && response["attestationObject"] == .string("YXR0"))
        #expect(response["transports"] == .array([.string("internal"), .string("hybrid")]))
        let bare = ApiPasskeyAttestationResponse(clientDataJSON: "a", attestationObject: "b")
        let encoded = try JSONDecoder().decode(JSONObject.self, from: JSONEncoder().encode(bare))
        #expect(encoded["transports"] == nil)
    }

    @Test func passkeyListItemDecodesTheDocumentedFields() throws {
        let list = try JSONDecoder().decode(
            ApiPasskeyList.self,
            from: Data(
                """
                {"passkeys":[{"id":12,"name":"iPhone","authenticator":"Apple Passwords",
                "createdAt":"2026-11-12T09:30:00.000000Z","lastUsedAt":"2026-11-12T10:02:41.000000Z"},
                {"id":7,"name":"MacBook","authenticator":null,"createdAt":"2026-10-30T18:11:05.000000Z","lastUsedAt":null}]}
                """.utf8))
        #expect(list.passkeys.map(\.id) == [12, 7])
        #expect(list.passkeys[0].authenticator == "Apple Passwords" && list.passkeys[1].authenticator == nil)
        #expect(list.passkeys[1].lastUsedAt == nil)
        let empty = try JSONDecoder().decode(ApiPasskeyList.self, from: Data(#"{"passkeys":[]}"#.utf8))
        #expect(empty.passkeys.isEmpty)
    }

    @Test func securitySummaryCountIsOptionalAndWholeNumbersOnly() {
        #expect(JSONObject(["passkeyCount": .number(2)])["passkeyCount"]?.int == 2)
        #expect(JSONObject(["passkeyCount": .number(0)])["passkeyCount"]?.int == 0)
        #expect(JSONObject(["twoFactorEnabled": .bool(false)])["passkeyCount"]?.int == nil)
        #expect(JSONValue.number(Decimal(string: "1.5")!).int == nil)
        #expect(JSONValue.number(-1).int == nil)
        #expect(JSONValue.string("2").int == nil)
    }
}
