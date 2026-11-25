// The alias half of `QuestRuntime`: when a quest's alias table is filled,
// cleared, and read. `QuestAliasFiller` derives the table at a start, and
// `ForceRefTo` and `Clear` change one alias. Aliases fill when the quest starts and
// clear when it stops (<https://ck.uesp.net/wiki/Alias>). See docs/engine/quest-state.md.

import Foundation
public import OpenSkyConditions
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyQuestsInterface
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
    func aliasLocation(alias aliasID: UInt32, in id: FormID) -> ResolvedFormID? {
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

    /// References in a filled alias with the Quest Object flag. Only a running
    /// quest has an alias table, so a stopped quest frees its items.
    public func questObjectReferences() -> Set<ReferenceKey> {
        AliasFill(owner: self).questObjectReferences()
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
        try AliasFill(owner: self).fillAliases(of: quest, key: key, event: event)
    }

    /// Adds what the world state knows about references outside the loaded area:
    /// the enable state, through the enable parent, and the deleted flag.
    private func withSavedState(_ search: QuestReferenceSearch) -> QuestReferenceSearch {
        AliasFill(owner: self).withSavedState(search)
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
        let old = store.component(QuestAliasState.self, for: key) ?? .empty
        let state = change(old)
        if state.isEmpty {
            store.reset(.questAliases, for: key)
        } else {
            store.set(state, for: key)
        }
        reportAliasData(of: quest, old: old, new: state)
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
        let old = store.component(QuestAliasState.self, for: key)
        let cleared = store.reset(.questAliases, for: key)
        if let old, let quest = quests.quest(key: key) {
            reportAliasData(of: quest, old: old, new: .empty)
        }
        return cleared
    }

    private func reportAliasData(of quest: Quest, old: QuestAliasState, new: QuestAliasState) {
        guard let aliasDataChanged else { return }
        let changes = QuestAliasData.changes(
            aliases: quest.aliases, resolver: quests.sourceResolver(of: quest.formID),
            old: old, new: new
        )
        if !changes.isEmpty {
            aliasDataChanged(changes)
        }
    }
}

extension QuestRuntime {
    /// Fills quest aliases and lists the references they hold.
    struct AliasFill {
        let owner: QuestRuntime

        func questObjectReferences() -> Set<ReferenceKey> {
            let quests = owner.quests
            var references: Set<ReferenceKey> = []
            for (key, table) in owner.aliasTables() {
                guard let quest = quests.quest(key: key) else { continue }
                for fill in table.fills
                    where quest.alias(id: fill.aliasID)?.flags.contains(.questObject) == true
                {
                    references.insert(fill.reference)
                }
            }
            return references
        }

        @discardableResult
        func fillAliases(
            of quest: Quest,
            key: ReferenceKey,
            event: StoryEventData?
        ) throws -> QuestAliasFillResult {
            let locations = owner.locations
            let quests = owner.quests
            let store = owner.store
            if let existing = store.component(QuestAliasState.self, for: key), !existing.isEmpty {
                return QuestAliasFillResult(
                    state: existing, skipped: QuestAliasTally(), unfilledRequired: []
                )
            }
            let scope = owner.referenceSearch?().map { found in
                let search = owner.withSavedState(found)
                return QuestAliasSearchScope(
                    search: search, questKey: key, quests: quests, otherTables: owner.aliasTables(),
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
            let filled = owner.creating(result)
            if !filled.state.isEmpty {
                store.set(filled.state, for: key)
                owner.reportAliasData(of: quest, old: .empty, new: filled.state)
            }
            return filled
        }

        func withSavedState(_ search: QuestReferenceSearch) -> QuestReferenceSearch {
            var search = search
            let store = owner.store
            search.isDeleted = { key in
                store.component(ReferenceDeletionState.self, for: key)?.isDeleted ?? false
            }
            if let persistent = search.persistent {
                search.isDisabledOutside = { key in
                    let enable = EnableParentResolver(
                        delta: { store.delta(for: $0) }, parent: { persistent.entry(for: $0) }
                    )
                    return persistent[key].map { !enable.isEnabled($0) } ?? false
                }
            }
            return search
        }
    }
}
