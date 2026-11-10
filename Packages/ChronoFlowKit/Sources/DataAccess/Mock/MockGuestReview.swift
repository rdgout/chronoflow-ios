import AppCore
import CryptoKit
import Foundation

struct MockGuestDraft: Codable, Sendable, Equatable {
    var deviceID: String
    var secretHash: String
    var draft: MockWizardDraft
}

enum MockGuestReview {
    static func hash(_ secret: String) -> String {
        SHA256.hash(data: Data(secret.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func secret() -> String {
        (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
    }

    static func prepare(_ request: ApiGuestTripReviewInput, now: Date) throws -> (ApiTripInput, AccountSettings) {
        let profile = ProfilePreferences.request(request.profile)
        var settings = AccountSnapshot.mockRegistration(id: "", name: "", email: "", language: .en, now: now).settings
        let missing = ["habitual_bed", "habitual_wake"].filter { profile[$0]?.string == nil }
        if !missing.isEmpty {
            throw DataFailure.validation(
                fields: Dictionary(
                    uniqueKeysWithValues: missing.map {
                        ("profile." + $0, FieldMessage(key: "Check your bedtime and wake-up time."))
                    }), status: 422)
        }
        do { try MockSettings.validate(section: .bodyClock, patch: profile, current: settings) } catch let failure
            as DataFailure
        {
            if case .validation(let fields, let status) = failure {
                throw DataFailure.validation(
                    fields: Dictionary(uniqueKeysWithValues: fields.map { ("profile." + $0.key, $0.value) }),
                    status: status)
            }
            throw failure
        }
        MockSettings.apply(profile, section: .bodyClock, to: &settings)
        settings.planCredits = JSONObject(["credits": .number(3), "unlimited": .bool(false)])
        var input = request.input
        input.return = nil
        input.tripEndKind = "one_way"
        input.tripEndNights = nil
        input.tripEndCheckOutDate = nil
        input.override = ApiTripInputOverride(
            use: true, habitualBed: profile["habitual_bed"]?.string,
            habitualWake: profile["habitual_wake"]?.string, chronotype: profile["chronotype"]?.string)
        for (index, leg) in input.outbound.legs.enumerated() where leg.fromIata == leg.toIata {
            throw DataFailure.validation(
                fields: [
                    "outbound.legs.\(index).to_iata": FieldMessage(
                        key: "Choose different departure and arrival airports.")
                ], status: 422)
        }
        let itinerary = try MockTripGeneration.itinerary(input)
        if let arrival = itinerary.legs.last?.arriveUtc,
            let date = ISO8601DateFormatter().date(from: arrival), date <= now
        {
            throw DataFailure.validation(
                fields: [
                    "review": FieldMessage(key: "A new plan needs an upcoming arrival. Check your flight dates.")
                ], status: 422)
        }
        return (input, settings)
    }
}
