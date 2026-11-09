#if DEBUG
    import AppCore
    import Foundation

    public enum MockAppSeed {
        struct Fixtures: Decodable {
            let settings: AccountSettings
            var trips: [TripFixture]
        }
        typealias TripFixture = MockTripFixtures.Template

        public static func make(now: Date, unverified: Bool = false, walkthroughSeen: Bool = false) throws
            -> MockServerState
        {
            var fixtures = try JSONDecoder().decode(Fixtures.self, from: MockTripFixtures.fixtureData())
            fixtures.trips = try fixtures.trips.enumerated().map {
                try rebase($0.element, index: $0.offset, now: now)
            }
            let trips = fixtures.trips.map { listItem($0, now: now) }
            let details = Dictionary(uniqueKeysWithValues: fixtures.trips.map { ($0.card.id, $0.detail) })
            var snapshot = AccountSnapshot.mockRegistration(
                id: MockScenarioValues.demoID, name: "Demo Traveller", email: MockScenarioValues.demoEmail,
                language: .en, now: now)
            snapshot.hasVerifiedEmail = !unverified
            snapshot.settings = fixtures.settings
            snapshot.readiness = MockSettings.readiness(fixtures.settings.bodyClock)
            snapshot.billing["checkout"] = .null
            snapshot.security = JSONObject([
                "canManagePasskeys": .bool(true), "canManageTwoFactor": .bool(true),
                "passkeys": .array(
                    ["iPhone 16", "MacBook Pro"].enumerated().map { index, name in
                        .object([
                            "id": .number(Decimal(index + 1)), "name": .string(name), "authenticator": .null,
                            "createdAtDiff": .null, "lastUsedAtDiff": .null,
                        ])
                    }),
                "passwordRules": .string("minlength: 10;"), "twoFactorEnabled": .bool(false),
                "twoFactorConfirmedAt": .null, "requiresConfirmation": .bool(true), "retryAfterSeconds": .null,
            ])
            let demo = MockServerAccount(
                snapshot: snapshot, password: MockScenarioValues.password, walkthroughSeen: walkthroughSeen,
                trips: trips, details: details)
            snapshot.id = MockScenarioValues.twoFactorID
            snapshot.email = MockScenarioValues.twoFactorEmail
            snapshot.security["passkeys"] = .array([])
            snapshot.security["twoFactorEnabled"] = .bool(true)
            snapshot.security["twoFactorConfirmedAt"] = .string(now.ISO8601Format())
            let twoFactor = MockServerAccount(
                snapshot: snapshot, password: MockScenarioValues.password,
                twoFactorCode: MockScenarioValues.twoFactorCode, recoveryCodes: [MockScenarioValues.recoveryCode],
                walkthroughSeen: walkthroughSeen,
                trips: trips, details: details)
            var state = MockServerState(accounts: [demo, twoFactor])
            state.seedAnchor = anchor(now: now)
            return state
        }

        static func anchor(now: Date) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: now)
        }

        static func refresh(_ stored: MockServerState, now: Date) throws -> MockServerState {
            var state = stored
            let anchor = anchor(now: now)
            let fixtures = try JSONDecoder().decode(Fixtures.self, from: MockTripFixtures.fixtureData())
            for accountID in [MockScenarioValues.demoID, MockScenarioValues.twoFactorID] {
                guard var account = state.accounts[accountID] else { continue }
                for (index, fixture) in fixtures.trips.enumerated() {
                    let id = fixture.card.id
                    guard let tripIndex = account.trips.firstIndex(where: { $0.card.id == id }),
                        let detail = account.details[id]
                    else { continue }
                    var trip = TripFixture(card: account.trips[tripIndex].card, detail: detail)
                    if stored.seedAnchor != anchor {
                        trip = try rebase(fixture, index: index, now: now)
                        var refreshed = trip.detail
                        refreshed.checkState.marks = detail.checkState.marks.map { mark in
                            var mark = mark
                            if let block = detail.plan.blocks.first(where: { $0.checkKey == mark.key }),
                                let key = refreshed.plan.blocks.first(where: { $0.id == block.id })?.checkKey
                            {
                                mark.key = key
                            }
                            return mark
                        }
                        refreshed.checkState.days = detail.checkState.days
                        trip = TripFixture(card: trip.card, detail: refreshed)
                    }
                    account.trips[tripIndex] = listItem(trip, now: now)
                    account.details[id] = trip.detail
                }
                state.accounts[accountID] = account
            }
            state.seedAnchor = anchor
            return state
        }

        private static func listItem(_ fixture: TripFixture, now: Date) -> TripListItem {
            var card = fixture.card
            let plan = fixture.detail.plan
            let first = plan.days.first!
            let last = plan.days.last!
            let start = first.startUtc
            let end = last.endUtc
            let status: TripStatus = now >= instant(end) ? .completed : now < instant(start) ? .upcoming : .active
            let next = plan.blocks.first {
                $0.actionable && $0.checkKey != nil && instant($0.endUtc) > now
            }
            card.progress = TripProgress(
                status: status, nextStep: next.map { TripCardNextStepView(text: $0.text, displayTz: $0.displayTz) })
            card.canComplete = status != .completed
            let keepOffline =
                status == .active
                || (status != .completed && instant(start) >= now && instant(start) <= now + 7 * 86400)
            return TripListItem(
                card: card, planInputHash: fixture.detail.checkState.planInputHash, planStartUtc: start,
                planStartZone: first.zones.first!.tz, planEndUtc: end, planEndDate: last.labelDate,
                preparationDays: plan.summary?.preparation.emitted ?? 0,
                adaptation: plan.summary?.adaptation, keepOffline: keepOffline,
                detailVersion: keepOffline ? fixture.detail.detailVersion : nil,
                checkState: keepOffline ? fixture.detail.checkState : nil)
        }

        static func instant(_ value: String) -> Date {
            let normalized = value.count == 17 ? value.replacingOccurrences(of: "Z", with: ":00Z") : value
            return ISO8601DateFormatter().date(from: normalized)!
        }
    }
#endif
