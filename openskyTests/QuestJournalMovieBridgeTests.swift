// Quests-page bridge coverage over a synthetic runtime (issue #184). No game
// movie or extracted asset is used: the measured node names, list properties
// and list methods are installed in code, so the test asserts the *contract*
// the bridge was written against rather than re-measuring the install.
//
// The shape installed below is exactly what `openskycli swf action-run --movie
// quest_journal.swf --dump-proto` reported for the two lists: `EntriesA` holds
// the rows, `iSelectedIndex` holds the selection with -1 for none, and
// `InvalidateData()` and `ClearList()` are methods on the list.

import Foundation
@testable import opensky
import Testing

private final class JournalCallLog: @unchecked Sendable {
    private(set) var calls: [String] = []

    func append(_ name: String) {
        calls.append(name)
    }
}

@Suite("Quest journal movie bridge")
struct QuestJournalMovieBridgeTests {
    private struct Harness {
        let runtime: SWFMovieRuntime
        let titleList: SWFDisplayObject
        let objectiveList: SWFDisplayObject
        let log: JournalCallLog
    }

    /// Builds `/QuestJournalFader/Menu_mc/QuestsFader/Page_mc/...` down to the
    /// two lists, so the bridge's pinned paths are what is exercised.
    private func harness() throws -> Harness {
        let runtime = try SWFRuntimeFixture.started(tags: [SWFDisplayFixture.showFrameTag])
        let log = JournalCallLog()
        var parent = runtime.root
        for name in ["QuestJournalFader", "Menu_mc", "QuestsFader", "Page_mc"] {
            parent = Self.clip(named: name, under: parent)
        }
        let titleHolder = Self.clip(named: "TitleList_mc", under: parent)
        let titleList = Self.clip(named: "List_mc", under: titleHolder)
        let objectiveList = Self.clip(named: "objectiveList", under: parent)
        for list in [titleList, objectiveList] {
            list.object.define(.integer(-1), for: QuestJournalMovieBridge.selectedIndexName)
            for method in [
                QuestJournalMovieBridge.invalidateMethod, QuestJournalMovieBridge.clearMethod
            ] {
                AS2Natives.method(runtime.runtime, on: list.object, name: method) { _ in
                    log.append(method)
                    return .undefined
                }
            }
        }
        return Harness(
            runtime: runtime, titleList: titleList, objectiveList: objectiveList, log: log
        )
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

    // MARK: - Publishing

    @Test
    func publishesQuestRowsObjectiveRowsAndTheSelection() throws {
        let harness = try harness()
        QuestJournalMovieBridge.publish(model(), runtime: harness.runtime)

        #expect(
            QuestJournalMovieBridge.questLabels(runtime: harness.runtime)
                == ["Unbound", "Supply and Demand"]
        )
        #expect(
            QuestJournalMovieBridge.objectiveLabels(runtime: harness.runtime)
                == ["Escape Helgen", "Follow Hadvar"]
        )
        #expect(
            QuestJournalMovieBridge.selectedIndex(
                runtime: harness.runtime, atPath: QuestJournalMovieBridge.titleListPath
            ) == 0
        )
        // The objective list is a readout of the selected quest, not a second
        // cursor, so it is rebuilt with nothing selected.
        #expect(
            QuestJournalMovieBridge.selectedIndex(
                runtime: harness.runtime, atPath: QuestJournalMovieBridge.objectiveListPath
            ) == nil
        )
    }

    /// The selection is written *after* the rebuild, because `InvalidateData`
    /// resets it to -1 as it goes. The call order is the contract.
    @Test
    func rebuildsBeforeSelecting() throws {
        let harness = try harness()
        var built = model()
        built.select(1)
        QuestJournalMovieBridge.publish(built, runtime: harness.runtime)

        #expect(harness.log.calls.contains(QuestJournalMovieBridge.invalidateMethod))
        #expect(
            QuestJournalMovieBridge.selectedIndex(
                runtime: harness.runtime, atPath: QuestJournalMovieBridge.titleListPath
            ) == 1
        )
    }

    /// A list that ends up empty is cleared as well as invalidated: the
    /// rebuild only touches as many clips as there are rows, so the previous
    /// quest's first objective would otherwise stay on screen.
    @Test
    func anEmptyListIsClearedNotOnlyInvalidated() throws {
        let harness = try harness()
        var built = model()
        built.select(1)
        QuestJournalMovieBridge.publish(built, runtime: harness.runtime)

        #expect(QuestJournalMovieBridge.objectiveLabels(runtime: harness.runtime).isEmpty)
        #expect(harness.log.calls.contains(QuestJournalMovieBridge.clearMethod))
    }

    @Test
    func selectionOfAnEmptyPageIsTheMoviesOwnSentinel() throws {
        let harness = try harness()
        QuestJournalMovieBridge.publish(.empty, runtime: harness.runtime)

        #expect(QuestJournalMovieBridge.questLabels(runtime: harness.runtime).isEmpty)
        #expect(
            harness.titleList.object
                .lookup(QuestJournalMovieBridge.selectedIndexName)?.property.value
                == .number(-1)
        )
    }

    // MARK: - Rows

    /// The row fields are the measured ones. `completed` and `failed` are what
    /// move an objective entry clip off its `Normal` frame — see
    /// `openskycli swf quest-journal --objective-state completed`.
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
        }
        #expect(QuestJournalMovieBridge.endpieceFrame(for: .unknown(99)) == "Misc")
        #expect(QuestJournalMovieBridge.endpieceFrame(for: .mainQuest) == "Main")
    }

    /// A movie whose shape moved must leave the readouts empty, never crash.
    @Test
    func aMissingPageDegradesToEmptyReadouts() throws {
        let runtime = try SWFRuntimeFixture.started(tags: [SWFDisplayFixture.showFrameTag])
        QuestJournalMovieBridge.publish(model(), runtime: runtime)

        #expect(QuestJournalMovieBridge.questLabels(runtime: runtime).isEmpty)
        #expect(QuestJournalMovieBridge.objectiveLabels(runtime: runtime).isEmpty)
        #expect(QuestJournalMovieBridge.titleText(runtime: runtime) == nil)
        #expect(QuestJournalMovieBridge.objectiveEntryFrames(runtime: runtime).isEmpty)
        #expect(!QuestJournalMovieBridge.isFrontmost(runtime: runtime))
    }
}
