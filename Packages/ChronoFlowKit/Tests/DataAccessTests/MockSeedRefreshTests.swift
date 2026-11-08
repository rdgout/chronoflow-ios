import AppCore
import Foundation
import Testing

@testable import DataAccess

#if DEBUG
    @Suite struct MockSeedRefreshTests {
        @Test(arguments: [false, true])
        func walkthroughOverrideCoversBothSeededAccounts(seen: Bool) throws {
            let seed = try MockAppSeed.make(now: MockAppSeed.instant("2026-11-07T12:00:00Z"), walkthroughSeen: seen)
            for id in [MockScenarioValues.demoID, MockScenarioValues.twoFactorID] {
                let account = try #require(seed.accounts[id])
                #expect(account.walkthroughSeen == seen)
            }
        }

        @Test(arguments: [false, true])
        func restoresTenDayOldSeedWithoutLosingUserState(legacyAnchor: Bool) async throws {
            let now = MockAppSeed.instant("2026-11-07T12:00:00Z")
            let earlier = now - 10 * 86400
            var original = try MockAppSeed.make(now: earlier)
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("mock-refresh-\(UUID())")
            defer { try? FileManager.default.removeItem(at: root) }
            let store = FileMockStateStore(applicationSupport: root)
            let customID = UUID().uuidString.lowercased()
            for accountID in original.accounts.keys {
                var account = try #require(original.accounts[accountID])
                account.snapshot.name = "Kept"
                account.walkthroughSeen = true
                account.recoveryCodes = []
                var custom = try #require(account.trips.last)
                var customDetail = try #require(account.details[custom.card.id])
                custom.card.id = customID
                customDetail.trip.id = customID
                account.trips.append(custom)
                account.details[customID] = customDetail
                let seededID = account.trips[0].card.id
                var detail = try #require(account.details[seededID])
                let keys = detail.plan.blocks.filter { $0.actionable }.compactMap(\.checkKey)
                detail.checkState.marks = zip(keys.prefix(2), [CheckStatus.done, .skipped]).map {
                    CheckMark(key: $0.0, status: $0.1, markedAt: earlier.ISO8601Format())
                }
                account.details[seededID] = detail
                original.accounts[accountID] = account
            }
            original.sessions["retained-token"] = MockSession(
                accountID: MockScenarioValues.demoID, deviceID: mockDeviceID,
                expiresAt: now.timeIntervalSince1970 + 86400)
            try store.save(original)
            if legacyAnchor {
                var object = try #require(
                    JSONSerialization.jsonObject(with: Data(contentsOf: store.url)) as? [String: Any])
                object.removeValue(forKey: "seedAnchor")
                try JSONSerialization.data(withJSONObject: object).write(to: store.url)
            }
            let source = MockDataSource(store: store, now: { now }, sleep: { _ in }, bearer: { "retained-token" })
            #expect(try await source.fetchIdentity().name == "Kept")
            let trips = try await source.fetchTrips()
            #expect(Set(trips.dropLast().map { $0.card.progress.status }) == [.active, .upcoming, .completed])
            let restored = try #require(try store.load())
            #expect(restored.seedAnchor == MockAppSeed.anchor(now: now))
            #expect(restored.seedAnchor != original.seedAnchor)
            let fresh = try MockAppSeed.make(now: now)
            for (accountID, before) in original.accounts {
                let after = try #require(restored.accounts[accountID])
                #expect(after.snapshot == before.snapshot)
                #expect(after.walkthroughSeen == before.walkthroughSeen)
                #expect(after.recoveryCodes == before.recoveryCodes)
                #expect(after.trips.last == before.trips.last)
                #expect(after.details[customID] == before.details[customID])
                for (index, trip) in after.trips.dropLast().enumerated() {
                    let expected = try #require(fresh.accounts[accountID]?.trips[index])
                    #expect(trip.card.progress == expected.card.progress)
                    #expect(trip.card.canComplete == expected.card.canComplete)
                    #expect(trip.keepOffline == expected.keepOffline)
                    let detail = try #require(after.details[trip.card.id])
                    let expectedDetail = try #require(fresh.accounts[accountID]?.details[trip.card.id])
                    #expect(detail.plan == expectedDetail.plan)
                    #expect(detail.checkState.planInputHash == trip.planInputHash)
                    #expect(trip.checkState == (trip.keepOffline ? detail.checkState : nil))
                    #expect(trip.detailVersion == (trip.keepOffline ? detail.detailVersion : nil))
                }
                let id = after.trips[0].card.id
                let oldDetail = try #require(before.details[id])
                let newDetail = try #require(after.details[id])
                #expect(newDetail.checkState.marks.count == 2)
                for (old, new) in zip(oldDetail.checkState.marks, newDetail.checkState.marks) {
                    let blockIndex = try #require(oldDetail.plan.blocks.firstIndex { $0.checkKey == old.key })
                    #expect(new.key == newDetail.plan.blocks[blockIndex].checkKey)
                    #expect(new.status == old.status)
                    #expect(new.markedAt == old.markedAt)
                }
            }
            let restarted = MockDataSource(store: store, now: { now }, sleep: { _ in }, bearer: { "retained-token" })
            #expect(try await restarted.fetchTrips() == trips)
            #expect(try store.load() == restored)
        }
    }
#endif
