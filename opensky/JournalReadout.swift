// World > Quests & Journal readout text (issue #184): the device-free half of
// the journal verification surface.
//
// Every line the panel shows is a pure function of one
// `JournalControlSnapshot`, exactly as `ScriptsReadout` is of one
// `ScriptsSnapshot`. Keeping the wording here rather than inside the section
// view controllers is what lets the text be asserted without AppKit, without a
// Metal device, and without a game install.
//
// No AppKit import on purpose: the file compiles into both the app and the CLI
// target, so it needs no project-membership exception.

nonisolated enum JournalReadout {
    /// What the session's quests are doing, plus the rows the panel lists.
    static func questsText(for snapshot: JournalControlSnapshot) -> String {
        guard snapshot.hasQuestIndex else {
            return "Quests: unavailable (no plugin loaded)"
        }
        let header = "Journal quests: \(snapshot.questCount)"
            + "  Running: \(snapshot.runningCount)"
            + "  Completed: \(snapshot.completedCount)"
        guard !snapshot.rows.isEmpty else {
            return "\(header)\nNo quest is running."
        }
        let dropped = snapshot.droppedRowCount > 0
            ? ["  ... and \(snapshot.droppedRowCount) more"]
            : []
        return ([header] + snapshot.rows.map(line) + dropped).joined(separator: "\n")
    }

    private static func line(_ row: JournalQuestRow) -> String {
        let state = [
            row.isRunning ? "running" : "stopped",
            row.isCompleted ? "completed" : nil
        ].compactMap(\.self).joined(separator: ", ")
        let stage = row.stage.map(String.init) ?? "-"
        return "  \(row.editorID) \"\(row.title)\" (\(row.kind))"
            + "  \(state)  stage \(stage)"
    }

    /// The selected quest as the page would show it: its objectives and the
    /// journal paragraphs of every stage it has reached.
    static func selectionText(for snapshot: JournalControlSnapshot) -> String {
        guard !snapshot.selectedEditorID.isEmpty else {
            return "No quest selected."
        }
        guard let row = snapshot.selectedRow else {
            return "No loaded plugin defines \(snapshot.selectedEditorID)."
        }
        let stages = row.declaredStages.isEmpty
            ? "none"
            : row.declaredStages.map(String.init).joined(separator: ", ")
        let header = [
            "\(row.editorID) \"\(row.title)\"  stage \(row.stage.map(String.init) ?? "-")",
            "Declared stages: \(stages)",
            "Objectives: " + (row.objectives.isEmpty
                ? "none declared"
                : row.objectives.joined(separator: ", "))
        ]
        let shown = snapshot.selectedObjectives.isEmpty
            ? ["Shown on the page: none"]
            : ["Shown on the page:"] + snapshot.selectedObjectives.map { "  \($0)" }
        let log = snapshot.selectedLogEntries.isEmpty
            ? ["Journal entries: none"]
            : ["Journal entries:"] + snapshot.selectedLogEntries.map { "  \($0)" }
        let outcome = snapshot.lastOutcome.map { ["Last action: \($0)"] } ?? []
        return (header + shown + log + outcome).joined(separator: "\n")
    }

    /// Whether the journal is up, what the movie built, and the bring-up
    /// tallies the acceptance gate reads.
    ///
    /// The three tallies are stated even when they are zero: "0 faults" is the
    /// gate passing, and hiding a zero would make a passing gate look like a
    /// missing readout.
    static func movieText(for snapshot: JournalControlSnapshot) -> String {
        let stack = snapshot.openMenus.isEmpty
            ? "none"
            : snapshot.openMenus.joined(separator: " > ")
        let header = [
            "Journal: \(snapshot.isOpen ? "open" : "closed")  Menu stack: \(stack)",
            "Listing: \(snapshot.showsCompleted ? "completed" : "active") quests"
                + "  \(snapshot.listedQuestCount) rows"
                + "  selection \(snapshot.selectedIndex)"
        ]
        guard snapshot.movieLoaded else {
            return (header + ["Movie: \(snapshot.movieError ?? "not loaded")"])
                .joined(separator: "\n")
        }
        let frames = snapshot.movieObjectiveFrames.isEmpty
            ? "none"
            : snapshot.movieObjectiveFrames.joined(separator: ", ")
        return (header + [
            "Movie rows: \(snapshot.movieQuestRows) quests"
                + ", \(snapshot.movieObjectiveRows) objectives",
            "Movie title: \(snapshot.movieTitleText ?? "-")",
            "Objective frames: \(frames)",
            "Faults: \(snapshot.movieFaults)"
                + "  Unhandled invokes: \(snapshot.movieUnhandledInvokes)"
                + "  Missing names: \(snapshot.movieMissingNames)",
            "Draws: \(snapshot.movieDrawStats.drawCalls)"
                + "  Glyphs: \(snapshot.movieDrawStats.glyphs)"
                + "  Skipped: \(snapshot.movieDrawStats.skippedItems)"
        ]).joined(separator: "\n")
    }
}
