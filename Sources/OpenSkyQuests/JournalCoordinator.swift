// The shell of the journal: the quest the panel names, the quest mutations its
// controls run, and the quest list its readouts show. The page model and the
// movie stay in the app, because they live in `OpenSkyMenus`.
// See docs/engine/coordinators.md and docs/engine/journal.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface

/// Reads and changes quest state for the journal through `JournalWorld`.
/// Without a quest runtime every control refuses with a stated reason.
@MainActor
public final class JournalCoordinator {
    /// As typed into the panel.
    public var editorID = ""
    /// Kept across readout refreshes, so the user sees what they just did.
    public var lastOutcome: String?
    private var cachedStrings: LocalizedStrings?
    private var stringsResolved = false

    weak var world: (any JournalWorld)?

    public init() {}

    public func attach(world: any JournalWorld) {
        self.world = world
    }

    public var runtime: QuestRuntime? {
        world?.questRuntime
    }

    /// Plugin string tables, loaded on first use.
    public var strings: LocalizedStrings? {
        if !stringsResolved {
            stringsResolved = true
            cachedStrings = world?.loadStrings()
        }
        return cachedStrings
    }

    public var selectedEditorID: String {
        editorID.trimmingCharacters(in: .whitespaces)
    }

    public var questEditorIDs: [String] {
        runtime?.quests.journalQuests().compactMap(\.editorID) ?? []
    }

    /// Every journal quest whose state reads.
    public func entries() -> [JournalQuestStatus] {
        guard let runtime else { return [] }
        return runtime.quests.journalQuests().compactMap { quest in
            (try? runtime.state(of: quest.formID)).map {
                JournalQuestStatus(quest: quest, state: $0)
            }
        }
    }

    public func selectedEntry() -> JournalQuestStatus? {
        let editorID = selectedEditorID
        guard
            !editorID.isEmpty,
            let runtime,
            let quest = runtime.quests.quest(editorID: editorID),
            let state = try? runtime.state(of: quest.formID)
        else {
            return nil
        }
        return JournalQuestStatus(quest: quest, state: state)
    }

    // MARK: - Mutations

    /// Each returns true when the change ran, refused or not, so the caller
    /// rebuilds the page.
    @discardableResult
    public func startSelectedQuest() -> Bool {
        applyChange("start") { runtime, formID in
            let state = try runtime.startQuest(formID)
            return "started, stage \(state.currentStage.map(String.init) ?? "none")"
        }
    }

    @discardableResult
    public func stopSelectedQuest() -> Bool {
        applyChange("stop") { runtime, formID in
            _ = try runtime.stopQuest(formID)
            return "stopped, aliases cleared"
        }
    }

    @discardableResult
    public func setSelectedQuestStage(_ index: Int) -> Bool {
        guard let stage = UInt16(exactly: index) else {
            lastOutcome = "stage \(index) is not a stage index"
            return false
        }
        return applyChange("set stage \(stage)") { runtime, formID in
            let state = try runtime.setStage(stage, on: formID)
            return "stage \(stage) reached, current \(state.stageValue)"
        }
    }

    @discardableResult
    public func setSelectedQuestObjective(_ index: Int, displayed: Bool) -> Bool {
        guard let objective = UInt16(exactly: index) else {
            lastOutcome = "objective \(index) is not an objective index"
            return false
        }
        return applyChange("objective \(objective)") { runtime, formID in
            _ = try runtime.setObjectiveDisplayed(objective, displayed, on: formID)
            return "objective \(objective) \(displayed ? "displayed" : "hidden")"
        }
    }

    /// A `QuestError` is a stated outcome, never a thrown error out of a
    /// control action.
    private func applyChange(
        _ label: String,
        _ change: (QuestRuntime, FormID) throws -> String
    ) -> Bool {
        guard let runtime else {
            lastOutcome = "\(label): no quest index loaded"
            return false
        }
        let editorID = selectedEditorID
        guard let quest = runtime.quests.quest(editorID: editorID) else {
            lastOutcome = editorID.isEmpty
                ? "\(label): no quest selected"
                : "\(label): no loaded plugin defines \(editorID)"
            return false
        }
        do {
            lastOutcome = try "\(quest.editorID ?? editorID): " + change(runtime, quest.formID)
        } catch {
            lastOutcome = "\(label) refused: \(String(describing: error))"
        }
        return true
    }
}
