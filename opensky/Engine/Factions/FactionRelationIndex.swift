// Every FACT interfaction relation in the load order, flattened into one
// lookup (issue #503, roadmap item 21.3).
//
// `FactionStore.relations(of:)` answers "what does this faction declare", which
// is the question a record dump asks. The hostility derivation asks the other
// one — "what do these two factions make of each other" — for every pair of
// memberships two actors hold, every time somebody looks at somebody else. A
// walk of one faction's relation list per query would be a linear scan of up to
// eighty-five entries inside a per-frame loop, so the walk happens once, here.
//
// Built beside the store rather than inside it because the store is the record
// view — the winning FACT per identity and the joins a dump needs — and this is
// a derived index that only the runtime wants.
//
// Documented in docs/engine/combat.md.

import Foundation

/// Directional reaction lookup between two factions.
nonisolated struct FactionRelationIndex {
    /// Ordered pair: what a member of `from` makes of a member of `to`.
    private struct Pair: Hashable {
        let from: ReferenceKey
        let to: ReferenceKey
    }

    private var reactions: [Pair: ActorReaction] = [:]
    /// XNAM entries whose combat-reaction word is none of the four the spec
    /// names. Counted rather than guessed at, and reported so a load order that
    /// carries one is a fact somebody can see rather than a silent neutral.
    private(set) var unnamedReactionCount = 0

    var count: Int {
        reactions.count
    }

    init(store: FactionStore) {
        for faction in store.sortedFactions {
            let from = ReferenceKey(resolved: faction.id)
            for relation in faction.faction.relations {
                add(relation, from: from, sourcePlugin: faction.sourcePlugin, store: store)
            }
        }
    }

    /// What a member of `from` makes of a member of `to`, or nil when neither
    /// faction's record names the other.
    ///
    /// Nil is not `.neutral`: the caller has to be able to tell "these two
    /// factions have nothing to do with each other" from "one of them wrote
    /// Neutral down", because only the second is an authored opinion and a
    /// later term may want to know the difference.
    func reaction(of from: ReferenceKey, toward to: ReferenceKey) -> ActorReaction? {
        reactions[Pair(from: from, to: to)]
    }

    private mutating func add(
        _ relation: Faction.Relation,
        from: ReferenceKey,
        sourcePlugin: String,
        store: FactionStore
    ) {
        guard let reaction = ActorReaction(relation.reaction) else {
            unnamedReactionCount += 1
            return
        }
        // Resolved as a plain link rather than through `FactionStore.faction`:
        // an XNAM may name a RACE instead of a FACT, and an entry pointing at a
        // record this index will never be asked about costs one dictionary slot
        // and is cheaper than deciding the target's record type here.
        guard let target = store.resolvedID(relation.faction, fromPlugin: sourcePlugin) else {
            return
        }
        // Load order already decided which FACT record wins, so the last
        // relation written for a pair by that winner is the one kept.
        reactions[Pair(from: from, to: ReferenceKey(resolved: target))] = reaction
    }
}
