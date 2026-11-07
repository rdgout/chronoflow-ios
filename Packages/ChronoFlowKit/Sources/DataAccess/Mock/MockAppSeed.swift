#if DEBUG
    import AppCore
    import Foundation

    public enum MockAppSeed {
        struct Fixtures: Decodable {
            let settings: AccountSettings
            var trips: [TripFixture]
        }
        struct TripFixture: Decodable {
            var card: TripCardView
            let detail: TripDetail
        }

        public static func make(now: Date, unverified: Bool = false, walkthroughSeen: Bool = false) throws
            -> MockServerState
        {
            var fixtures = try JSONDecoder().decode(Fixtures.self, from: fixtureData())
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
            return MockServerState(accounts: [demo, twoFactor])
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
