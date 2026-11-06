import Testing

@testable import AppCore

@MainActor struct LaunchIntroTests {
    @Test func offsetsProgressAndAbsoluteClockDelays() {
        let clock = ManualLaunchClock()
        let intro = LaunchIntro(start: .milliseconds(2300), clock: clock)
        #expect(
            (0..<6).map { LaunchIntro.offset(for: $0) } == [
                .zero, .milliseconds(100), .milliseconds(150), .milliseconds(300), .milliseconds(400),
                .milliseconds(450),
            ])
        for index in 0..<6 {
            let start = intro.start + LaunchIntro.offset(for: index)
            #expect(intro.progress(for: index, at: start - .milliseconds(1)) == 0)
            #expect(intro.progress(for: index, at: start) == 0)
            #expect(
                abs(intro.progress(for: index, at: start + .milliseconds(225)) - CubicBezier.intro.value(at: 0.5))
                    < 1e-12)
            #expect(intro.progress(for: index, at: start + .milliseconds(450)) == 1)
        }
        clock.advance(to: .milliseconds(2400))
        #expect(abs(intro.delay(for: 0) + 0.1) < 1e-12)
        #expect(abs(intro.delay(for: 5) - 0.35) < 1e-12)
        #expect((0..<6).allSatisfy { intro.progress(for: $0, at: .milliseconds(3200)) == 1 })
    }

    @Test func introIsClaimedOnceAndFreezingKeepsTheSharedEpoch() {
        let clock = ManualLaunchClock()
        let intro = LaunchIntro(start: .milliseconds(2300), clock: clock, frozenTime: .milliseconds(2450))
        #expect(intro.claim())
        #expect(!intro.claim())
        #expect(intro.hasPlayed)
        #expect(intro.frozenTime == .milliseconds(2450))
        clock.advance(to: .seconds(10))
        #expect(intro.progress(for: 2, at: intro.frozenTime!) == 0)
        let late = LaunchIntro(start: .milliseconds(8700), clock: clock)
        #expect(late.progress(for: 5, at: .milliseconds(9600)) == 1)
    }
}
