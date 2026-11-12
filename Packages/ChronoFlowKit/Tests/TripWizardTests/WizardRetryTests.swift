import AppCore
import Foundation
import Testing

@testable import TripWizard

@Suite struct WizardRetryTests {
    @Test(arguments: [false, true]) @MainActor
    func inlineReviewThrottleTicksAndAllowsManualRetry(fromFineTune: Bool) async throws {
        let clock = CheckingTestClock()
        let fixture = try await completionFixture(checkingClock: clock.clock)
        let model = fixture.model
        await fixture.source.configure(reviewFailure: .throttled(retryAfterSeconds: 3, status: 429))
        if fromFineTune {
            model.revisit(.fineTune)
            model.editForm { $0.preparation.days = 0 }
            model.finishFineTune()
        } else {
            model.readyTick(force: true)
        }
        try await eventually { model.draft.state.step == .checking && model.retrySeconds == 3 && clock.waiterCount > 0 }
        model.beginChecking()
        #expect(await fixture.source.count("review") == 1)
        clock.advance(to: 1)
        try await eventually { model.retrySeconds == 2 }
        clock.advance(to: 3)
        try await eventually { model.retrySeconds == 0 }
        #expect(model.checking.retryAt == nil)
        await fixture.source.configure()
        model.beginChecking()
        try await eventually { await fixture.source.count("review") == 2 }
        #expect(model.checking.failure == nil)
        try await fixture.close()
    }

    @Test @MainActor func checkingThrottleClearsWhenLeavingAndDoesNotBlockContinue() async throws {
        let clock = CheckingTestClock()
        let fixture = try await completionFixture(checkingClock: clock.clock)
        let model = fixture.model
        await fixture.source.configure(reviewFailure: .throttled(retryAfterSeconds: 30, status: 429))
        model.go(.outbound)
        model.beginChecking()
        try await eventually { model.retrySeconds == 30 }
        model.go(.outbound)
        #expect(model.retrySeconds == 0 && model.checking.failure == nil && model.checking.retryAt == nil)
        await fixture.source.configure()
        model.beginChecking()
        try await eventually { await fixture.source.count("review") == 2 }
        #expect(model.draft.state.step == .checking && model.checking.failure == nil)
        try await fixture.close()
    }

    @Test @MainActor func saveThrottleTicksWithoutReadyViewAndExpires() async throws {
        let clock = CheckingTestClock()
        let fixture = try await completionFixture(checkingClock: clock.clock)
        let model = fixture.model
        await fixture.source.configure(saveFailure: .throttled(retryAfterSeconds: 3, status: 429))
        model.savePlan()
        try await eventually { model.retrySeconds == 3 && clock.waiterCount > 0 }
        fixture.clock.advance(1)
        clock.advance(to: 1)
        try await eventually { model.retrySeconds == 2 }
        #expect(!model.canSave)
        fixture.clock.advance(2)
        clock.advance(to: 3)
        try await eventually { model.retrySeconds == 0 }
        #expect(model.draft.state.saveFailure?.retryAt == nil && model.canSave)
        #expect(await fixture.source.count("save") == 1)
        try await fixture.close()
    }

    @Test(arguments: [MemberWizardStep.fineTune, .whereTo, .outbound]) @MainActor
    func leavingSaveThrottleAllowsChangedInputToContinue(step: MemberWizardStep) async throws {
        let clock = CheckingTestClock()
        let fixture = try await completionFixture(checkingClock: clock.clock)
        let model = fixture.model
        await fixture.source.configure(saveFailure: .throttled(retryAfterSeconds: 42, status: 429))
        model.savePlan()
        try await eventually { model.retrySeconds == 42 }
        model.revisit(step)
        #expect(model.retrySeconds == 0)
        await fixture.source.configure()
        model.editForm { $0.preparation.days = 0 }
        if step == .fineTune {
            model.finishFineTune()
        } else {
            model.finishFlightInput()
            try await eventually { clock.deadlines.contains(1.2) }
            clock.advance(to: 1.2)
            try await eventually { clock.deadlines.contains(1.5) }
            clock.advance(to: 1.5)
        }
        try await eventually { model.draft.state.step == .ready && !model.reviewing }
        #expect(model.draft.state.saveFailure == nil && model.retrySeconds == 0 && model.canSave)
        try await fixture.close()
    }

    @Test @MainActor func reviewClearsActiveSaveThrottleAndRevisitRestoresOnlyRemainingTime() async throws {
        let clock = CheckingTestClock()
        let fixture = try await completionFixture(checkingClock: clock.clock)
        let model = fixture.model
        await fixture.source.configure(saveFailure: .throttled(retryAfterSeconds: 42, status: 429))
        model.savePlan()
        try await eventually { model.retrySeconds == 42 }
        model.revisit(.fineTune)
        fixture.clock.advance(40)
        model.finishFineTune()
        #expect(model.retrySeconds == 2)
        await fixture.source.configure()
        model.readyTick(force: true)
        try await eventually { !model.reviewing && model.draft.state.saveFailure == nil }
        #expect(model.retrySeconds == 0 && model.canSave)
        clock.advance(to: 100)
        #expect(model.retrySeconds == 0)
        try await fixture.close()
    }

    @Test(arguments: [false, true]) @MainActor
    func updatedOnlyDescribesServerChangesForUnchangedInput(userEdited: Bool) async throws {
        let fixture = try await completionFixture()
        let model = fixture.model
        var changed = fixture.review
        changed.price?.cost += 1
        await fixture.source.queueReviews([.success(changed)])
        if userEdited {
            model.revisit(.fineTune)
            model.editForm { $0.preparation.days = 0 }
            model.finishFineTune()
        } else {
            model.readyTick(force: true)
        }
        try await eventually { !model.reviewing }
        #expect(model.draft.state.updated == !userEdited)
        model.revisit(.fineTune)
        #expect(model.draft.state.updated == false)
        model.finishFineTune()
        #expect(model.draft.state.updated == false)
        try await fixture.close()
    }
}
