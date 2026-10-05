// The story-manager walk over a synthetic tree: Root, a KILL event node, a quest
// node with two quests, and a fallback quest node after it. Plus the `.seq`
// session-start pass.

import EngineTesting
import FormatsTesting
import Foundation
@testable import OpenSkyConditions
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyQuests
@testable import OpenSkyQuestsInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct StoryManagerTests {
    static let first = FormID(0x0100)
    static let second = FormID(0x0101)
    static let victim = ReferenceKey.plugin(name: "test.esm", objectID: 0x0500)
    static let hour = 3600.0

    static func quests() throws -> QuestStore {
        let victimAlias = QuestFixture.alias(
            id: 0, name: "Victim",
            fill: QuestFixture.word("ALFE", FourCC("KILL").rawValue)
                + QuestFixture.word("ALFD", UInt32(StoryEventData.Member.actor2.rawValue))
        )
        return try QuestFixture.store(
            QuestFixture.record(
                formID: 0x0100,
                fields: QuestFixture.editorID("KillFirst")
                    + QuestFixture.general() + QuestFixture.stage(10, flags: 0x02) + victimAlias
            )
                + QuestFixture.record(
                    formID: 0x0101,
                    fields: QuestFixture.editorID("KillSecond")
                        + QuestFixture.general()
                )
                + QuestFixture.record(
                    formID: 0x0102,
                    fields: QuestFixture.editorID("KillFallback")
                        + QuestFixture.general()
                )
        )
    }

    static func story(flags: UInt32 = 0, questsToRun: UInt32 = 1) throws -> StoryManagerStore {
        try StoryManagerStore(plugins: [("Test.esm", ESMFixture.plugin(records: [
            ESMFixture.recordBytes(
                "SMBN",
                formID: 0x50,
                fields: [("EDID", ESMFixture.zstring("Root"))]
            ),
            ESMFixture.recordBytes("SMEN", formID: 0x51, fields: [
                ("EDID", ESMFixture.zstring("KillEvent")), ("PNAM", ESMFixture.u32(0x50)),
                ("ENAM", Data("KILL".utf8))
            ]),
            ESMFixture.recordBytes("SMQN", formID: 0x52, fields: [
                ("EDID", ESMFixture.zstring("KillQuests")), ("PNAM", ESMFixture.u32(0x51)),
                ("DNAM", ESMFixture.u32(flags)), ("MNAM", ESMFixture.u32(questsToRun)),
                ("NNAM", ESMFixture.u32(0x100)), ("FNAM", ESMFixture.u32(0)),
                ("RNAM", ESMFixture.f32(24)), ("NNAM", ESMFixture.u32(0x101))
            ]),
            ESMFixture.recordBytes("SMQN", formID: 0x53, fields: [
                ("EDID", ESMFixture.zstring("KillFallbackNode")), ("PNAM", ESMFixture.u32(0x51)),
                ("SNAM", ESMFixture.u32(0x52)), ("NNAM", ESMFixture.u32(0x102))
            ])
        ]))])
    }

    static func runtime(
        _ store: WorldStateStore,
        story: StoryManagerStore,
        hours: Double = 0
    ) throws -> StoryManagerRuntime {
        var context = ConditionContext()
        context.clock = GameClock(totalGameSeconds: hours * hour)
        return try StoryManagerRuntime(
            store: store,
            quests: QuestRuntime(store: store, quests: quests()),
            story: story,
            context: context,
            registry: ConditionFunctionRegistry()
        )
    }

    static var kill: StoryEventData {
        var event = StoryEventData(event: "KILL")
        event.actor2 = victim
        return event
    }

    /// The first quest of the first node starts, fills its alias from the
    /// event, runs its start-up stage, and consumes the event.
    @Test func theFirstQuestNodeStartsOneQuestAndConsumesTheEvent() throws {
        let store = WorldStateStore()
        let runtime = try Self.runtime(store, story: Self.story())
        let walk = runtime.fire(Self.kill)
        #expect(walk.startedQuests == [Self.first])
        #expect(walk.steps.map(\.outcome) == [
            .entered, .entered, .questStarted(Self.first),
            .questRejected(Self.second, .limitReached), .consumed
        ])
        #expect(try runtime.quests.state(of: Self.first).isStageDone(10))
        #expect(try runtime.quests.aliasState(of: Self.first).reference(forAlias: 0) == Self.victim)
        #expect(runtime.state(of: Self.first)?.startCount == 1)
    }

    @Test func numQuestsToRunStartsSeveral() throws {
        let runtime = try Self.runtime(
            WorldStateStore(), story: Self.story(flags: 0x0004_0000, questsToRun: 2)
        )
        #expect(runtime.fire(Self.kill).startedQuests == [Self.first, Self.second])
    }

    /// A running quest is passed over with its reason, and the next one starts.
    @Test func aRunningQuestIsRejectedWithItsReason() throws {
        let store = WorldStateStore()
        let runtime = try Self.runtime(store, story: Self.story())
        try runtime.quests.startQuest(Self.first)
        let walk = runtime.fire(Self.kill)
        #expect(walk.steps.map(\.outcome).contains(.questRejected(Self.first, .alreadyRunning)))
        #expect(walk.startedQuests == [Self.second])
    }

    /// Hours until reset hold a quest back, also after a restore, until they pass.
    @Test func hoursUntilResetHoldAcrossARestore() throws {
        let store = WorldStateStore()
        let story = try Self.story()
        let runtime = try Self.runtime(store, story: story)
        runtime.fire(Self.kill)
        try runtime.quests.stopQuest(Self.first)

        let restored = WorldStateStore()
        restored.restore(from: store.snapshot())
        let early = try Self.runtime(restored, story: story, hours: 23).fire(Self.kill)
        #expect(early.steps.map(\.outcome).contains(.questRejected(Self.first, .resetPending)))
        #expect(early.startedQuests == [Self.second])

        let late = try Self.runtime(restored, story: story, hours: 25)
        try late.quests.stopQuest(Self.second)
        #expect(late.fire(Self.kill).startedQuests == [Self.first])
        #expect(late.state(of: Self.first)?.startCount == 2)
    }

    /// An event with no node walks nothing.
    @Test func anEventWithoutNodesStartsNothing() throws {
        let runtime = try Self.runtime(WorldStateStore(), story: Self.story())
        let walk = runtime.fire(StoryEventData(event: "CLOC"))
        #expect(walk.steps.isEmpty)
        #expect(walk.startedQuests.isEmpty)
    }

    @Test func eventNodesAreFoundUnderTheRootBranch() throws {
        let story = try Self.story()
        #expect(story.events == ["KILL"])
        #expect(story.roots(forEvent: "KILL").map(\.record.editorID) == ["KillEvent"])
    }

    // MARK: - Session start

    static func list(_ ids: [UInt32]) throws -> PluginQuestList {
        let data = ids.reduce(Data()) { data, id in
            data + withUnsafeBytes(of: id.littleEndian) { Data($0) }
        }
        let list = Result { () throws(StartGameQuestListError) in
            try StartGameQuestList(data: data)
        }
        return PluginQuestList(plugin: "Test.esm", masters: [], list: list)
    }

    /// The pass starts a listed quest once; a second pass finds its state and starts nothing.
    @Test func theSessionStartPassRunsOnce() throws {
        let runtime = try QuestRuntime(store: WorldStateStore(), quests: Self.quests())
        let lists = try [Self.list([0x0101, 0x0999])]
            + [PluginQuestList(plugin: "Missing.esp", masters: ["Test.esm"], list: nil)]
        let first = runtime.runSessionStart(lists: lists, starter: nil)
        #expect(first.entries.map(\.outcome) == [.started, .notInQuestStore])
        #expect(first.missingLists == ["Missing.esp"])
        #expect(try runtime.state(of: Self.second).isRunning)
        let second = runtime.runSessionStart(lists: lists, starter: nil)
        #expect(second.entries.map(\.outcome) == [.alreadyHasState, .notInQuestStore])
        #expect(second.startedCount == 0)
    }

    /// A list that writes its plugin's own quest under a master's index, as
    /// `HearthFires.seq` does, still starts that quest.
    @Test func aListedQuestFallsBackToTheListsOwnPlugin() throws {
        let quests = try QuestStore(plugins: [
            (name: "Base.esm", file: ESMFixture.plugin(records: [])),
            (
                name: "Test.esm",
                file: ESMFixture.plugin(
                    masters: ["Base.esm", "Patch.esm"],
                    records: [QuestFixture.record(
                        formID: 0x0200_0100,
                        fields: QuestFixture.editorID("OwnQuest") + QuestFixture.general()
                    )]
                )
            )
        ])
        let runtime = QuestRuntime(store: WorldStateStore(), quests: quests)
        let data = withUnsafeBytes(of: UInt32(0x0100_0100).littleEndian) { Data($0) }
        let list = PluginQuestList(
            plugin: "Test.esm",
            masters: ["Base.esm", "Patch.esm"],
            list: Result { () throws(StartGameQuestListError) in
                try StartGameQuestList(data: data)
            }
        )
        let report = runtime.runSessionStart(lists: [list], starter: nil)
        #expect(report.entries.map(\.outcome) == [.started])
        #expect(report.entries.first?.quest == ResolvedFormID(plugin: "Test.esm", objectID: 0x100))
        #expect(report.entries.first?.editorID == "OwnQuest")
    }
}
