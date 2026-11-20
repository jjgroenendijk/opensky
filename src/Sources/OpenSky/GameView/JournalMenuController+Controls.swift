// The journal's controls: the snapshot the sections read, and the
// quest commands they send. `GameViewController` gets them through
// `JournalMenuHosting`, so it holds no journal logic.

import OpenSkyFormatsESM
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyQuests
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkySessionInterface

extension JournalMenuController {
    /// One sample per refresh, so two sections never show a half-updated session.
    var snapshot: JournalControlSnapshot {
        guard journal.runtime != nil else { return .empty }
        if let runtime = movie.loadedRenderer?.swfRuntime {
            return movieSnapshot(runtime)
        }
        let entries = journal.entries()
        let listed = JournalCore.listed(entries)
        let rows = listed.prefix(JournalControlSnapshot.rowLimit).map(Self.row)
        return JournalControlSnapshot(
            rows: Array(rows),
            selectedIndex: model.selectedIndex
        )
    }
}

extension JournalMenuController {
    /// The rows as the movie shows them, so the readout matches the page.
    private func movieSnapshot(_ runtime: SWFMovieRuntime) -> JournalControlSnapshot {
        let labels = QuestJournalMovieBridge.questLabels(runtime: runtime)
        let selected = QuestJournalMovieBridge.selectedIndex(
            runtime: runtime, atPath: QuestJournalMovieBridge.titleListPath
        )
        return JournalControlSnapshot(
            rows: labels.prefix(JournalControlSnapshot.rowLimit).map(JournalQuestRow.init(title:)),
            selectedIndex: selected ?? -1
        )
    }

    private static func row(_ entry: JournalQuestStatus) -> JournalQuestRow {
        JournalQuestRow(
            title: JournalMenuModel.fallbackTitle(for: entry.quest)
        )
    }
}
