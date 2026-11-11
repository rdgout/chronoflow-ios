import Foundation
import Testing

struct BackoffPollTests {
    @Test func immediateSuccessDoesNotPause() {
        let result = BackoffPoll.until(
            timeout: 5, now: { 0 }, pause: { _ in Issue.record("Unexpected pause") }, condition: { true })
        #expect(result)
    }

    @Test func backsOffAndCapsSnapshotsWithoutExceedingDeadline() {
        var time = 0.0
        var pauses: [Double] = []
        var snapshots = 0
        let result = BackoffPoll.until(
            timeout: 5, now: { time },
            pause: {
                pauses.append($0)
                time += $0
            },
            condition: {
                snapshots += 1
                return false
            })
        #expect(!result)
        #expect(time == 5)
        #expect(pauses.prefix(3).elementsEqual([0.05, 0.075, 0.1125], by: { abs($0 - $1) < 0.0001 }))
        #expect(pauses.allSatisfy { $0 > 0 && $0 <= 1 })
        #expect(snapshots < 15)
    }

    @Test func snapshotCostCountsTowardTimeoutAndZeroOnlyChecksOnce() {
        for timeout in [0.0, 0.1] {
            var time = 0.0
            var snapshots = 0
            let result = BackoffPoll.until(
                timeout: timeout, now: { time }, pause: { _ in Issue.record("Late pause") },
                condition: {
                    snapshots += 1
                    time += 0.2
                    return false
                })
            #expect(!result)
            #expect(snapshots == 1)
        }
    }

    @Test func stopsAsSoonAsDelayedStateArrives() {
        var time = 0.0
        let result = BackoffPoll.until(
            timeout: 2, now: { time }, pause: { time += $0 }, condition: { time >= 0.1 })
        #expect(result)
        #expect(time < 0.2)
    }
}
