// The options of a new game at a place: their text forms, the reasons a text is
// refused, and what the settings remember.

import Foundation
import OpenSkyLaunch
import Testing

struct LaunchNewGameTests {
    private func isolatedDefaults() throws -> UserDefaults {
        let suite = "LaunchNewGameTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func aMarkerStartRoundTrips() {
        let start = LaunchStart.marker(
            worldspace: "Tamriel",
            plugin: "Skyrim.esm",
            objectID: 0x1A2B3
        )
        #expect(start.storedValue == "marker:Tamriel:Skyrim.esm:01A2B3")
        #expect(LaunchStart(storedValue: start.storedValue) == start)
        for text in [
            "marker:Tamriel:Skyrim.esm", "marker:Bad World:Skyrim.esm:1", "marker:Tamriel::1",
            "marker:Tamriel:Skyrim.esm:xyz", "marker:Tamriel:Skyrim.esm:1000000"
        ] {
            #expect(LaunchStart(storedValue: text) == nil, "\(text)")
        }
    }

    @Test func aPlaceFromTheListNeedsAPlace() {
        #expect(LaunchStartForm(kind: .place).validate() == .failure(.noPlace))
        let marker = LaunchStart.marker(worldspace: "Tamriel", plugin: "Skyrim.esm", objectID: 9)
        #expect(LaunchStartForm(marker).kind == .place)
        #expect(LaunchStartForm(marker).validate() == .success(marker))
        let cell = LaunchStart.cell("WhiterunBanneredMare")
        #expect(LaunchStartForm(cell).kind == .cell)
        #expect(LaunchStartForm(cell, fromList: true).kind == .place)
        #expect(LaunchStartForm(cell, fromList: true).validate() == .success(cell))
        #expect(LaunchStartForm(.normal, fromList: true).kind == .normal)
        #expect(!LaunchStartProblem.noPlace.reason.isEmpty)
        #expect(LaunchStartProblem.placeMissing("Riverwood").reason.contains("Riverwood"))
    }

    @Test func textValidatesIntoANewGame() {
        let text = LaunchNewGameText(
            start: "cell:WhiterunBanneredMare", hour: " 13.5 ", weather: " SkyrimClear ",
            story: "helgen-ralof", items: "mage", opensRaceMenu: false
        )
        let game = LaunchNewGame(
            start: .cell("WhiterunBanneredMare"), hour: 13.5, weather: "SkyrimClear",
            story: .helgenRalof, opensRaceMenu: false, items: .mage
        )
        #expect(text.validate() == .success(game))
        #expect(LaunchNewGameText(game).validate() == .success(game))
        #expect(LaunchNewGameText(start: "cell:QASmoke").validate()
            == .success(LaunchNewGame(start: .cell("QASmoke"))))
    }

    @Test func badTextGivesItsReason() {
        let good = LaunchNewGameText(start: "cell:QASmoke")
        var text = good
        text.start = "normal"
        #expect(text.validate() == .failure(.badStart("normal")))
        text = good
        text.hour = "25"
        #expect(text.validate() == .failure(.badHour))
        text.hour = "noon"
        #expect(text.validate() == .failure(.badHour))
        text = good
        text.weather = "Bad Weather"
        #expect(text.validate() == .failure(.badWeather))
        text = good
        text.story = "done"
        #expect(text.validate() == .failure(.badStory))
        text = good
        text.items = "king"
        #expect(text.validate() == .failure(.badItems))
        let problems: [LaunchNewGameProblem] = [
            .badStart("x"), .badHour, .badWeather, .badStory, .badItems
        ]
        #expect(Set(problems.map(\.reason)).count == problems.count)
    }

    @Test func everyPresetButNoneGivesItemsToWear() {
        #expect(LaunchItemPreset.none.items.isEmpty)
        for preset in LaunchItemPreset.allCases where preset != .none {
            #expect(preset.items.contains { $0.equips }, "\(preset)")
            #expect(preset.items.allSatisfy { !$0.editorID.isEmpty && $0.count >= 1 })
        }
        #expect(Set(LaunchItemPreset.allCases.map(\.title)).count == LaunchItemPreset.allCases
            .count)
        #expect(Set(LaunchStory.allCases.map(\.title)).count == LaunchStory.allCases.count)
    }

    @Test func theSettingsRememberTheOptions() throws {
        let defaults = try isolatedDefaults()
        let start = LaunchStart.cell("QASmoke")
        #expect(LaunchPreferences.savedNewGame(at: start, userDefaults: defaults)
            == LaunchNewGame(start: start))
        LaunchPreferences.remember(
            options: LaunchNewGameText(
                start: "", hour: "9", weather: "SkyrimClear", story: "helgen-hadvar",
                items: "thief", opensRaceMenu: false
            ),
            userDefaults: defaults
        )
        #expect(LaunchPreferences.savedNewGame(at: start, userDefaults: defaults) == LaunchNewGame(
            start: start, hour: 9, weather: "SkyrimClear", story: .helgenHadvar,
            opensRaceMenu: false, items: .thief
        ))
        #expect(LaunchPreferences.savedNewGameText(userDefaults: defaults).items == "thief")
    }

    @Test func aSavedOptionThatNoLongerReadsFallsBack() throws {
        let defaults = try isolatedDefaults()
        LaunchPreferences.remember(
            options: LaunchNewGameText(
                start: "", hour: "late", weather: "Bad Weather", story: "x", items: "y"
            ),
            userDefaults: defaults
        )
        let start = LaunchStart.exterior(worldspace: "Tamriel", x: 1, y: 2)
        #expect(LaunchPreferences.savedNewGame(at: start, userDefaults: defaults)
            == LaunchNewGame(start: start))
    }
}
