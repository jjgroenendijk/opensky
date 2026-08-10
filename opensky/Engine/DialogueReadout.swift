// Dialogue readout text (issue #205): the device-free half of the dialogue
// verification surface.
//
// Every line the panel shows is a pure function of one
// `DialogueControlSnapshot`, exactly as `JournalReadout` is of one
// `JournalControlSnapshot`. Keeping the wording here rather than inside the
// section view controller is what lets the text be asserted without AppKit,
// without a Metal device, and without a game install.
//
// No AppKit import on purpose: the file compiles into both the app and the CLI
// target, so it needs no project-membership exception.

nonisolated enum DialogueReadout {
    /// The Talk target, the conversation, and the topics on offer — the three
    /// things the acceptance question "did F on a voiced NPC open a
    /// condition-filtered list" is answered from.
    static func topicsText(for snapshot: DialogueControlSnapshot) -> String {
        guard snapshot.hasDialogueIndex else {
            return "Dialogue: unavailable (no plugin loaded)"
        }
        let header = "Dialogue index: \(snapshot.topicCount) topics, "
            + "\(snapshot.infoCount) responses"
        let target = "Talk target: " + (snapshot.targetName.map {
            "\($0)" + (snapshot.targetKey.map { key in " (\(key))" } ?? "")
        } ?? "none under the crosshair")
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
    /// This is the readout item 17.8 needs: "the line I expected is missing" is
    /// only debuggable if the engine says which check rejected it.
    static func conditionsText(for snapshot: DialogueControlSnapshot) -> String {
        guard snapshot.hasDialogueIndex else {
            return "Condition trace: unavailable (no plugin loaded)"
        }
        guard snapshot.isOpen else {
            return "Condition trace: no conversation open"
        }
        let unresolved = "Unresolved condition calls: \(snapshot.unresolvedConditionCount)"
        guard !snapshot.rejections.isEmpty else {
            return "\(unresolved)\nEvery considered topic was offered."
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
    static func movieText(for snapshot: DialogueControlSnapshot) -> String {
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

    /// Result of the last panel control, or the standing instruction when none
    /// has run.
    static func outcomeText(for snapshot: DialogueControlSnapshot) -> String {
        snapshot.lastOutcome ?? "Point the crosshair at an actor and press F, or Open."
    }

    /// One rejection reason worded for a readout.
    static func reason(_ rejection: DialogueRejection) -> String {
        switch rejection {
        case let .questNotRunning(quest): "quest \(quest) not running"
        case .alreadySaid: "already said"
        case .conditionsFailed: "conditions failed"
        case .notReached: "not reached"
        }
    }
}
