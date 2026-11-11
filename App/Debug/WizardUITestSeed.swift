#if DEBUG
    import AppCore
    import DataAccess
    import Foundation

    nonisolated func wizardUITestSeed(_ original: MockServerState) -> MockServerState {
        guard ProcessInfo.processInfo.environment["CF_WIZARD_TEST_REVIEW"] == "1" else { return original }
        var seed = original
        for id in seed.accounts.keys {
            seed.accounts[id]?.snapshot.settings.sleepAnswered = false
            seed.accounts[id]?.snapshot.settings.bodyClock["habitualBed"] = .string("23:30")
            seed.accounts[id]?.snapshot.settings.bodyClock["habitualWake"] = .string("07:15")
            seed.accounts[id]?.snapshot.settings.bodyClock["chronotype"] = .null
            seed.accounts[id]?.snapshot.settings.bodyClock["ageBand"] = .null
            for field in ["shiftWork", "excludeCaffeine", "flightMovementBreaks"] {
                seed.accounts[id]?.snapshot.settings.bodyClock[field] = .bool(false)
            }
        }
        return seed
    }
#endif
