import Testing

@testable import AppCore

struct LaunchSignpostsTests {
    @MainActor @Test func signpostsPairAllIntervalsWithoutDoubleBeginsOrEnds() {
        let signs = LaunchSignposts()
        for interval in LaunchSignposts.Interval.allCases {
            signs.end(interval)
            signs.begin(interval)
            signs.begin(interval)
        }
        #expect(signs.activeIntervals == Set(LaunchSignposts.Interval.allCases))
        for interval in LaunchSignposts.Interval.allCases {
            signs.end(interval)
            signs.end(interval)
        }
        #expect(signs.activeIntervals.isEmpty)
        signs.event(.sceneConnect)
        signs.event(.overlayFirstCommit)
        signs.event(.rootFirstLayout)
        #expect(signs.events == [.sceneConnect, .overlayFirstCommit, .rootFirstLayout])
    }
}
