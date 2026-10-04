// The lookup stores over the records decoded for M23 to M28: hazards, idles,
// camera paths, story-manager nodes, head parts, scenes, and dialogue branches,
// over synthetic plugins.

import FormatsCoreTesting
import FormatsESMTesting
import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

struct RecordGraphStoreTests {
    private typealias Fixture = ESMFixture

    private static func id(_ objectID: UInt32) -> ResolvedFormID {
        ResolvedFormID(plugin: "Base.esm", objectID: objectID)
    }

    private static func plugin(_ records: [Data]) throws -> [(name: String, file: ESMFile)] {
        try [("Base.esm", Fixture.plugin(records: records))]
    }

    @Test func countsHazardLinksWithNoTarget() throws {
        let data = Fixture.u32(0) + Fixture.f32(1, 2, 3, 4) + Fixture.u32(0, 0x900, 0, 0, 0)
        let hazard = Fixture.recordBytes("HAZD", formID: 0x10, fields: [
            ("EDID", Fixture.zstring("Fire")), ("DATA", data)
        ])
        let store = try HazardStore(plugins: Self.plugin([hazard]))
        let resolved = try #require(store.hazards.record(editorID: "fire"))
        #expect(store.links(of: resolved).spell?.target == Self.id(0x900))
        #expect(store.danglingLinkCount == 1)
    }

    @Test func buildsTheIdleForestAndMarkerList() throws {
        let store = try IdleStore(plugins: Self.plugin([
            Fixture.recordBytes("AACT", formID: 0x08, fields: []),
            Self.idle(0x10, parent: 0x08, previous: 0, group: 3),
            Self.idle(0x12, parent: 0x10, previous: 0x11, group: 0),
            Self.idle(0x11, parent: 0x10, previous: 0, group: 0),
            Fixture.recordBytes("IDLM", formID: 0x20, fields: [("IDLA", Fixture.u32(0x11, 0x99))])
        ]))
        #expect(store.forest.children(of: Self.id(0x10)) == [Self.id(0x11), Self.id(0x12)])
        #expect(store.forest.orphans.isEmpty)
        #expect(store.roots(underAction: Self.id(0x08)).map(\.id) == [Self.id(0x10)])
        #expect(store.roots(inAnimationGroup: 3).map(\.id) == [Self.id(0x10)])
        let marker = try #require(store.markers.record(Self.id(0x20)))
        #expect(store.idles(of: marker).map(\.id) == [Self.id(0x11)])
    }

    @Test func resolvesCameraShotsAndCountsDanglingOnes() throws {
        let store = try CameraPathStore(plugins: Self.plugin([
            Fixture.recordBytes("CAMS", formID: 0x30, fields: []),
            Fixture.recordBytes("CPTH", formID: 0x40, fields: [
                ("ANAM", Fixture.u32(0, 0)), ("SNAM", Fixture.u32(0x30)), (
                    "SNAM",
                    Fixture.u32(0x31)
                )
            ])
        ]))
        let path = try #require(store.paths.record(Self.id(0x40)))
        #expect(store.shots(of: path).map(\.id) == [Self.id(0x30)])
        #expect(store.danglingShotCount == 1)
        #expect(store.forest.roots == [Self.id(0x40)])
    }

    @Test func groupsStoryManagerTreesByEventAndQuest() throws {
        let store = try StoryManagerStore(plugins: Self.plugin([
            Fixture.recordBytes("SMEN", formID: 0x50, fields: [("ENAM", Data("KILL".utf8))]),
            Fixture.recordBytes("SMQN", formID: 0x51, fields: [
                ("PNAM", Fixture.u32(0x50)), ("NNAM", Fixture.u32(0x70))
            ])
        ]))
        #expect(store.roots(forEvent: "KILL").map(\.id) == [Self.id(0x50)])
        #expect(store.nodes(startingQuest: Self.id(0x70)).map(\.id) == [Self.id(0x51)])
        #expect(store.event(of: Self.id(0x51)) == "KILL")
    }

    @Test func expandsExtraHeadPartsWithoutLoopingOnACycle() throws {
        let store = try CharacterPartStore(plugins: Self.plugin([
            Self.headPart(0x60, type: 3, extras: [0x61], color: 0x80),
            Self.headPart(0x61, type: 3, extras: [0x60, 0x62]),
            Fixture.recordBytes("CLFM", formID: 0x80, fields: [("CNAM", Fixture.u8(1, 2, 3, 0))])
        ]))
        #expect(store.headParts(ofType: .hair).count == 2)
        let expanded = store.expandedParts(Self.id(0x60))
        #expect(expanded.parts.map(\.id) == [Self.id(0x60), Self.id(0x61)])
        #expect(expanded.cycles == 1)
        #expect(expanded.danglingLinks == 1)
        let part = try #require(store.headParts.record(Self.id(0x60)))
        #expect(store.color(of: part)?.record.color == SIMD4(1, 2, 3, 0))
    }

    @Test func listsScenesPerQuestWithTheirTopics() throws {
        let scene = Fixture.recordBytes("SCEN", formID: 0x90, fields: [
            ("ANAM", Fixture.u16(0)), ("ALID", Fixture.i32(2)), ("DATA", Fixture.u32(0x91)),
            ("ANAM", Data()), ("PNAM", Fixture.u32(0x70))
        ])
        let store = try SceneStore(plugins: Self.plugin([scene]))
        let scenes = store.scenes(forQuest: Self.id(0x70))
        #expect(scenes.map(\.id) == [Self.id(0x90)])
        #expect(try store.dialogueTopics(of: #require(scenes.first)) == [Self.id(0x91)])
    }

    @Test func indexesDialogueBranchesByQuestAndTopic() throws {
        let file = try Fixture.plugin(records: [
            Fixture.recordBytes("DLBR", formID: 0xA0, fields: [
                ("QNAM", Fixture.u32(0x70)), ("SNAM", Fixture.u32(0xB0))
            ]),
            Fixture.recordBytes("DIAL", formID: 0xB0, fields: [("BNAM", Fixture.u32(0xA0))]),
            Fixture.recordBytes("DLVW", formID: 0xC0, fields: [("QNAM", Fixture.u32(0x70))])
        ])
        let store = DialogueStore(file: file, pluginName: "Base.esm")
        #expect(store.branches(forQuest: FormID(0x70)).map(\.formID) == [FormID(0xA0)])
        #expect(store.branch(ofTopic: FormID(0xB0))?.startingTopic == FormID(0xB0))
        #expect(store.topics(inBranch: FormID(0xA0)).map(\.formID) == [FormID(0xB0)])
        #expect(store.views(forQuest: FormID(0x70)).count == 1)
    }

    @Test func nameFollowsTheBaseDataTemplateFlag() throws {
        let template = try ActorBase(record: FactionFixture.decode(FactionFixture.actor(
            formID: 0x600, editorID: "Template",
            aiData: Fixture.field("FULL", Fixture.zstring("Hulda"))
        )), localized: false)
        let inheriting = try FactionFixture.actorBase(
            formID: 0x601, editorID: "Inheriting", templateFlags: 0x0080, template: 0x600
        )
        let own = try FactionFixture.actorBase(
            formID: 0x602, editorID: "Own", templateFlags: 0x0010, template: 0x600
        )
        let resolver = ActorTemplateResolver(
            actors: [0x600: template, 0x601: inheriting, 0x602: own],
            leveledActors: [:]
        )
        #expect(try resolver.resolveName(base: FormID(0x601)).value == .inline("Hulda"))
        #expect(try resolver.resolveName(base: FormID(0x602)).value == nil)
    }

    @Test func combatStyleFollowsTheAIDataTemplateFlag() throws {
        let template = try ActorBase(record: FactionFixture.decode(FactionFixture.actor(
            formID: 0x600, editorID: "Template",
            aiData: Fixture.field("ZNAM", Fixture.u32(0xD0))
        )), localized: false)
        let inheriting = try FactionFixture.actorBase(
            formID: 0x601, editorID: "Inheriting", templateFlags: 0x0010, template: 0x600
        )
        let resolver = ActorTemplateResolver(
            actors: [0x600: template, 0x601: inheriting],
            leveledActors: [:]
        )
        let style = try resolver.resolveCombatStyle(base: FormID(0x601))
        #expect(style.value == FormID(0xD0))
        #expect(style.source == FormID(0x600))
    }

    private static func idle(
        _ formID: UInt32,
        parent: UInt32,
        previous: UInt32,
        group: UInt8
    ) -> Data {
        Fixture.recordBytes("IDLE", formID: formID, fields: [
            ("ANAM", Fixture.u32(parent, previous)),
            ("DATA", Fixture.u8(0, 0, 0, group) + Fixture.u16(0))
        ])
    }

    private static func headPart(
        _ formID: UInt32,
        type: UInt32,
        extras: [UInt32],
        color: UInt32 = 0
    ) -> Data {
        Fixture.recordBytes(
            "HDPT",
            formID: formID,
            fields: [("PNAM", Fixture.u32(type))]
                + extras.map { ("HNAM", Fixture.u32($0)) } + [("CNAM", Fixture.u32(color))]
        )
    }
}
