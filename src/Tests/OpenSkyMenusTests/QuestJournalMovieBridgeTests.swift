// Quests-page bridge coverage over a synthetic runtime. The measured node
// names, `EntriesA` and `iSelectedIndex` (-1 for none) are installed in code,
// so the tests check the bridge against its contract.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsSWF
import OpenSkyFormatsTesting
@testable import OpenSkyMenus
import Testing

@Suite("Quest journal movie bridge")
struct QuestJournalMovieBridgeTests {
    private struct Harness {
        let runtime: SWFMovieRuntime
        let titleList: SWFDisplayObject
    }

    /// Builds `/QuestJournalFader/Menu_mc/QuestsFader/Page_mc/...` down to the
    /// two lists, so the bridge's pinned paths are what is exercised.
    private func harness() throws -> Harness {
        let runtime = try SWFRuntimeFixture.started(tags: [SWFDisplayFixture.showFrameTag])
        var parent = runtime.root
        for name in ["QuestJournalFader", "Menu_mc", "QuestsFader", "Page_mc"] {
            parent = Self.clip(named: name, under: parent)
        }
        let titleHolder = Self.clip(named: "TitleList_mc", under: parent)
        let titleList = Self.clip(named: "List_mc", under: titleHolder)
        let objectiveList = Self.clip(named: "objectiveList", under: parent)
        for list in [titleList, objectiveList] {
            list.object.define(.integer(-1), for: QuestJournalMovieBridge.selectedIndexName)
        }
        return Harness(runtime: runtime, titleList: titleList)
    }

    private static func clip(
        named name: String,
        under parent: SWFDisplayObject
    ) -> SWFDisplayObject {
        let node = SWFDisplayObject(content: .clip(nil))
        node.name = name
        parent.addChild(node, atDepth: UInt16(parent.children.count + 1))
        return node
    }

    private func model() -> JournalMenuModel {
        JournalMenuModel(
            active: [
                Self.entry(
                    title: "Unbound",
                    kind: .mainQuest,
                    objectives: [
                        JournalObjectiveEntry(index: 10, text: "Escape Helgen", state: .displayed),
                        JournalObjectiveEntry(index: 20, text: "Follow Hadvar", state: .completed)
                    ],
                    logEntries: ["A dragon attacked."]
                ),
                Self.entry(title: "Supply and Demand", kind: .miscellaneous)
            ],
            completed: []
        )
    }

    private static func entry(
        title: String,
        kind: Quest.Kind,
        objectives: [JournalObjectiveEntry] = [],
        logEntries: [String] = []
    ) -> JournalQuestEntry {
        JournalQuestEntry(
            formID: FormID(0x0100),
            editorID: title,
            title: title,
            kind: kind,
            isCompleted: false,
            stage: 10,
            objectives: objectives,
            logEntries: logEntries
        )
    }

    // MARK: - Requests

    @Test @MainActor
    func theQuestsRequestFillsTheListTheMovieHandsOver() throws {
        let harness = try harness()
        QuestJournalMovieBridge.registerRequests(runtime: harness.runtime) { model() }
        harness.runtime.callHost(
            QuestJournalMovieBridge.questsDataCall, arguments: [.object(harness.titleList.object)]
        )

        #expect(
            QuestJournalMovieBridge.questLabels(runtime: harness.runtime)
                == ["Unbound", "Supply and Demand"]
        )
        let row = MenuMovieEntryList.row(at: 0, of: harness.titleList.object)
        #expect(row?.lookup("description")?.property.value == .string("A dragon attacked."))
    }

    /// The movie's highlighted quest becomes the model's selection; an unknown one is ignored.
    @Test func selectingAQuestByFormIDMovesTheSelection() {
        let quests = [0x100, 0x200].map { id in
            JournalQuestEntry(
                formID: FormID(UInt32(id)), editorID: "Q\(id)", title: "Q\(id)",
                kind: .sideQuests, isCompleted: false, stage: 10, objectives: [], logEntries: []
            )
        }
        var journal = JournalMenuModel(active: quests, completed: [])
        journal.select(quest: FormID(0x200))
        #expect(journal.selectedIndex == 1)
        journal.select(quest: FormID(0xDEAD_BEEF))
        #expect(journal.selectedIndex == 1)
    }

    /// `show` answers the next request with the new model and lets the page ask again.
    @Test @MainActor
    func showingAModelLetsThePageAskAgain() throws {
        let harness = try harness()
        let page = try #require(harness.runtime.node(
            atPath: QuestJournalMovieBridge.pagePath, from: harness.runtime.root
        ))
        page.object.assign(.boolean(true), for: "bUpdated")
        QuestJournalMovieBridge.show(model(), runtime: harness.runtime)
        #expect(page.object.lookup("bUpdated")?.property.value == .boolean(false))
        harness.runtime.callHost(
            QuestJournalMovieBridge.questsDataCall, arguments: [.object(harness.titleList.object)]
        )
        #expect(QuestJournalMovieBridge.questLabels(runtime: harness.runtime).count == 2)
    }

    /// The misc group is left to the movie, which adds its own row, and the
    /// finished quests follow the running ones with `completed` set.
    @Test
    func questRowsLeaveTheMiscGroupToTheMovie() {
        var misc = Self.entry(title: "Miscellaneous", kind: .miscellaneous)
        misc.miscQuests = [FormID(0x200)]
        misc.isTracked = true
        let finished = JournalQuestEntry(
            formID: FormID(0x300), editorID: "Done", title: "Done", kind: .sideQuests,
            isCompleted: true, stage: 200, objectives: [], logEntries: []
        )
        let built = JournalMenuModel(
            active: [Self.entry(title: "Unbound", kind: .mainQuest), misc], completed: [finished]
        )
        let rows = QuestJournalMovieBridge.questRows(built)

        #expect(rows.map { $0["text"] } == [.string("Unbound"), .string("Done")])
        #expect(rows.last?["completed"] == .boolean(true))
        let answer = QuestJournalMovieBridge.questsDataAnswer(built)
        #expect(answer == [
            .number(256),
            .number(256),
            .boolean(true),
            .boolean(true),
            .boolean(true)
        ])
    }

    @Test @MainActor
    func theObjectivesRequestFillsTheSelectedRow() throws {
        let harness = try harness()
        QuestJournalMovieBridge.registerRequests(runtime: harness.runtime) { model() }
        harness.runtime.callHost(
            QuestJournalMovieBridge.questsDataCall, arguments: [.object(harness.titleList.object)]
        )
        harness.titleList.object.assign(.integer(0), for: QuestJournalMovieBridge.selectedIndexName)
        harness.runtime.callHost(QuestJournalMovieBridge.objectivesDataCall, arguments: [])

        let row = MenuMovieEntryList.row(at: 0, of: harness.titleList.object)
        let objectives = row?.lookup("objectives")?.property.value.objectValue
        let first = objectives?.lookup("0")?.property.value.objectValue
        #expect(first?.lookup("text")?.property.value == .string("Escape Helgen"))
        #expect(QuestJournalMovieBridge.selectedQuest(runtime: harness.runtime) == FormID(0x100))
    }

    @Test @MainActor
    func anObjectivesRequestWithNothingSelectedIsTallied() throws {
        let harness = try harness()
        QuestJournalMovieBridge.registerRequests(runtime: harness.runtime) { .empty }
        harness.runtime.callHost(QuestJournalMovieBridge.objectivesDataCall, arguments: [])

        #expect(harness.runtime.tally.missingNames[QuestJournalMovieBridge.objectivesDataCall] == 1)
        #expect(QuestJournalMovieBridge.selectedQuest(runtime: harness.runtime) == nil)
    }

    // MARK: - Rows

    /// The row fields are the measured ones. `completed` and `failed` are what
    /// move an objective entry clip off its `Normal` frame — see
    /// `openskycli menu quest-journal --objective-state completed`.
    @Test
    func objectiveRowsCarryTheMeasuredStateFields() {
        let completed = QuestJournalMovieBridge.objectiveRow(
            JournalObjectiveEntry(index: 1, text: "done", state: .completed)
        )
        #expect(completed["completed"] == .boolean(true))
        #expect(completed["failed"] == .boolean(false))

        let failed = QuestJournalMovieBridge.objectiveRow(
            JournalObjectiveEntry(index: 2, text: "lost", state: .failed)
        )
        #expect(failed["completed"] == .boolean(false))
        #expect(failed["failed"] == .boolean(true))

        let plain = QuestJournalMovieBridge.objectiveRow(
            JournalObjectiveEntry(index: 3, text: "open", state: .displayed)
        )
        #expect(plain["completed"] == .boolean(false))
        #expect(plain["failed"] == .boolean(false))
        #expect(plain["text"] == .string("open"))
    }

    /// Every endpiece name is one of the clip's own measured frame labels, and
    /// a type the movie predates falls back to `Misc` rather than to nothing.
    @Test
    func everyQuestTypeMapsToAMeasuredEndpieceLabel() {
        let kinds: [Quest.Kind] = [
            .none, .mainQuest, .magesGuild, .thievesGuild, .darkBrotherhood,
            .companionQuests, .miscellaneous, .daedricQuests, .sideQuests, .civilWar,
            .vampire, .dragonborn, .unknown(99)
        ]
        for kind in kinds {
            let label = QuestJournalMovieBridge.endpieceFrame(for: kind)
            #expect(
                QuestJournalMovieBridge.endpieceFrames.contains(label),
                "\(kind.name) mapped to unmeasured label \(label)"
            )
            #expect(Quest.Kind(rawValue: kind.rawValue) == kind)
        }
        #expect(QuestJournalMovieBridge.endpieceFrame(for: .unknown(99)) == "Misc")
        #expect(QuestJournalMovieBridge.endpieceFrame(for: .mainQuest) == "Main")
        #expect(QuestJournalMovieBridge.endpieceFrame(for: .miscellaneous) == "Favor")
        #expect(QuestJournalMovieBridge.endpieceFrame(for: .sideQuests) == "Misc")
        let row = QuestJournalMovieBridge.titleRow(Self.entry(title: "Unbound", kind: .mainQuest))
        #expect(row["type"] == .integer(1), "the movie indexes its table with the DNAM type")
    }

    /// A movie whose shape moved must leave the readouts empty, never crash.
    @Test
    func aMissingPageDegradesToEmptyReadouts() throws {
        let runtime = try SWFRuntimeFixture.started(tags: [SWFDisplayFixture.showFrameTag])
        QuestJournalMovieBridge.startQuestsPage(runtime: runtime)

        #expect(QuestJournalMovieBridge.questLabels(runtime: runtime).isEmpty)
        #expect(QuestJournalMovieBridge.objectiveLabels(runtime: runtime).isEmpty)
        #expect(QuestJournalMovieBridge.titleText(runtime: runtime) == nil)
        #expect(QuestJournalMovieBridge.objectiveEntryFrames(runtime: runtime).isEmpty)
        #expect(!QuestJournalMovieBridge.isFrontmost(runtime: runtime))
    }
}
