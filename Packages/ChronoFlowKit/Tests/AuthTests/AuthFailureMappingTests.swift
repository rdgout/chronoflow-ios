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
    }

    @Test func backendFieldMessagesMapAndLocalizeInBothLanguages() {
        let rows = [
            ("Use both uppercase and lowercase letters.", "Gebruik hoofdletters en kleine letters.", "password"),
            ("Use at least one letter.", "Gebruik minstens één letter.", "password"),
            ("Use at least one number.", "Gebruik minstens één cijfer.", "password"),
            ("Use at least one symbol.", "Gebruik minstens één symbool.", "password"),
            (
                "This password has appeared in a data leak. Choose a different password.",
                "Dit wachtwoord is gevonden in een datalek. Kies een ander wachtwoord.", "password"
            ),
            (
                "This email verification link is invalid or has expired.",
                "Deze link om je e-mailadres te verifiëren is ongeldig of verlopen.", "email"
            ),
        ]
        for (english, dutch, field) in rows {
            let message = FieldMessage(key: english)
            let failure = DataFailure.validation(fields: [field: message], status: 422)
            let mapped = AuthFailureMapping(failure, displayedFields: ["email", "password"])
            #expect(AuthCopy.supports(message))
            #expect(mapped.fields == [field: message])
            #expect(mapped.banner == nil)
            for (language, expected) in [("en", english), ("nl", dutch)] {
                #expect(AuthCopy.field(message, locale: Locale(identifier: language)) == expected)
            }
            let hidden = AuthFailureMapping(failure, displayedFields: [])
            #expect(hidden.fields.isEmpty && hidden.banner == .server)
        }
    }
}
