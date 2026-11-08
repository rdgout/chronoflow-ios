import AppCore
import Auth
import Foundation
import Testing

@MainActor struct AuthFormModelTests {
    @Test func oneLockCoversTapReturnAndPasskeyAndEditsClearFeedback() {
        let form = AuthFormModel()
        #expect(form.begin(.password))
        #expect(!form.begin(.password))
        #expect(!form.begin(.passkey))
        form.receive(.validation(fields: ["email": FieldMessage(key: "Please fill this in.")], status: 422))
        form.edit("email")
        #expect(form.fields["email"] != nil)
        form.finish()
        form.edit("email")
        #expect(form.fields.isEmpty)
        #expect(form.begin(.passkey))
        form.finish()
    }
    @Test func announcementsAreConsumedOncePerFailureAndNeverRepeatOnEdit() {
        let form = AuthFormModel()
        let nl = Locale(identifier: "nl")
        form.receive(.server(status: 500))
        #expect(form.takeAnnouncement(locale: nl) == "Er ging bij ons iets mis. Probeer het zo meteen opnieuw.")
        #expect(form.takeAnnouncement(locale: nl) == nil)
        form.edit("email")
        #expect(form.takeAnnouncement(locale: nl) == nil)
        form.receive(.server(status: 500))
        #expect(form.takeAnnouncement(locale: nl) != nil)
        form.receive(.offline)
        #expect(form.failure == .offline)
        #expect(form.banner == .offline && form.takeAnnouncement(locale: nl) == "Verbinding nodig")
        #expect(form.begin(.password))
    }

    @Test(arguments: [
        DataFailure.reviewExpired, .notEnoughCredits, .saveCapacity,
        .profileInvalid(fields: ["name": FieldMessage(key: "Please fill this in.")]),
        .offline, .unauthorized(status: 401), .emailUnverified(status: 403),
        .validation(fields: [:], status: 422),
        .validation(fields: ["name": FieldMessage(key: "Please fill this in.")], status: 422),
        .validation(fields: ["email": FieldMessage(key: "This email address is already in use.")], status: 422),
        .validation(
            fields: ["email": FieldMessage(key: "These sign-in details don't match our records.")], status: 422),
        .validation(fields: ["email": FieldMessage(key: "Please fill this in.")], status: 422),
        .validation(fields: ["password": FieldMessage(key: "Please fill this in.")], status: 422),
        .validation(
            fields: ["password_confirmation": FieldMessage(key: "The passwords don't match yet.")], status: 422),
        .validation(
            fields: ["code": FieldMessage(key: "The authentication code was not accepted. Try again.")], status: 422),
        .validation(fields: ["recovery_code": FieldMessage(key: "Please fill this in.")], status: 422),
        .validation(fields: ["hidden": FieldMessage(key: "Please fill this in.")], status: 422),
        .validation(fields: ["email": FieldMessage(key: "Unknown server copy")], status: 422),
        .validation(fields: ["password": FieldMessage(key: "Use at least :min characters.")], status: 422),
        .throttled(retryAfterSeconds: 60, status: 429), .conflict(status: 409), .server(status: 500),
        .server(status: nil), .unsupported(.security),
    ])
    func everyFailureHasVisibleLocalizedFeedbackAndOneAnnouncement(_ failure: DataFailure) throws {
        let contexts: [(AuthFormContext, Set<String>)] = [
            (.signIn, ["email", "password"]), (.signUp, ["name", "email", "password", "password_confirmation"]),
            (.forgot, ["email"]), (.reset, ["password", "password_confirmation"]),
            (.twoFactor, ["code"]), (.twoFactor, ["recovery_code"]), (.verify, []),
        ]
        for (context, displayed) in contexts {
            for language in ["en", "nl"] {
                let locale = Locale(identifier: language)
                let form = AuthFormModel(displayedFields: displayed, context: context)
                #expect(form.begin(.password))
                form.receive(failure)
                form.finish()
                #expect(form.failure == failure && !form.busy)
                #expect(Set(form.fields.keys).isSubset(of: displayed))
                let visible = form.fields.values.compactMap { AuthCopy.field($0, locale: locale) }
                #expect(visible.count == form.fields.count && visible.allSatisfy { !$0.isEmpty })
                #expect(form.banner != nil || !visible.isEmpty, "Silent failure in \(context): \(failure)")
                let announcement = try #require(form.takeAnnouncement(locale: locale))
                #expect(!announcement.isEmpty && visible.allSatisfy { announcement.contains($0) })
                if let banner = form.banner {
                    #expect(announcement.contains(AuthCopy.string(banner.title(for: context), locale: locale)))
                }
                #expect(form.takeAnnouncement(locale: locale) == nil)
                form.receive(failure)
                #expect(form.takeAnnouncement(locale: locale) == announcement)
                form.clear()
                #expect(form.takeAnnouncement(locale: locale) == nil)
            }
        }
    }

    @Test func fieldOnlyAnnouncementsClearOnEditAndUseTheLatestFailure() {
        let form = AuthFormModel()
        let locale = Locale(identifier: "nl")
        let failure = DataFailure.validation(fields: ["email": FieldMessage(key: "Please fill this in.")], status: 422)
        form.receive(failure)
        #expect(form.banner == nil && form.takeAnnouncement(locale: locale) == "Vul dit veld in.")
        form.receive(failure)
        form.edit("email")
        #expect(form.takeAnnouncement(locale: locale) == nil)
        form.receive(failure)
        form.receive(.offline)
        #expect(form.takeAnnouncement(locale: locale) == "Verbinding nodig")
    }
}
