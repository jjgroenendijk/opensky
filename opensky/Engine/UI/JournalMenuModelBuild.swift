// Builds a `JournalMenuModel` out of live quest state (issue #184). Satellite
// of UI/JournalMenuModel.swift, which holds the value types.
//
// Two rules decide what a row says, and both are quest-record facts rather than
// journal conventions invented here:
//
// * A quest appears at all only when its `Kind` is not `.none`. Type 0 "keeps
//   the quest out of the journal entirely" (docs/formats/records.md, from the
//   DNAM type field), which is why `QuestStore.journalQuests()` already filters
//   it and why the row set is filtered the same way.
// * An objective appears only while its `isDisplayed` flag is set, the flag
//   `SetObjectiveDisplayed` exists to control
//   (<https://ck.uesp.net/wiki/SetObjectiveDisplayed_-_Quest>).
//
// Text resolution goes through `LocalizedStrings`, never through a table kind
// picked by feel. `openskycli swf quest-journal --text` resolves each field out
// of all three tables and prints what each answered, and on vanilla
// `Skyrim.esm` exactly one answers per field: the quest FULL and the objective
// NNAM come from `.strings`, and the stage CNAM journal paragraph — the one
// long-form field of the three — comes from `.dlstrings`. That split matches
// the general rule docs/formats/records.md already states for the tables
// (FULL -> `.strings`, long-form body text -> `.dlstrings`).

import Foundation

nonisolated extension JournalMenuModel {
    /// Resolves one lstring, with or without string tables.
    ///
    /// A plugin whose header does not say localized writes its text inline, and
    /// then there is no table to consult and none is needed. That is not only
    /// the synthetic-fixture case: an unlocalized mod plugin reaches the
    /// journal the same way.
    static func text(
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
    static func fallbackTitle(for quest: Quest) -> String {
        if let editorID = quest.editorID, !editorID.isEmpty {
            return editorID
        }
        return quest.formID.description
    }
}

extension JournalMenuModel {
    /// Everything the journal page shows, sampled from one quest runtime.
    ///
    /// - Parameters:
    ///   - runtime: the quest state layer; its store is the session's.
    ///   - strings: the plugin's string tables, or nil for a plugin that writes
    ///     its text inline rather than into tables.
    ///   - aliases: alias fills, used to substitute the alias tokens the
    ///     journal text carries (issue #183). `.empty` leaves tokens as
    ///     written, which is what a session with no fills would show anyway.
    ///   - showsCompleted: which of the two lists to select into.
    ///   - selectedIndex: the row to keep selected, clamped into the list.
    @MainActor
    static func build(
        runtime: QuestRuntime,
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
    static func makeEntry(
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

    /// The journal paragraphs of every reached stage, in stage order.
    ///
    /// A stage may carry several QSDT log entries and the vanilla journal picks
    /// between them by condition. Conditions are not evaluated here — the page
    /// has no condition context — so the file-order default
    /// `Quest.Stage.primaryLogEntry` is taken, and a stage index appearing more
    /// than once contributes each of its texts in file order.
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
