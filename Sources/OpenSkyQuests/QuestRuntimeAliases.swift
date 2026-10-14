// The alias half of `QuestRuntime`: when a quest's alias table is filled,
// cleared, and read. `QuestAliasFiller` derives the table at a start, and
// `ForceRefTo` and `Clear` change one alias. Aliases fill when the quest starts and
// clear when it stops (<https://ck.uesp.net/wiki/Alias>). See docs/engine/quest-state.md.

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
        store.derived(QuestAliasResolution.self, from: quests) {
            QuestAliasResolution(defaults: quests, tables: aliasTables())
        }
    }

    func aliasTables() -> [ReferenceKey: QuestAliasState] {
        var tables: [ReferenceKey: QuestAliasState] = [:]
        for key in quests.sortedKeys {
            if let state = store.component(QuestAliasState.self, for: key) {
                tables[key] = state
            }
        }
        return tables
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
        let scope = referenceSearch?().map { search in
            QuestAliasSearchScope(
                search: search, questKey: key, quests: quests, otherTables: aliasTables(),
                translation: quests.translation(of: quest.formID)
            )
        }
        let result = QuestAliasFiller.fill(
            quest,
            resolver: quests.sourceResolver(of: quest.formID),
            locations: locations,
            event: event,
            scope: scope,
            translation: quests.translation(of: quest.formID)
        )
        guard result.canStartQuest else {
            throw QuestError.aliasFillFailed(
                quest: quest.formID, aliases: result.unfilledRequired
            )
        }
        let filled = creating(result)
        if !filled.state.isEmpty {
            store.set(filled.state, for: key)
        }
        return filled
    }

    /// Makes each requested reference only once the quest may start, so a refused
    /// start leaves nothing behind in the world.
    private func creating(_ result: QuestAliasFillResult) -> QuestAliasFillResult {
        guard let referenceCreator, !result.creations.isEmpty else { return result }
        var state = result.state
        for creation in result.creations {
            if let created = referenceCreator(creation.base, creation.anchor) {
                state = state.filling(creation.aliasID, with: created)
            }
        }
        return QuestAliasFillResult(
            state: state, skipped: result.skipped, unfilledRequired: result.unfilledRequired,
            creations: result.creations
        )
    }

    // MARK: - Forcing

    @discardableResult
    public func forceAlias(
        _ aliasID: UInt32, to reference: ReferenceKey?, on id: FormID
    ) throws -> QuestAliasState {
        try changeAlias(aliasID, on: id) { state in
            reference.map { state.filling(aliasID, with: $0) } ?? state.clearing(aliasID)
        }
    }

    @discardableResult
    public func forceLocationAlias(
        _ aliasID: UInt32, to location: ResolvedFormID?, on id: FormID
    ) throws -> QuestAliasState {
        try changeAlias(aliasID, on: id) { state in
            location.map { state.fillingLocation(aliasID, with: $0) } ?? state.clearing(aliasID)
        }
    }

    /// An empty table is stored as no component, like a stopped quest's.
    private func changeAlias(
        _ aliasID: UInt32, on id: FormID, _ change: (QuestAliasState) -> QuestAliasState
    ) throws -> QuestAliasState {
        guard let quest = quests.quest(id) else { throw QuestError.unknownQuest(id) }
        guard quest.alias(id: aliasID) != nil else {
            throw QuestError.unknownAlias(quest: id, alias: aliasID)
        }
        guard let key = quests.key(for: id) else { throw QuestError.unresolvedQuestKey(id) }
        let state = change(store.component(QuestAliasState.self, for: key) ?? .empty)
        if state.isEmpty {
            store.reset(.questAliases, for: key)
        } else {
            store.set(state, for: key)
        }
        return state
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
