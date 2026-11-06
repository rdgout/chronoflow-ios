import AppCore
import Auth
import Foundation
import Testing

struct AuthFailureMappingTests {
    @Test func onlyApprovedMessagesReachDisplayedFields() {
        let mapped = AuthFailureMapping(
            .validation(
                fields: [
                    "email": FieldMessage(key: "Please fill this in."),
                    "password": FieldMessage(key: "unknown server English"),
                    "device_id": FieldMessage(key: "Please fill this in."),
                ], status: 422), displayedFields: ["email", "password"])
        #expect(mapped.fields == ["email": FieldMessage(key: "Please fill this in.")])
        #expect(mapped.banner == .server)
        let credentials = AuthFailureMapping(
            .validation(
                fields: [
                    "email": FieldMessage(key: "These sign-in details don't match our records.")
                ], status: 422), displayedFields: ["email"])
        #expect(credentials.banner == .credentials && credentials.fields.isEmpty)
    }
    @Test func offlineHasNoPresentationAndThrottleRetainsDeadline() {
        #expect(AuthFailureMapping(.offline, displayedFields: []).banner == nil)
        let throttle = AuthFailureMapping(.throttled(retryAfterSeconds: 73, status: 429), displayedFields: [])
        #expect(throttle.banner == .locked && throttle.retryAfterSeconds == 73)
    }
    @Test func obsoleteCredentialsKeyUsesTheServerFallback() {
        let mapped = AuthFailureMapping(
            .validation(
                fields: ["email": FieldMessage(key: "These credentials do not match our records.")], status: 422),
            displayedFields: ["email", "password"])
        #expect(mapped.banner == .server)
        #expect(mapped.fields.isEmpty)
    }
    @Test func fieldArgumentsAreWhitelistedAndNeverExposeUnknownEnglish() {
        for (locale, expected) in [
            ("en", "Use no more than 255 characters."), ("nl", "Gebruik niet meer dan 255 tekens."),
        ] {
            #expect(
                AuthCopy.field(
                    FieldMessage(key: "Use no more than :max characters.", arguments: ["max": .number(255)]),
                    locale: Locale(identifier: locale)) == expected)
        }
        #expect(!AuthCopy.supports(FieldMessage(key: "Use at least :min characters.")))
        #expect(
            !AuthCopy.supports(FieldMessage(key: "Use at least :min characters.", arguments: ["min": .string("<bad>")]))
        )
        #expect(
            !AuthCopy.supports(FieldMessage(key: "Use at least :min characters.", arguments: ["min": .number(0.5)])))
        #expect(!AuthCopy.supports(FieldMessage(key: "Use both uppercase and lowercase letters.")))
    }
}
