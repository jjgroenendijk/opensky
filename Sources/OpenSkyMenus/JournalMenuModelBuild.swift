// Builds a `JournalMenuModel` from quest state. A quest is listed only when its
// `Kind` is not `.none` (docs/formats/quest-records.md) and it has an objective
// or a log entry to show; an objective only while `isDisplayed` is set. Running
// misc quests share one row. FULL and NNAM resolve from `.strings`, the CNAM
// paragraph from `.dlstrings`.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface

nonisolated extension JournalMenuModel {
    /// Resolves one lstring, with or without string tables.
    ///
    /// A plugin whose header does not say localized writes its text inline, and
    /// then there is no table to consult and none is needed. That is not only
    /// the synthetic-fixture case: an unlocalized mod plugin reaches the
    /// journal the same way.
    public static func text(
        _ value: LString?,
        kind: StringTable.Kind,
        strings: LocalizedStrings?
    ) -> String? {
        if let strings {
            return strings.resolve(value, kind: kind)
        }
        guard case let .inline(inline) = value else { return nil }
        return inline
    }

    /// Fallback text a row shows when the plugin's string tables answer
    /// nothing, so a missing table degrades into a labelled row rather than
    /// into a blank list.
    public static func fallbackTitle(for quest: Quest) -> String {
        if let editorID = quest.editorID, !editorID.isEmpty {
            return editorID
        }
        return quest.formID.description
    }
}

extension JournalMenuModel {
    /// Everything the journal page shows, sampled from one quest runtime.
    /// `strings` is nil for a plugin with inline text. `.empty` aliases leave
    /// tokens as written. `selectedIndex` is clamped into the list.
    @MainActor
    public static func build(
        runtime: any QuestAccess,
        strings: LocalizedStrings?,
        aliases: QuestAliasNaming = .none,
        showsCompleted: Bool = false,
        selectedIndex: Int = 0
    ) -> JournalMenuModel {
        var active: [JournalQuestEntry] = []
        var completed: [JournalQuestEntry] = []
        var misc: [JournalQuestEntry] = []
        for quest in runtime.quests.journalQuests() {
            guard let state = try? runtime.state(of: quest.formID) else { continue }
            guard state.isRunning || state.isCompleted || state.isFailed else { continue }
            // A DLC quest's text IDs point into its own plugin's tables.
            var entry = makeEntry(
                quest: quest,
                state: state,
                strings: strings?.scoped(to: runtime.quests.sourcePlugin(of: quest.formID)),
                aliases: aliases
            )
            entry.track(state.isRunning && runtime.isTracked(quest.formID))
            // A background quest, such as one that tracks an achievement, has
            // nothing to show, so the game never lists it.
            guard !entry.objectives.isEmpty || !entry.logEntries.isEmpty else { continue }
            if state.isRunning, quest.kind == .miscellaneous {
                misc.append(entry)
            } else if state.isRunning, !state.isFailed {
                active.append(entry)
            }
            if state.isCompleted || state.isFailed {
                completed.append(entry)
            }
        }
        if let group = miscGroup(misc) {
            active.append(group)
        }
        return JournalMenuModel(
            active: active,
            completed: completed,
            showsCompleted: showsCompleted,
            selectedIndex: selectedIndex
        )
    }

    /// One row, with its objectives and its reached-stage log entries.
    public static func makeEntry(
        quest: Quest,
        state: QuestRuntimeState,
        strings: LocalizedStrings?,
        aliases: QuestAliasNaming = .none
    ) -> JournalQuestEntry {
        let substitute = { (text: String) -> String in
            aliases.substituting(text, in: quest)
        }
        let title = JournalMenuModel.text(quest.name, kind: .strings, strings: strings)
            .flatMap { $0.isEmpty ? nil : substitute($0) }
        var entry = JournalQuestEntry(
            formID: quest.formID,
            editorID: JournalMenuModel.fallbackTitle(for: quest),
            title: title ?? JournalMenuModel.fallbackTitle(for: quest),
            kind: quest.kind,
            isCompleted: state.isCompleted,
            stage: state.currentStage,
            objectives: objectives(
                of: quest, state: state, strings: strings, substitute: substitute
            ),
            logEntries: logEntries(
                of: quest, state: state, strings: strings, substitute: substitute
            )
        )
        entry.isFailed = state.isFailed
        return entry
    }

    /// The game lists running misc quests as one last row, whose objectives are
    /// the open objectives of them all. The movie's own row has the same shape.
    public static func miscGroup(_ misc: [JournalQuestEntry]) -> JournalQuestEntry? {
        let objectives = misc.flatMap { $0.objectives.filter { $0.state == .displayed } }
        guard !objectives.isEmpty else { return nil }
        return JournalQuestEntry(
            formID: FormID(0),
            editorID: miscGroupEditorID,
            title: miscGroupTitle,
            kind: .miscellaneous,
            isCompleted: false,
            stage: nil,
            objectives: objectives,
            logEntries: [],
            isTracked: misc.contains(where: \.isTracked),
            miscQuests: misc.map(\.formID)
        )
    }

    public static let miscGroupEditorID = "Miscellaneous"
    /// The movie's own label for the row, a translation key.
    public static let miscGroupTitle = "$MISCELLANEOUS"

    // MARK: - Private

    private static func objectives(
        of quest: Quest,
        state: QuestRuntimeState,
        strings: LocalizedStrings?,
        substitute: (String) -> String
    ) -> [JournalObjectiveEntry] {
        // An objective index may legally appear more than once in a QUST, so
        // the first record carrying display text wins rather than the last,
        // and each index contributes at most one row.
        var seen: Set<UInt16> = []
        return quest.objectives.compactMap { objective in
            let display = state.objective(objective.index)
            guard display.isDisplayed || display.isCompleted || display.isFailed else {
                return nil
            }
            guard seen.insert(objective.index).inserted else { return nil }
            let text = JournalMenuModel
                .text(objective.displayText, kind: .strings, strings: strings)
                .flatMap { $0.isEmpty ? nil : substitute($0) }
            return JournalObjectiveEntry(
                index: objective.index,
                text: text ?? "objective \(objective.index)",
                state: objectiveState(display),
                quest: quest.formID,
                hasTargets: !objective.targets.isEmpty
            )
        }
    }

    private static func objectiveState(
        _ display: QuestObjectiveState
    ) -> JournalObjectiveEntry.State {
        if display.isFailed {
            return .failed
        }
        return display.isCompleted ? .completed : .displayed
    }

    /// The newest log entry: the items its stage wrote when set. A state with no record
    /// of one, such as an imported save, shows the highest reached stage with text.
    private static func logEntries(
        of quest: Quest,
        state: QuestRuntimeState,
        strings: LocalizedStrings?,
        substitute: (String) -> String
    ) -> [String] {
        let entries: [Quest.LogEntry] = if
            let log = state.journalLog,
            let stage = quest.stages.first(where: { $0.index == log.stage })
        {
            log.items.compactMap { item in
                stage.logEntries.indices.contains(Int(item)) ? stage.logEntries[Int(item)] : nil
            }
        } else {
            quest.stages
                .filter { state.isStageDone($0.index) && $0.primaryLogEntry?.text != nil }
                .max { $0.index < $1.index }?.primaryLogEntry.map { [$0] } ?? []
        }
        return entries.compactMap { entry in
            JournalMenuModel.text(entry.text, kind: .dlstrings, strings: strings)
                .flatMap { $0.isEmpty ? nil : substitute($0) }
        }
    }
}

nonisolated extension JournalQuestEntry {
    /// Marks the quest and its open objectives tracked.
    mutating func track(_ isTracked: Bool) {
        self.isTracked = isTracked
        objectives = objectives.map { objective in
            var objective = objective
            objective.isActive = isTracked && objective.state == .displayed
            return objective
        }
    }
}
