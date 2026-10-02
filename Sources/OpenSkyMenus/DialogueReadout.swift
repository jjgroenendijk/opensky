// Dialogue readout text. Each line is a pure function of one
// `DialogueControlSnapshot`, so the wording is testable without AppKit, a
// Metal device, or an install. No AppKit import: the CLI builds it too.

import OpenSkyDialogueInterface

nonisolated public enum DialogueReadout: Sendable {
    /// The Talk target, the conversation, and the topics on offer — the three
    /// things the acceptance question "did F on a voiced NPC open a
    /// condition-filtered list" is answered from.
    public static func topicsText(for snapshot: DialogueControlSnapshot) -> String {
        guard snapshot.hasDialogueIndex else {
            return "Dialogue: no game loaded"
        }
        let header = "Dialogue index: \(snapshot.topicCount) topics, "
            + "\(snapshot.infoCount) responses"
        let target = "Talk target: " + (snapshot.targetName.map {
            "\($0)" + (snapshot.targetKey.map { key in " (\(key))" } ?? "")
        } ?? "none")
        return ([header, target] + conversationLines(snapshot)).joined(separator: "\n")
    }

    /// The open conversation's own lines, or the one line that says there is
    /// none.
    private static func conversationLines(_ snapshot: DialogueControlSnapshot) -> [String] {
        guard snapshot.isOpen else {
            return ["Conversation: closed"]
        }
        let menus = snapshot.openMenus.isEmpty
            ? "none"
            : snapshot.openMenus.joined(separator: " > ")
        let header = "Conversation: \(snapshot.speaker) · \(snapshot.state)"
        let stack = "Menu stack: \(menus) · world "
            + (snapshot.worldSimPaused ? "paused" : "running")
        let subtitle = "Subtitle: " + (snapshot.subtitle.map { "\"\($0)\"" } ?? "none")
        let rows = snapshot.rows.isEmpty
            ? ["Topics: none on offer"]
            : ["Topics: \(snapshot.rows.count)"] + snapshot.rows.enumerated().map { index, row in
                let marker = index == snapshot.selectedIndex ? ">" : " "
                let goodbye = row.endsConversation ? " (goodbye)" : ""
                return "\(marker) \(index): \"\(row.text)\" info \(row.info)\(goodbye)"
            }
        let dropped = snapshot.droppedRowCount > 0
            ? ["  ... and \(snapshot.droppedRowCount) more"]
            : []
        return [header, stack, subtitle] + rows + dropped
    }

    /// Why the topics that are not listed are not listed, plus what the
    /// evaluator could not answer while deciding.
    ///
    /// "The line I expected is missing" is only debuggable if the engine says
    /// which check rejected it.
    public static func conditionsText(for snapshot: DialogueControlSnapshot) -> String {
        guard snapshot.hasDialogueIndex else {
            return "Condition trace: no game loaded"
        }
        guard snapshot.isOpen else {
            return "Condition trace: no conversation open"
        }
        let unresolved = "Unresolved condition calls: \(snapshot.unresolvedConditionCount)"
        guard !snapshot.rejections.isEmpty else {
            return "\(unresolved)\nRejected topics: 0"
        }
        let lines = snapshot.rejections.map { row in
            "  \(row.topic): " + (row.reasons.isEmpty
                ? "no responses declared"
                : row.reasons.joined(separator: ", "))
        }
        return (["\(unresolved)", "Rejected topics: \(snapshot.rejections.count)"]
            + lines).joined(separator: "\n")
    }

    /// What the vanilla movie built, beside what the engine published, plus the
    /// three bring-up tallies.
    public static func movieText(for snapshot: DialogueControlSnapshot) -> String {
        if let error = snapshot.movieError {
            return "Movie: failed — \(error)"
        }
        guard snapshot.movieLoaded else {
            return "Movie: not loaded"
        }
        let diagnostics = snapshot.movieDiagnostics
        let selection = snapshot.movieSelectedIndex.map(String.init) ?? "none"
        let state = snapshot.movieMenuState.map(String.init) ?? "absent"
        return """
        Movie: dialoguemenu.swf loaded
        Rows: movie \(snapshot.movieTopicRows) · engine \(snapshot.rows.count)
        Selection: movie \(selection) · engine \(snapshot.selectedIndex)
        Subtitle: movie \"\(snapshot.movieSubtitle ?? "")\" · eMenuState \(state)
        Faults: \(diagnostics.faults) · missing names: \(diagnostics.missingNames) \
        · unhandled invokes: \(diagnostics.unhandledInvokes)
        """
    }

    /// Result of the last control, if any.
    public static func outcomeText(for snapshot: DialogueControlSnapshot) -> String {
        snapshot.lastOutcome ?? "Last action: none"
    }

    /// One rejection reason worded for a readout.
    public static func reason(_ rejection: DialogueRejection) -> String {
        switch rejection {
        case let .questNotRunning(quest): "quest \(quest) not running"
        case .alreadySaid: "already said"
        case .conditionsFailed: "conditions failed"
        case .notReached: "not reached"
        }
    }
}
