import AppCore
import Testing

@testable import TripWizard

@Suite struct WizardCreditsTests {
    private func review(
        status: PlanStatus = .ok, price: ApiReviewPrice?, canSave: Bool, blocked: String? = nil
    ) -> ApiTripReview {
        ApiTripReview(
            identity: ApiReviewIdentity(token: "t", inputRevision: 1, reviewRevision: 1),
            status: status, reasons: [], prompts: [], price: price, canSave: canSave, saveBlockedReason: blocked,
            itinerary: ApiReviewItinerary(legs: [], layovers: []))
    }

    private let paid = ApiReviewPrice(state: .create, cost: 1, balance: 3, unlimited: false, freeDirections: [])

    @Test func noPriceIsNeverFree() {
        #expect(WizardCredits(review(status: .needsAnswers, price: nil, canSave: false)) == .unavailable)
        #expect(WizardCredits(review(status: .noPlan, price: nil, canSave: false)) == .unavailable)
    }

    @Test func pricedReviews() {
        #expect(WizardCredits(review(price: paid, canSave: true)) == .credits)
        #expect(WizardCredits(review(price: paid, canSave: false, blocked: "Not enough credits")) == .unavailable)
        var free = paid
        free.cost = 0
        #expect(WizardCredits(review(price: free, canSave: true)) == .free)
    }
}
