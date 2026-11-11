import AppCore
import Testing

@Suite struct LockoutWaitTests {
    @Test func roundsUpAtUnitBoundaries() {
        for (seconds, unit, count) in [
            (0, LockoutWait.Unit.seconds, 0), (1, .seconds, 1), (45, .seconds, 45), (59, .seconds, 59),
            (60, .minutes, 1), (61, .minutes, 2), (2818, .minutes, 47), (3599, .minutes, 60),
            (3600, .hours, 1), (3601, .hours, 2),
        ] {
            let wait = LockoutWait(seconds: seconds)
            #expect(wait.unit == unit && wait.count == count)
        }
    }
}
