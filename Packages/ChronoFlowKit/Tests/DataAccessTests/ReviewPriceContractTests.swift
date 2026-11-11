import AppCore
import Foundation
import Testing

@Suite struct ReviewPriceContractTests {
    private func decode(_ name: String, patch: (inout JSONObject) -> Void = { _ in }) throws -> ApiTripReview {
        var raw = try JSONDecoder().decode(JSONObject.self, from: fixture("wizard/\(name).json"))
        patch(&raw)
        return try JSONDecoder().decode(ApiTripReview.self, from: JSONEncoder().encode(raw))
    }

    @Test func needsAnswersHasNoPriceAndNoSummary() throws {
        let review = try decode("needs-answers")
        #expect(review.status == .needsAnswers && review.price == nil && review.summary == nil && !review.canSave)
        #expect(review.prompts.allSatisfy { $0.blocking })
    }

    @Test func priceKeyMayBeAbsent() throws {
        let review = try decode("needs-answers") { $0["price"] = nil }
        #expect(review.price == nil)
    }

    @Test func noPlanHasReasonsAndNoPrompts() throws {
        let review = try decode("needs-answers") {
            $0["status"] = .string("no_plan")
            $0["prompts"] = .array([])
            $0["reasons"] = .array([
                .object(["key": .string("This plan is not available for travellers under 18."), "args": .array([])])
            ])
        }
        #expect(review.status == .noPlan && review.price == nil && review.summary == nil && !review.canSave)
        #expect(review.prompts.isEmpty && review.reasons.count == 1)
    }

    @Test func notEnoughCreditsKeepsThePrice() throws {
        let review = try decode("review") {
            $0["canSave"] = .bool(false)
            $0["saveBlockedReason"] = .string("Not enough credits")
        }
        #expect(review.price?.cost == 1 && review.price?.balance == 1)
        #expect(!review.canSave && review.saveBlockedReason == "Not enough credits")
    }

    @Test func okReviewKeepsThePrice() throws {
        let review = try decode("review")
        #expect(review.status == .ok && review.canSave && review.price?.state == .create)
    }
}
