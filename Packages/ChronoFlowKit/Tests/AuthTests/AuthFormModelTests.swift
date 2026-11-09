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
        #expect(form.banner == nil && form.takeAnnouncement(locale: nl) == nil)
        #expect(form.begin(.password))
    }
}
