// Builds a `JournalMenuModel` from quest state. A quest is listed only when its
// `Kind` is not `.none` (docs/formats/quest-records.md); an objective only
// while `isDisplayed` is set. Text goes through `LocalizedStrings`: FULL and
// NNAM resolve from `.strings`, the CNAM paragraph from `.dlstrings`.

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
        for quest in runtime.quests.journalQuests() {
            guard let state = try? runtime.state(of: quest.formID) else { continue }
            guard state.isRunning || state.isCompleted else { continue }
            let entry = makeEntry(quest: quest, state: state, strings: strings, aliases: aliases)
            if state.isRunning {
                active.append(entry)
            }
            if state.isCompleted {
                completed.append(entry)
            }
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
        return JournalQuestEntry(
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
    }

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
                state: objectiveState(display)
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

    /// The journal paragraphs of every reached stage, in stage order. The page
    /// has no condition context, so it takes `Quest.Stage.primaryLogEntry`.
    private static func logEntries(
        of quest: Quest,
        state: QuestRuntimeState,
        strings: LocalizedStrings?,
        substitute: (String) -> String
    ) -> [String] {
        quest.stages
            .filter { state.isStageDone($0.index) }
            .sorted { $0.index < $1.index }
            .compactMap { stage in
                guard let entry = stage.primaryLogEntry else { return nil }
                guard
                    let text = JournalMenuModel
                        .text(entry.text, kind: .dlstrings, strings: strings),
                    !text.isEmpty
                else {
                    return nil
                }
                return substitute(text)
            }
    }
}
