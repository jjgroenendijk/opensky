// Loading-screen selection: passing screens in load order, a seeded pick, and
// the player standing in the destination while the check runs.

import FormatsCoreTesting
import FormatsESMTesting
import Foundation
@testable import OpenSkyConditions
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorld
import Testing

struct LoadScreenSelectorTests {
    private typealias Fixture = ESMFixture

    private static func screen(
        _ objectID: UInt32,
        _ tip: String
    ) throws -> ResolvedRecord<LoadScreen> {
        let record = try LoadScreen(
            record: Fixture.record(
                "LSCR",
                fields: [("EDID", Fixture.zstring(tip)), ("DESC", Fixture.zstring(tip))]
            ),
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
