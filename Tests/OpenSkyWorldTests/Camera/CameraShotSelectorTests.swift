// The CPTH walk over a synthetic tree: the first passing root wins, a child
// takes over from its parent, failures name their condition, and each CAMS
// action is one stage with its own seeded pick.

import FormatsCoreTesting
import FormatsESMTesting
import Foundation
@testable import OpenSkyConditions
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorld
import Testing

struct CameraShotSelectorTests {
    private typealias Fixture = ESMFixture

    private static func id(_ objectID: UInt32) -> ResolvedFormID {
        ResolvedFormID(plugin: "Base.esm", objectID: objectID)
    }

    private static func shot(_ formID: UInt32, action: UInt32) -> Data {
        let data = Fixture.u32(action, 0, 2, 0x02) + Fixture.f32(1, 1, 0.5, 2, 1, 50)
        return Fixture.recordBytes("CAMS", formID: formID, fields: [("DATA", data)])
    }

    private static func path(
        _ formID: UInt32,
        parent: UInt32,
        previous: UInt32,
        editorID: String,
        shots: [UInt32] = []
    ) -> Data {
        var fields: [(String, Data)] = [
            ("EDID", Fixture.zstring(editorID)), ("ANAM", Fixture.u32(parent, previous)),
            ("DATA", Fixture.u8(1))
        ]
        fields += shots.map { ("SNAM", Fixture.u32($0)) }
        return Fixture.recordBytes("CPTH", formID: formID, fields: fields)
    }

    /// Two roots. The first fails; under the second, a child holds three shots.
    private static func store() throws -> CameraPathStore {
        try CameraPathStore(plugins: [("Base.esm", Fixture.plugin(records: [
            shot(0x30, action: 0), shot(0x31, action: 0), shot(0x32, action: 2),
            shot(0x33, action: 0),
            path(0x40, parent: 0, previous: 0, editorID: "Blocked", shots: [0x33]),
            path(0x41, parent: 0, previous: 0x40, editorID: "Kills", shots: [0x33]),
            path(0x42, parent: 0x41, previous: 0, editorID: "Bow", shots: [0x30, 0x31, 0x32])
        ]))])
    }

    private static func check(failing names: Set<String>) -> CameraShotSelector.Check {
        { path in names.contains(path.editorID ?? "") ? "GetIsID" : nil }
    }

    @Test func childWithShotsTakesOverFromItsPassingParent() throws {
        let selector = try CameraShotSelector(
            store: Self.store(),
            check: Self.check(failing: ["Blocked"])
        )
        let selection = selector.select { _ in 0 }
        #expect(selection.path?.id == Self.id(0x42))
        #expect(selection.trace.map(\.verdict) == [.rejected("GetIsID"), .passed, .chosen])
        #expect(selection.trace.map(\.depth) == [0, 0, 1])
    }

    @Test func zoomOneDoesNotTurnAPathOff() throws {
        let selector = try CameraShotSelector(store: Self.store(), check: Self.check(failing: []))
        #expect(selector.select { _ in 0 }.path?.id == Self.id(0x40))
    }

    @Test func eachActionIsOneStageInOrder() throws {
        let selector = try CameraShotSelector(
            store: Self.store(),
            check: Self.check(failing: ["Blocked"])
        )
        var counts: [Int] = []
        let selection = selector.select { count in
            counts.append(count)
            return count - 1
        }
        #expect(counts == [2, 1])
        #expect(selection.sequence.map(\.id) == [Self.id(0x31), Self.id(0x32)])
        #expect(selection.chosen?.id == Self.id(0x31))
    }

    @Test func failingParentHidesItsChildren() throws {
        let selector = try CameraShotSelector(
            store: Self.store(), check: Self.check(failing: ["Blocked", "Kills"])
        )
        let selection = selector.select { _ in 0 }
        #expect(selection.path == nil)
        #expect(selection.trace.map(\.verdict) == [
            .rejected("GetIsID"),
            .rejected("GetIsID"),
            .notReached
        ])
    }

    @Test func seededPicksRepeat() throws {
        let selector = try CameraShotSelector(
            store: Self.store(),
            check: Self.check(failing: ["Blocked"])
        )
        var first = ConditionRandom(seed: 7)
        var second = ConditionRandom(seed: 7)
        #expect(
            selector.select(random: &first).sequence.map(\.id)
                == selector.select(random: &second).sequence.map(\.id)
        )
    }
}
