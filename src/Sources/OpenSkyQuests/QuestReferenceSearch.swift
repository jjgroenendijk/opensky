// The Find Matching Reference fill: the alias's match conditions run on each
// candidate reference, with the candidate as subject. Rules from the Creation Kit's
// Quest Alias Tab (<https://ck.uesp.net/wiki/Quest_Alias_Tab>). OpenSky searches the
// loaded area only. See docs/engine/quest-state.md.

import Foundation
import OpenSkyConditions
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyQuestsInterface
import OpenSkyWorldState
import simd

/// What the filler needs to run match conditions for one quest: the loaded world,
/// the other quests' alias tables, and the quest's own FormID space.
nonisolated public struct QuestAliasSearchScope: Sendable {
    public var search: QuestReferenceSearch
    public var questKey: ReferenceKey
    public var quests: QuestStore
    public var otherTables: [ReferenceKey: QuestAliasState]
    public var translation: FormIDTranslation?

    public init(
        search: QuestReferenceSearch, questKey: ReferenceKey, quests: QuestStore,
        otherTables: [ReferenceKey: QuestAliasState], translation: FormIDTranslation?
    ) {
        self.search = search
        self.questKey = questKey
        self.quests = quests
        self.otherTables = otherTables
        self.translation = translation
    }

    func match(_ alias: Quest.Alias, quest: FormID, filled: QuestAliasState) -> QuestAliasMatch {
        var tables = otherTables
        tables[questKey] = filled
        return QuestAliasMatch(
            alias: alias, quest: quest, search: search,
            aliases: QuestAliasResolution(defaults: quests, tables: tables),
            translation: translation
        )
    }
}

/// One alias's match against the search, with the alias table filled so far.
nonisolated struct QuestAliasMatch {
    let alias: Quest.Alias
    let quest: FormID
    let search: QuestReferenceSearch
    let aliases: QuestAliasResolution
    let translation: FormIDTranslation?

    /// The candidates that pass the alias flags and its match conditions, in order. One
    /// evaluator serves the whole list: only the subject changes, so the context is not
    /// copied per candidate.
    func matches(_ candidates: [ReferenceKey], held: (ReferenceKey) -> Bool) -> [ReferenceKey] {
        var evaluator = evaluator()
        let flags = alias.flags
        return candidates.filter { candidate in
            if search.dead.contains(candidate), !flags.contains(.allowDead) {
                return false
            }
            if !flags.contains(.allowDisabled), search.disables(candidate) {
                return false
            }
            if held(candidate), !flags.contains(.allowReuseInQuest) {
                return false
            }
            return conditionsPass(on: candidate, with: &evaluator)
        }
    }

    func conditionsPass(on candidate: ReferenceKey) -> Bool {
        var evaluator = evaluator()
        return conditionsPass(on: candidate, with: &evaluator)
    }

    private func conditionsPass(
        on candidate: ReferenceKey, with evaluator: inout ConditionEvaluator
    ) -> Bool {
        let conditions = alias.matchConditions.conditions
        guard !conditions.isEmpty else { return true }
        evaluator.context.subject = candidate
        return evaluator.evaluate(conditions).isTrue
    }

    private func evaluator() -> ConditionEvaluator {
        var context = search.context
        context.target = nil
        context.aliasQuest = quest
        context.aliases = aliases
        context.formIDTranslation = translation
        return ConditionEvaluator(context: context)
    }

    /// "Closest" takes the nearest to the player; otherwise a random match.
    func choose(from matches: [ReferenceKey]) -> ReferenceKey? {
        guard !matches.isEmpty else { return nil }
        if alias.flags.contains(.matchClosest), let origin = search.origin {
            return matches.min { lhs, rhs in
                distance(lhs, origin) < distance(rhs, origin)
            }
        }
        var random = search.context.random
        return matches[Int(random.next() % UInt64(matches.count))]
    }

    private func distance(_ key: ReferenceKey, _ origin: SIMD3<Float>) -> Float {
        search.position(of: key).map { simd_distance($0, origin) } ?? .infinity
    }
}
