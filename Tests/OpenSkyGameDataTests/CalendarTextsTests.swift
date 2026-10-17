// The in-game date line: its word order, the 12-hour clock, the ordinal suffixes, and
// the string settings that supply every word.

import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct CalendarTextsTests {
    private static func english() throws -> CalendarTexts {
        let words: [String: GameSettingFixtureValue] = [
            "sDaySunday": .text("Sundas"), "sDayMonday": .text("Morndas"),
            "sMonthAugust": .text("Last Seed"), "sMonthJanuary": .text("Morning Star"),
            "sTimeAM": .text("AM"), "sTimePM": .text("PM"),
            "sFirstOrdSuffix": .text("st"), "sSecondOrdSuffix": .text("nd"),
            "sThirdOrdSuffix": .text("rd"), "sDefaultOrdSuffix": .text("th"),
            "sOf": .text(" of ")
        ]
        return try CalendarTexts.resolve(store: GameSettingFixture.store(words)) { text in
            guard case let .inline(value) = text else { return nil }
            return value
        }
    }

    @Test func theDateLineReadsLikeTheWaitMenu() throws {
        let texts = try Self.english()
        #expect(texts.dateLine(weekday: 0, hourOfDay: 8, day: 17, month: 8, year: 201)
            == "Sundas, 8:00 AM, 17th of Last Seed, 4E 201")
        #expect(texts.dateLine(weekday: 1, hourOfDay: 0.5, day: 1, month: 1, year: 202)
            == "Morndas, 12:30 AM, 1st of Morning Star, 4E 202")
        #expect(texts.dateLine(weekday: 0, hourOfDay: 13.75, day: 22, month: 8, year: 201)
            == "Sundas, 1:45 PM, 22nd of Last Seed, 4E 201")
    }

    @Test func ordinalsFollowEnglishRules() throws {
        let texts = try Self.english()
        #expect([1, 2, 3, 4, 11, 12, 13, 21, 23, 30].map(texts.ordinal) == [
            "1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "23rd", "30th"
        ])
    }

    @Test func aMissingWordFallsBackToItsEditorID() {
        #expect(CalendarTexts.vanilla.dateLine(
            weekday: 0, hourOfDay: 20, day: 3, month: 12, year: 201
        ) == "sDaySunday, 8:00 sTimePM, 3sThirdOrdSuffixsOfsMonthDecember, 4E 201")
    }
}
