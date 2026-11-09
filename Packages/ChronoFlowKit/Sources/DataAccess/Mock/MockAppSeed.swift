#if DEBUG
    import AppCore
    import Foundation

    public enum MockAppSeed {
        struct Fixtures: Decodable {
            let settings: AccountSettings
            let trips: [TripFixture]
        }
        struct TripFixture: Decodable {
            var card: JSONObject
            let detail: TripDetail
        }

        public static func make(now: Date, unverified: Bool = false, walkthroughSeen: Bool = false) throws
            -> MockServerState
        {
            let fixtures = try JSONDecoder().decode(Fixtures.self, from: fixtureData())
            let trips = fixtures.trips.map { listItem($0, now: now) }
            let details = Dictionary(uniqueKeysWithValues: fixtures.trips.map { ($0.card["id"]!.string!, $0.detail) })
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
            guard case .array(let days) = plan["days"], case .array(let blocks) = plan["blocks"] else {
                preconditionFailure("Mock plan fixture must have days and blocks")
            }
            let first = days.first!.object!
            let last = days.last!.object!
            let start = first["startUtc"]!.string!
            let end = last["endUtc"]!.string!
            let status = now >= instant(end) ? "completed" : now < instant(start) ? "upcoming" : "active"
            let next = blocks.compactMap(\.object).first {
                $0["actionable"] == .bool(true) && $0["checkKey"]?.object != nil
                    && instant($0["endUtc"]!.string!) > now
            }
            card["progress"] = .object([
                "status": .string(status),
                "nextStep": next.map { .object(["text": $0["text"]!, "displayTz": $0["displayTz"]!]) } ?? .null,
            ])
            card["canComplete"] = .bool(status != "completed")
            let keepOffline =
                status == "active"
                || (status != "completed" && instant(start) >= now && instant(start) <= now + 7 * 86400)
            let summary = plan["summary"]!.object!
            guard case .array(let zones) = first["zones"],
                case .number(let emitted) = summary["preparation"]!.object!["emitted"]
            else {
                preconditionFailure("Mock plan must have zones and preparation days")
            }
            return TripListItem(
                card: card, planInputHash: fixture.detail.checkState.planInputHash, planStartUtc: start,
                planStartZone: zones.first!.object!["tz"]!.string!, planEndUtc: end,
                planEndDate: last["labelDate"]!.string!,
                preparationDays: NSDecimalNumber(decimal: emitted).intValue,
                adaptation: summary["adaptation"]?.object.map(JSONObject.init), keepOffline: keepOffline,
                detailVersion: keepOffline ? fixture.detail.detailVersion : nil,
                checkState: keepOffline ? fixture.detail.checkState : nil)
        }

        private static func instant(_ value: String) -> Date {
            let normalized = value.count == 17 ? value.replacingOccurrences(of: "Z", with: ":00Z") : value
            return ISO8601DateFormatter().date(from: normalized)!
        }
    }
#endif
