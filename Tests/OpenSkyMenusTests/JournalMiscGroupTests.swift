// The journal's misc row, tracked rows, the "Show on map" target ID, and the
// Stats page rows, as the movie reads them.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsSWF
@testable import OpenSkyMenus
@testable import OpenSkyQuestsInterface
import Testing

@MainActor
struct JournalMiscGroupTests {
    private func entry(
        _ formID: UInt32, kind: Quest.Kind, objectives: [JournalObjectiveEntry]
    ) -> JournalQuestEntry {
        JournalQuestEntry(
            formID: FormID(formID), editorID: "Quest\(formID)", title: "Quest \(formID)",
            kind: kind, isCompleted: false, stage: 10, objectives: objectives, logEntries: []
        )
    }

    private func objective(_ index: UInt16, _ state: JournalObjectiveEntry.State, quest: UInt32)
        -> JournalObjectiveEntry
    {
        JournalObjectiveEntry(index: index, text: "Do \(index)", state: state, quest: FormID(quest))
    }

    /// Only open objectives join the misc row, and each keeps its quest.
    @Test func runningMiscQuestsShareOneRow() throws {
        var tracked = entry(0x10, kind: .miscellaneous, objectives: [
            objective(10, .displayed, quest: 0x10), objective(20, .completed, quest: 0x10)
        ])
        tracked.track(true)
        let other = entry(
            0x11, kind: .miscellaneous, objectives: [objective(5, .displayed, quest: 0x11)]
        )
        let group = try #require(JournalMenuModel.miscGroup([tracked, other]))
        #expect(group.objectives.map(\.index) == [10, 5])
        #expect(group.objectives.map(\.isActive) == [true, false])
        #expect(group.isTracked)
        #expect(group.miscQuests == [FormID(0x10), FormID(0x11)])
        let row = QuestJournalMovieBridge.titleRow(group)
        #expect(row["text"] == .string("$MISCELLANEOUS"))
        #expect(row["formID"] == .number(0))
        #expect(row["type"] == .integer(0))
        let empty = entry(0x12, kind: .miscellaneous, objectives: [])
        #expect(JournalMenuModel.miscGroup([empty]) == nil)
    }

    @Test func aTrackedObjectiveRowCarriesItsTargetID() throws {
        var open = objective(20, .displayed, quest: 0x0001_2345)
        open.hasTargets = true
        open.isActive = true
        let row = QuestJournalMovieBridge.objectiveRow(open)
        #expect(row["active"] == .boolean(true))
        let target = try #require(
            QuestJournalMovieBridge.objectiveTarget(fromID: row["questTargetID"])
        )
        #expect(target.quest == FormID(0x0001_2345))
        #expect(target.objective == 20)
        let done = QuestJournalMovieBridge.objectiveRow(objective(30, .completed, quest: 1))
        #expect(done["questTargetID"] == nil, "a closed objective offers no map button")
        #expect(QuestJournalMovieBridge.objectiveTarget(fromID: .number(-1)) == nil)
        #expect(QuestJournalMovieBridge.objectiveTarget(fromID: .number(1.5)) == nil)
    }

    @Test func statRowsListTheCatalogInCategoryOrder() {
        var stats = MiscStatsState()
        stats.increment("Bribes", by: 3)
        let rows = JournalStatRow.rows(stats)
        #expect(rows.first?.name == "Locations Discovered")
        #expect(rows.first { $0.name == "Bribes" }?.value == 3)
        #expect(!rows.contains { $0.name.hasPrefix("Favorite") || $0.name == "Whiterun Bounty" })
        #expect(rows.map(\.category.rawValue) == rows.map(\.category.rawValue).sorted())
        #expect(rows.last?.category == .crime)
    }
}
