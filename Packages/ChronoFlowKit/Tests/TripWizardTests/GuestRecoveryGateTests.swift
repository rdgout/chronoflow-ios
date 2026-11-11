import Foundation
import Testing
import TripWizard

@Suite struct GuestRecoveryGateTests {
    private let updated = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(arguments: [false, true])
    func noRecordDoesNotRecover(_ signingIn: Bool) {
        #expect(decision(age: nil, handoff: true, intro: true, signingIn: signingIn) == .none)
    }

    @Test(arguments: [0.0, 1740, 1799.999])
    func liveRecordResumesItsDestination(_ age: TimeInterval) {
        #expect(decision(age: age, handoff: true, intro: true) == .wizard)
        #expect(decision(age: age, handoff: true, intro: true, signingIn: true) == .signIn)
    }

    @Test(arguments: [false, true], [false, true])
    func waitsForBothLaunchStages(_ handoff: Bool, _ intro: Bool) {
        for signingIn in [false, true] {
            let expected: GuestRecoveryGate.Decision = handoff && intro ? (signingIn ? .signIn : .wizard) : .wait
            #expect(decision(age: 60, handoff: handoff, intro: intro, signingIn: signingIn) == expected)
        }
    }

    @Test(arguments: [1800.0, 1860], [false, true])
    func expiryWinsDuringTheIntroAndInTheBackground(_ age: TimeInterval, _ finished: Bool) {
        #expect(decision(age: age, handoff: finished, intro: finished) == .expire)
        #expect(decision(age: age, handoff: finished, intro: finished, signingIn: true) == .expire)
    }

    private func decision(
        age: TimeInterval?, handoff: Bool, intro: Bool, signingIn: Bool = false
    ) -> GuestRecoveryGate.Decision {
        GuestRecoveryGate.decision(
            updatedAt: age == nil ? nil : updated, now: updated.addingTimeInterval(age ?? 0),
            handoffFinished: handoff, introFinished: intro, signingIn: signingIn)
    }
}
