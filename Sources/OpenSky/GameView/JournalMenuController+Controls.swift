// The journal's controls: the snapshot the sections read, and the
// quest commands they send. `GameViewController` gets them through
// `JournalMenuHosting`, so it holds no journal logic.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyQuests

extension JournalMenuController {
    /// One sample per refresh, so two sections never show a half-updated session.
    var snapshot: JournalControlSnapshot {
        guard journal.runtime != nil else { return .empty }
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
    private static func row(_ entry: JournalQuestStatus) -> JournalQuestRow {
        JournalQuestRow(
            title: JournalMenuModel.fallbackTitle(for: entry.quest)
        )
    }
}
