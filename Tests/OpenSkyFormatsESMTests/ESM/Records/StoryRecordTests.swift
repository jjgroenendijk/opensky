// DLBR, DLVW, the story-manager nodes, and SCEN over synthetic fields.
// Layout sources: xEdit wbDefinitionsTES5.pas; see docs/formats/dialogue.md,
// docs/formats/story-manager.md and docs/formats/scenes.md.

import FormatsCoreTesting
import FormatsESMTesting
import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import TagsTesting
import Testing

@Suite(.tags(.parser))
struct StoryRecordTests {
    private typealias Fixture = ESMFixture

    private static func condition() -> Data {
        QuestFixture.condition(functionIndex: 58).dropFirst(6)
    }

    @Test func decodesDialogueBranchAndView() throws {
        let branch = try DialogueBranch(record: Fixture.record("DLBR", fields: [
            ("QNAM", Fixture.u32(0x10)), ("TNAM", Fixture.u32(1)),
            ("DNAM", Fixture.u32(0x03)), ("SNAM", Fixture.u32(0x11))
        ]))
        #expect(branch.quest == FormID(0x10))
        #expect(branch.flags.contains(.topLevel))
        #expect(branch.flags.contains(.blocking))
        #expect(branch.startingTopic == FormID(0x11))
        #expect(branch.skipped.isEmpty)

        let view = try DialogueView(record: Fixture.record("DLVW", fields: [
            ("QNAM", Fixture.u32(0x10)), ("BNAM", Fixture.u32(0x20)), ("BNAM", Fixture.u32(0x21)),
            ("TNAM", Fixture.u32(0x30)), ("ENAM", Fixture.u32(7)), ("DNAM", Fixture.u8(1)),
            ("XXYZ", Data())
        ]))
        #expect(view.branches == [FormID(0x20), FormID(0x21)])
        #expect(view.topics == [FormID(0x30)])
        #expect(view.showsAllText)
        #expect(view.skipped.counts[.unknownField("XXYZ")] == 1)
    }

    @Test func decodesStoryManagerQuestNodeAndTalliesCountMismatch() throws {
        let node = try StoryManagerNode(record: Fixture.record("SMQN", fields: [
            ("PNAM", Fixture.u32(0x40)), ("SNAM", Fixture.u32(0)),
            ("CTDA", Self.condition()),
            ("DNAM", Fixture.u32(0x02)), ("XNAM", Fixture.u32(1)), ("MNAM", Fixture.u32(1)),
            ("QNAM", Fixture.u32(3)),
            ("NNAM", Fixture.u32(0x50)), ("FNAM", Fixture.u32(1)), ("RNAM", Fixture.f32(24)),
            ("NNAM", Fixture.u32(0x51))
        ]))
        #expect(node.kind == .quest)
        #expect(node.parent == FormID(0x40))
        #expect(node.previousSibling == nil)
        #expect(node.conditions.count == 1)
        #expect(node.quests.map(\.quest) == [FormID(0x50), FormID(0x51)])
        #expect(node.quests[0].resetsAfterFullDay == true)
        #expect(node.quests[0].hoursUntilReset == 24)
        #expect(node.quests[1].hoursUntilReset == nil)
        #expect(node.skipped.counts[.mismatch("QNAM count differs from NNAM entries")] == 1)
    }

    @Test func decodesStoryManagerEventNode() throws {
        let node = try StoryManagerNode(record: Fixture.record("SMEN", fields: [
            ("ENAM", Data("KILL".utf8))
        ]))
        #expect(node.kind == .event)
        #expect(node.event == "KILL")
        #expect(throws: ESMError.self) {
            _ = try StoryManagerNode(record: Fixture.record("SMXX", fields: []))
        }
    }

    @Test func decodesScenePhasesActorsAndActions() throws {
        let scene = try Scene(record: Fixture.record("SCEN", fields: Self.sceneFields))
        #expect(scene.editorID == "TestScene")
        #expect(scene.phases.count == 1)
        #expect(scene.phases[0].name == "Loop01")
        #expect(scene.phases[0].startConditions.count == 1)
        #expect(scene.phases[0].completionConditions.count == 1)
        #expect(scene.phases[0].editorWidth == 200)
        #expect(scene.actors.map(\.aliasID) == [3])
        #expect(scene.actors[0].behaviorFlags == 0x04)
        #expect(scene.actions.count == 2)
        #expect(scene.actions[0].payload == .dialogue(SceneDialogue(topic: FormID(0x70))))
        #expect(scene.actions[0].startPhase == 0)
        #expect(scene.actions[1].payload == .timer(5))
        #expect(scene.quest == FormID(0x60))
        #expect(scene.actorBehavior?.combat == 1)
        #expect(scene.skipped.isEmpty)
    }

    @Test func openPhaseAtRecordEndIsTallied() throws {
        let scene = try Scene(record: Fixture.record("SCEN", fields: [
            ("HNAM", Data()), ("NAM0", Fixture.zstring("Open"))
        ]))
        #expect(scene.phases.isEmpty)
        #expect(scene.skipped.counts[.mismatch("SCEN run left open at record end")] == 1)
    }

    private static let sceneFields: [(String, Data)] = [
        ("EDID", Fixture.zstring("TestScene")), ("FNAM", Fixture.u32(0)),
        ("HNAM", Data()), ("NAM0", Fixture.zstring("Loop01")),
        ("CTDA", condition()), ("NEXT", Data()), ("CTDA", condition()), ("NEXT", Data()),
        ("WNAM", Fixture.u32(200)), ("HNAM", Data()),
        ("ALID", Fixture.i32(3)), ("LNAM", Fixture.u32(0)), ("DNAM", Fixture.u32(0x04)),
        ("ANAM", Fixture.u16(0)), ("ALID", Fixture.i32(3)), ("INAM", Fixture.u32(1)),
        ("SNAM", Fixture.u32(0)), ("ENAM", Fixture.u32(0)), ("DATA", Fixture.u32(0x70)),
        ("ANAM", Data()),
        ("ANAM", Fixture.u16(2)), ("SNAM", Fixture.u32(0)), ("SNAM", Fixture.f32(5)),
        ("ANAM", Data()),
        ("PNAM", Fixture.u32(0x60)), ("INAM", Fixture.u32(2)), ("VNAM", Fixture.u32(0, 1, 0, 0))
    ]
}
