// The journal shell over two synthetic quests: what each panel control does or
// why it refuses, and the quest list the readouts show.

import OpenSkyEngineTesting
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
@testable import OpenSkyQuests
import OpenSkyQuestsInterface
import OpenSkyWorldState
import Testing

@MainActor
@Suite("Journal coordinator")
struct JournalCoordinatorTests {
    /// `MQ101` runs from the start and has objectives 10 and 20.
    /// `FreeformRiften` is dormant, with one start-up stage.
    static func runtime() throws -> QuestRuntime {
        try QuestRuntime(store: WorldStateStore(), quests: QuestFixture.store(
            QuestFixture.record(
                formID: 0x0100,
                fields: QuestFixture.editorID("MQ101")
                    + QuestFixture.general(flags: 0x0001, type: 1)
                    + QuestFixture.stage(10)
                    + QuestFixture.stage(20)
                    + QuestFixture.objective(10, text: "Find the horn")
                    + QuestFixture.objective(20, text: "Return the horn")
            )
                + QuestFixture.record(
                    formID: 0x0200,
                    fields: QuestFixture.editorID("FreeformRiften")
                        + QuestFixture.general(type: 6)
                        + QuestFixture.stage(5, flags: 0x02)
                )
        ))
    }

    /// The coordinator holds its world weakly, so each test keeps `world`.
    private func coordinator(_ world: FakeJournalWorld) -> JournalCoordinator {
        let coordinator = JournalCoordinator()
        coordinator.attach(world: world)
        return coordinator
    }

    @Test func withoutAQuestRuntimeEveryControlRefuses() {
        let world = FakeJournalWorld(runtime: nil)
        let coordinator = coordinator(world)
        coordinator.editorID = "MQ101"
        #expect(!coordinator.startSelectedQuest())
        #expect(coordinator.lastOutcome == "start: no quest index loaded")
        #expect(coordinator.entries().isEmpty)
        #expect(coordinator.questEditorIDs.isEmpty)
    }

    @Test func anEmptySelectionIsNamed() throws {
        let world = try FakeJournalWorld(runtime: Self.runtime())
        let coordinator = coordinator(world)
        coordinator.editorID = "   "
        #expect(!coordinator.stopSelectedQuest())
        #expect(coordinator.lastOutcome == "stop: no quest selected")
    }

    @Test func anUnknownQuestIsNamed() throws {
        let world = try FakeJournalWorld(runtime: Self.runtime())
        let coordinator = coordinator(world)
        coordinator.editorID = "MQ999"
        #expect(!coordinator.startSelectedQuest())
        #expect(coordinator.lastOutcome == "start: no loaded plugin defines MQ999")
    }

    @Test func startRunsTheTrimmedSelection() throws {
        let runtime = try Self.runtime()
        let world = FakeJournalWorld(runtime: runtime)
        let coordinator = coordinator(world)
        coordinator.editorID = " FreeformRiften "
        #expect(coordinator.startSelectedQuest())
        #expect(coordinator.lastOutcome?.hasPrefix("FreeformRiften: started") == true)
        #expect(try runtime.state(of: FormID(0x0200)).isRunning)
    }

    @Test func aNegativeStageIsRefusedBeforeTheRuntime() throws {
        let world = try FakeJournalWorld(runtime: Self.runtime())
        let coordinator = coordinator(world)
        coordinator.editorID = "MQ101"
        #expect(!coordinator.setSelectedQuestStage(-1))
        #expect(coordinator.lastOutcome == "stage -1 is not a stage index")
    }

    /// A `QuestError` is an outcome line, and the page still rebuilds.
    @Test func anUndeclaredStageIsARefusalLine() throws {
        let world = try FakeJournalWorld(runtime: Self.runtime())
        let coordinator = coordinator(world)
        coordinator.editorID = "MQ101"
        #expect(coordinator.setSelectedQuestStage(15))
        #expect(coordinator.lastOutcome?.hasPrefix("set stage 15 refused:") == true)
    }

    @Test func anObjectiveIsShownOnTheSelectedQuest() throws {
        let world = try FakeJournalWorld(runtime: Self.runtime())
        let coordinator = coordinator(world)
        coordinator.editorID = "MQ101"
        #expect(coordinator.setSelectedQuestObjective(10, displayed: true))
        #expect(coordinator.lastOutcome == "MQ101: objective 10 displayed")
        let entry = try #require(coordinator.selectedEntry())
        #expect(entry.state.objective(10).isDisplayed)
    }

    @Test func entriesListEveryJournalQuestInEditorIDOrder() throws {
        let world = try FakeJournalWorld(runtime: Self.runtime())
        let coordinator = coordinator(world)
        #expect(coordinator.questEditorIDs == ["FreeformRiften", "MQ101"])
        #expect(coordinator.entries().map(\.quest.editorID) == ["FreeformRiften", "MQ101"])
    }

    @Test func stringsLoadOnce() throws {
        let world = try FakeJournalWorld(runtime: Self.runtime())
        let coordinator = coordinator(world)
        _ = coordinator.strings
        _ = coordinator.strings
        #expect(world.stringLoads == 1)
    }
}

@MainActor
final class FakeJournalWorld: JournalWorld {
    let questRuntime: QuestRuntime?
    private(set) var stringLoads = 0

    init(runtime: QuestRuntime?) {
        questRuntime = runtime
    }

    func loadStrings() -> LocalizedStrings? {
        stringLoads += 1
        return nil
    }
}
