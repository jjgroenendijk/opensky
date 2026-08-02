// The alias half of `QuestRuntime` (issue #183, roadmap item 13.4): when a
// quest's alias table is filled, when it is cleared, and who may read it.
//
// A satellite of `QuestRuntime.swift` rather than more methods on it, matching
// how the inventory layer splits, and because everything here follows one rule
// the stage and objective mutations do not: the table is derived from plugin
// data by `QuestAliasFiller` rather than edited by a caller. Nothing outside
// this file writes a `QuestAliasState`.
//
// Lifetime, from the Creation Kit wiki (<https://ck.uesp.net/wiki/Alias>):
// aliases "are not actually 'filled' until the quest starts running", and the
// Optional checkbox decides whether an alias that will not fill stops the
// start. Both are implemented in `startQuest`; `stopQuest` clears the table,
// which is what makes a restarted quest re-run its fills against the world as
// it stands then rather than as it stood at the first start.
//
// Documented in docs/engine/runtime-state.md.

import Foundation

extension QuestRuntime {
    // MARK: - Reading

    /// Filled aliases of the quest `id` names. An untouched or stopped quest
    /// reads as the empty table rather than as nil, exactly as an untouched
    /// objective reads as all-false.
    ///
    /// - Throws: `QuestError.unknownQuest`, `QuestError.unresolvedQuestKey`.
    func aliasState(of id: FormID) throws -> QuestAliasState {
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
    func aliasReference(alias aliasID: UInt32, in id: FormID) -> ReferenceKey? {
        guard let key = quests.key(for: id) else { return nil }
        return store.component(QuestAliasState.self, for: key)?.reference(forAlias: aliasID)
    }

    /// Every quest with a non-empty alias table, in `ReferenceKey` order,
    /// paired with the record it belongs to. For inspection surfaces.
    func filledAliasQuests() -> [(quest: Quest, aliases: QuestAliasState)] {
        quests.sortedQuests().compactMap { quest in
            guard
                let key = quests.key(for: quest.formID),
                let state = store.component(QuestAliasState.self, for: key),
                !state.isEmpty
            else {
                return nil
            }
            return (quest: quest, aliases: state)
        }
    }

    /// The seam conditions read alias fills through, built the same way
    /// `resolution()` builds the quest-state seam.
    func aliasResolution() -> QuestAliasResolution {
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

    /// Fills `quest`'s aliases and stores the table, unless a non-optional
    /// alias could not be filled.
    ///
    /// Idempotent for a quest whose table is already non-empty: the Creation
    /// Kit fills on the transition into running, so a second `Start` on a
    /// running quest must not re-point aliases its scripts are already holding.
    ///
    /// - Throws: `QuestError.aliasFillFailed` when a non-optional alias stayed
    ///   empty, in which case nothing is written.
    /// - Returns: the table as stored, and the reasons any alias stayed empty.
    @discardableResult
    func fillAliases(of quest: Quest, key: ReferenceKey) throws -> QuestAliasFillResult {
        if let existing = store.component(QuestAliasState.self, for: key), !existing.isEmpty {
            return QuestAliasFillResult(
                state: existing, skipped: QuestAliasTally(), unfilledRequired: []
            )
        }
        let result = QuestAliasFiller.fill(quest, resolver: quests.resolver)
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
    func clearAliases(key: ReferenceKey) -> Bool {
        store.reset(.questAliases, for: key)
    }
}
