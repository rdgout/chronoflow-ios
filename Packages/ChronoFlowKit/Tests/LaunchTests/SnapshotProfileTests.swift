import SnapshotSupport
import Testing

@Suite struct SnapshotProfileTests {
    @Test func extremesKeepFullCoverageAndMidSizeDevicesUseTheCompactProfile() throws {
        for model in ["iPhone14,6", "iPhone18,5", "iPhone19,3", "iPhone19,4"] {
            let profile = try SnapshotProfile.current(model: model)
            #expect(profile.introTimes == [2400, 2450, 2700, 3200, 3300])
            #expect(profile.dynamicType.count == 12)
            #expect(profile.launchFrames.count == 11)
        }
        for model in ["iPhone18,3", "iPhone18,4", "iPhone19,2"] {
            let profile = try SnapshotProfile.current(model: model)
            #expect(profile.dynamicType == ["large", "xxLarge"])
            #expect(profile.introTimes == [2700, 3300])
            #expect(profile.launchFrames == ["ready-0", "ready-1400", "slow-2600", "welcome-2400", "reduceMotion-0"])
        }
        #expect(throws: (any Error).self) { try SnapshotProfile.current(model: "future iPhone") }
    }
}
