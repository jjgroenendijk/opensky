// Loading-screen selection: passing screens in load order, a seeded pick, and
// the player standing in the destination while the check runs.

import Foundation
@testable import OpenSkyConditions
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyLoading
import Testing

struct LoadScreenSelectorTests {
    private typealias Fixture = ESMFixture

    private static func screen(
        _ objectID: UInt32,
        _ tip: String,
        model: Bool = true,
        conditioned: Bool = false,
        mainMenu: Bool = false
    ) throws -> ResolvedRecord<LoadScreen> {
        var fields = [("EDID", Fixture.zstring(tip)), ("DESC", Fixture.zstring(tip))]
        if model {
            fields.append(("NNAM", Fixture.u32(0x60)))
        }
        if conditioned {
            fields.append(("CTDA", Data(QuestFixture.condition(functionIndex: 0).dropFirst(6))))
        }
        let record = try LoadScreen(
            record: Fixture.record("LSCR", flags: mainMenu ? 0x400 : 0, fields: fields),
            localized: false
        )
        return ResolvedRecord(
            id: ResolvedFormID(plugin: "Base.esm", objectID: objectID), record: record,
            sourcePlugin: "Base.esm"
        )
    }

    private static func screens() throws -> [ResolvedRecord<LoadScreen>] {
        try [screen(0x10, "Cave"), screen(0x11, "City"), screen(0x12, "Any")]
    }

    @Test func keepsPassingScreensInLoadOrder() throws {
        let selector = try LoadScreenSelector(screens: Self.screens()) { screen in
            screen.record.editorID == "City" ? "GetInCurrentLoc" : nil
        }
        #expect(selector.passing().map(\.record.editorID) == ["Cave", "Any"])
    }

    @Test func seededPickRepeatsAndStaysInThePassingSet() throws {
        let selector = try LoadScreenSelector(screens: Self.screens()) { _ in nil }
        var first = ConditionRandom(seed: 3)
        var second = ConditionRandom(seed: 3)
        let pick = selector.pick(random: &first)
        #expect(pick?.id == selector.pick(random: &second)?.id)
        #expect(pick != nil)
    }

    @Test func noPassingScreenPicksNothing() throws {
        let selector = try LoadScreenSelector(screens: Self.screens()) { _ in "GetIsID" }
        var random = ConditionRandom(seed: 1)
        #expect(selector.pick(random: &random) == nil)
    }

    @Test func onlyScreensWithAModelCountAndSpecificOnesWin() throws {
        let screens = try [
            Self.screen(0x10, "General"), Self.screen(
                0x11,
                "Bare",
                model: false,
                conditioned: true
            ),
            Self.screen(0x12, "Whiterun", conditioned: true)
        ]
        let selector = LoadScreenSelector(screens: screens) { _ in nil }
        #expect(selector.candidates(.gameLoaded).map(\.record.editorID) == ["Whiterun"])
        let general = LoadScreenSelector(screens: Array(screens.prefix(2))) { _ in nil }
        #expect(general.candidates(.gameLoaded).map(\.record.editorID) == ["General"])
    }

    @Test func beforeAGameOnlyMainMenuScreensCount() throws {
        let screens = try [Self.screen(0x10, "General"), Self.screen(0x11, "Menu", mainMenu: true)]
        let selector = LoadScreenSelector(screens: screens) { _ in "GetIsID" }
        #expect(selector.candidates(.noGame).map(\.record.editorID) == ["Menu"])
    }

    @Test func standardCheckPutsThePlayerInTheDestination() throws {
        let destination = ResolvedFormID(plugin: "Base.esm", objectID: 0x99)
        let check = LoadScreenSelector.conditionCheck(
            context: ConditionContext(),
            destination: destination
        )
        // A screen with no conditions always passes.
        #expect(try check(Self.screen(0x10, "Cave")) == nil)
        let data = ConditionDataResolution().with(
            sourcePlugin: "Base.esm",
            location: destination,
            of: .player
        )
        #expect(data.currentLocation(of: .player) == destination)
        #expect(data.sourcePlugin == "Base.esm")
    }
}
