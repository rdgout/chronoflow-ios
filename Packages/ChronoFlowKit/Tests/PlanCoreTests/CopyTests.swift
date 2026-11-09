import AppCore
import Foundation
import Testing

@testable import PlanCore

struct CopyTests {
    struct Golden: Decodable {
        var id: String
        var kind: String
        var locale: String
        var expected: String
        var value: CopyArgValue
        var zone: String?
        var timeFormat: String?
        var style: String?
    }

    @Test func intlGoldens() async throws {
        let formatter = CopyLineFormatter(catalog: try await CopyCatalog.load())
        let url = Bundle.module.url(forResource: "intl-cases", withExtension: "json", subdirectory: "Fixtures")!
        let cases = try JSONDecoder().decode([Golden].self, from: Data(contentsOf: url))
        #expect(cases.count == 44)
        for item in cases {
            let language = Language(rawValue: item.locale)
            let options = CopyFormat(language: language, timeFormat: TimeFormat(rawValue: item.timeFormat ?? "24"))
            let actual: String
            switch item.kind {
            case "instant": actual = formatter.formatInstant(item.value.text, options: options, zone: item.zone)
            case "date": actual = formatter.formatDate(item.value.text, language: language, zone: item.zone!)
            case "minutes":
                actual = formatter.formatMinutes(
                    item.value.number, language: language, duration: item.style == "duration")
            default: actual = formatter.formatOffset(item.value.number, language: language)
            }
            #expect(actual == item.expected, "\(item.id): \(actual)")
        }
    }

    @Test func caffeineCases() async throws {
        let f = CopyLineFormatter(catalog: try await CopyCatalog.load())
        let values = [1, 2, 3, 4, 5, 8]
        let en = [
            "half a cup of coffee", "one cup of coffee", "1½ cups of coffee", "two cups of coffee", "2½ cups of coffee",
            "4 cups of coffee",
        ]
        let nl = [
            "een half kopje koffie", "één kopje koffie", "1½ kopje koffie", "twee kopjes koffie", "2½ kopjes koffie",
            "4 kopjes koffie",
        ]
        let chips = ["½ coffee", "1 coffee", "1½ coffees", "2 coffees", "2½ coffees", "4 coffees"]
        for (i, halves) in values.enumerated() {
            let amount = DrinkAmountView(drink: .filterCoffee, halves: halves)
            #expect(f.drink(amount, language: .en) == en[i])
            #expect(f.drink(amount, language: .nl) == nl[i])
            #expect(f.drink(amount, language: .en, chip: true) == chips[i])
            #expect(f.drink(amount, language: .nl, chip: true).hasSuffix(" koffie"))
        }
        for drink in [Drink.tea, .cola, .energyDrink, .espresso] {
            for halves in values {
                for lang in [Language.en, .nl] {
                    let value = f.drink(DrinkAmountView(drink: drink, halves: halves), language: lang)
                    #expect(
                        !value.isEmpty && !value.contains("|") && !value.contains(":amount") && !value.contains("{"))
                }
            }
        }
        let amount = CaffeineAmountView(
            mg: 125, drinks: [.init(drink: .filterCoffee, halves: 3), .init(drink: .tea, halves: 5)])
        #expect(f.caffeineAmount(amount, language: .en) == "1½ cups of coffee or 2½ cups of tea (125 mg)")
        #expect(f.caffeineAmount(amount, language: .nl) == "1½ kopje koffie of 2½ kopjes thee (125 mg)")
        #expect(f.caffeineAmount(.init(mg: 125, drinks: []), language: .nl) == "125 mg")
        #expect(f.usualDrinks(1, language: .nl) == "1 drankje")
        #expect(f.usualDrinks(2, language: .en) == "2 drinks")
    }

    @Test func argumentsPluralAndFallback() async throws {
        let f = CopyLineFormatter(catalog: try await CopyCatalog.load())
        for language in [Language.en, .nl] {
            let options = CopyFormat(language: language)
            let line = CopyLine(
                key: ":count booked nights", args: [.standard(.init(name: "count", kind: .count, value: .number(2)))])
            #expect(f.format(line, options: options) == (language == .en ? "2 booked nights" : "2 geboekte nachten"))
            let one = CopyLine(key: line.key, args: [.standard(.init(name: "count", kind: .count, value: .number(1)))])
            #expect(f.format(one, options: options) == (language == .en ? "1 booked night" : "1 geboekte nacht"))
            let unknown = CopyLine(
                key: "Unknown :place and :place2",
                args: [.standard(.init(name: "place", kind: .place, value: .string("Tokyo")))])
            #expect(f.format(unknown, options: options) == "Unknown Tokyo and :place2")
            let caffeine = CopyLine(
                key: "Coffee nap: have about :mg, then nap.",
                args: [.caffeine(.init(name: "mg", kind: .milligrams, value: 125, drinks: [], usualDrinks: 2))])
            #expect(f.format(caffeine, options: options).contains(language == .en ? "2 drinks" : "2 drankjes"))
        }
        let catalog = try CopyCatalog(
            data: Data(
                #"{"entries":[{"key":"Hello :name","arguments":["name"],"languages":{"en":{"kind":"single","formats":["Hello %1$@"]}}}]}"#
                    .utf8))
        #expect(catalog.text("Hello :name", language: .nl, arguments: ["name": "Ada"]) == "Hello Ada")
        let annotated = CopyFormat(language: .en, displayZone: "UTC", annotateInstantZone: true)
        #expect(
            f.formatArgument(
                .init(name: "at", kind: .instant, value: .string("2026-01-15T00:00Z"), tz: "Asia/Tokyo"),
                options: annotated) == "09:00 (Tokyo)")
        #expect(
            f.formatArgument(.init(name: "text", kind: .text, value: .string("verbatim")), options: annotated)
                == "verbatim")
        #expect(
            f.formatArgument(.init(name: "n", kind: .milligrams, value: .number(125)), options: annotated) == "125 mg")
    }
}
