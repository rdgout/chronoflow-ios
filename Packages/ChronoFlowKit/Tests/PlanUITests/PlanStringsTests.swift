import AppCore
import Testing

@testable import PlanUI

@Suite @MainActor struct PlanStringsTests {
    @Test func todayHeadingsAndSpokenProgressAreDutch() {
        #expect(PlanStrings.text("Right now", language: .nl) == "Op dit moment")
        #expect(PlanStrings.text("Up next", language: .nl) == "Hierna")
        #expect(
            PlanStrings.text("{{done}} of {{total}} done", language: .nl, ["done": "3", "total": "7"])
                == "3 van 7 gedaan")
    }

    @Test func futureCountsAndPreparationNoteUseCatalogPlurals() {
        #expect(PlanStrings.text("In {{count}} days", language: .en, count: 1) == "In 1 day")
        #expect(PlanStrings.text("In {{count}} days", language: .en, count: 6) == "In 6 days")
        #expect(PlanStrings.text("In {{count}} days", language: .nl, count: 1) == "Over 1 dag")
        #expect(PlanStrings.text("In {{count}} days", language: .nl, count: 6) == "Over 6 dagen")
        let key = "Your {{count}} preparation days start on {{date}}."
        #expect(
            PlanStrings.text(key, language: .en, ["date": "Fri 9 Oct"], count: 1)
                == "Your preparation day starts on Fri 9 Oct.")
        #expect(
            PlanStrings.text(key, language: .en, ["date": "Fri 9 Oct"], count: 3)
                == "Your 3 preparation days start on Fri 9 Oct.")
        #expect(
            PlanStrings.text(key, language: .nl, ["date": "vr 9 okt"], count: 1)
                == "Je voorbereidingsdag begint op vr 9 okt.")
        #expect(
            PlanStrings.text(key, language: .nl, ["date": "vr 9 okt"], count: 3)
                == "Je 3 voorbereidingsdagen beginnen op vr 9 okt.")
        #expect(PlanStrings.text("{{count}} skipped", language: .nl, count: 1) == "1 overgeslagen")
    }
}
