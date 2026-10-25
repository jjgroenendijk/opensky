// Journal snapshot (docs/engine/journal.md). The
// readout reads one snapshot and calls one mutation per action, like
// `ScriptControlProviding`. Alias text reuses `ScriptsReadout.questAliasText`
// so the two readouts cannot disagree.

import Foundation

/// One quest as the readout lists it — running state, current stage, and the
/// display state of each objective the record declares.
nonisolated public struct JournalQuestRow: Equatable, Sendable {
    /// FULL, resolved, or the editor ID when the plugin's tables answer nothing.
    public let title: String

    public init(
        title: String
    ) {
        self.title = title
    }
}

/// Everything the journal readouts show, captured in one value.
nonisolated public struct JournalControlSnapshot: Equatable, Sendable {
    /// Rows a snapshot carries. A real install runs a hundred-odd quests at
    /// once, and the readout shows the ones the user asked about plus the running
    /// set, not the whole index.
    public static let rowLimit = 12

    public static let empty = JournalControlSnapshot(
        rows: [],
        selectedIndex: -1
    )

    // MARK: Quest state

    /// The rows the readout shows, at most `rowLimit` of them.
    public let rows: [JournalQuestRow]

    // MARK: Journal presentation

    /// Row the page has selected, or -1 for none.
    public let selectedIndex: Int

    public init(
        rows: [JournalQuestRow],
        selectedIndex: Int
    ) {
        self.rows = rows
        self.selectedIndex = selectedIndex
    }
}
