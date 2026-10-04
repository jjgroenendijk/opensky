// The alias half of `QuestRuntime`: when a quest's alias table is filled,
// cleared, and read. `QuestAliasFiller` derives the table; nothing else writes a
// `QuestAliasState`. Aliases fill when the quest starts and clear when it stops
// (<https://ck.uesp.net/wiki/Alias>). See docs/engine/quest-state.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface
import OpenSkyWorldState

extension QuestRuntime {
    // MARK: - Reading

    /// Filled aliases of the quest `id` names. An untouched or stopped quest
    /// reads as the empty table rather than as nil, exactly as an untouched
    /// objective reads as all-false.
    ///
    /// - Throws: `QuestError.unknownQuest`, `QuestError.unresolvedQuestKey`.
    public func aliasState(of id: FormID) throws -> QuestAliasState {
        guard quests.quest(id) != nil else {
            throw QuestError.unknownQuest(id)
        }
        guard let key = quests.key(for: id) else {
            throw QuestError.unresolvedQuestKey(id)
        }
        return store.component(QuestAliasState.self, for: key) ?? .empty
    }

    /// Reference currently filling one alias, or nil when the alias is empty,
    /// the quest defines no such alias, or no quest is named.
    ///
    /// The lookup shape the Papyrus binding seam and the condition evaluator
    /// both need: a VMAD alias property and a `questAlias` run-on each arrive
    /// holding a quest plus an alias number and nothing else.
    public func aliasReference(alias aliasID: UInt32, in id: FormID) -> ReferenceKey? {
        guard let key = quests.key(for: id) else { return nil }
        return store.component(QuestAliasState.self, for: key)?.reference(forAlias: aliasID)
    }

    /// Location currently filling one ALLS alias.
    public func aliasLocation(alias aliasID: UInt32, in id: FormID) -> ResolvedFormID? {
        guard let key = quests.key(for: id) else { return nil }
        return store.component(QuestAliasState.self, for: key)?.location(forAlias: aliasID)
    }

    /// The seam conditions read alias fills through, built the same way
    /// `resolution()` builds the quest-state seam.
    public func aliasResolution() -> QuestAliasResolution {
        var tables: [ReferenceKey: QuestAliasState] = [:]
        for quest in quests.sortedQuests() {
            guard
                let key = quests.key(for: quest.formID),
                let state = store.component(QuestAliasState.self, for: key)
            else {
                continue
            }
            tables[key] = state
        }
        return QuestAliasResolution(defaults: quests, tables: tables)
    }

    // MARK: - Filling

    /// Fills `quest`'s aliases and stores the table, unless a non-optional alias
    /// could not be filled. A second start on a running quest does not refill.
    /// - Throws: `QuestError.aliasFillFailed`; nothing is written then.
    /// - Returns: the table as stored, and why any alias stayed empty.
    @discardableResult
    public func fillAliases(of quest: Quest, key: ReferenceKey) throws -> QuestAliasFillResult {
        try fillAliases(of: quest, key: key, event: nil)
    }

    @discardableResult
    public func fillAliases(
        of quest: Quest,
        key: ReferenceKey,
        event: StoryEventData?
    ) throws -> QuestAliasFillResult {
        if let existing = store.component(QuestAliasState.self, for: key), !existing.isEmpty {
            return QuestAliasFillResult(
                state: existing, skipped: QuestAliasTally(), unfilledRequired: []
            )
        }
        let result = QuestAliasFiller.fill(
            quest,
            resolver: quests.sourceResolver(of: quest.formID),
            locations: locations,
            event: event
        )
        guard result.canStartQuest else {
            throw QuestError.aliasFillFailed(
                quest: quest.formID, aliases: result.unfilledRequired
            )
        }
        if !result.state.isEmpty {
            store.set(result.state, for: key)
        }
        return result
    }

    /// Drops the quest's alias table. Called by `stopQuest`, and by nothing
    /// else: a quest that is merely not running any more still owns its
    /// stages, but an alias is a live pointer into the world and holding one
    /// past the stop would keep a reference reserved forever.
    ///
    /// - Returns: true when a table was actually removed.
    @discardableResult
    public func clearAliases(key: ReferenceKey) -> Bool {
        store.reset(.questAliases, for: key)
    }
}
