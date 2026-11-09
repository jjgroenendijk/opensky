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

    /// Whether `candidate` passes the alias flags and its match conditions.
    func passes(_ candidate: ReferenceKey, held: (ReferenceKey) -> Bool) -> Bool {
        let flags = alias.flags
        if search.dead.contains(candidate), !flags.contains(.allowDead) {
            return false
        }
        if search.disabled.contains(candidate), !flags.contains(.allowDisabled) {
            return false
        }
        if held(candidate), !flags.contains(.allowReuseInQuest) {
            return false
        }
        return conditionsPass(on: candidate)
    }

    func conditionsPass(on candidate: ReferenceKey) -> Bool {
        let conditions = alias.matchConditions.conditions
        guard !conditions.isEmpty else { return true }
        var context = search.context
        context.subject = candidate
        context.target = nil
        context.aliasQuest = quest
        context.aliases = aliases
        context.formIDTranslation = translation
        var evaluator = ConditionEvaluator(context: context)
        return evaluator.evaluate(conditions).isTrue
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
