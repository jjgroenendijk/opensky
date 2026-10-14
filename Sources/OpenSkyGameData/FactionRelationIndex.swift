// Every FACT interfaction relation in the load order, flattened into one lookup.
// The hostility derivation asks for pairs every frame, so the relation lists are
// walked once here. See docs/engine/hostility.md.

import Foundation
import OpenSkyFormatsESM

/// Directional reaction lookup between two factions.
nonisolated public struct FactionRelationIndex: Sendable {
    /// `reactions[from][to]`: what a member of `from` makes of a member of `to`.
    private var reactions: [ReferenceKey: [ReferenceKey: ActorReaction]] = [:]
    /// XNAM entries whose combat-reaction word is none of the four the spec
    /// names. Counted rather than guessed at, and reported so a load order that
    /// carries one is a fact somebody can see rather than a silent neutral.
    public private(set) var unnamedReactionCount = 0
    /// Reactions scripts set with `Faction.SetEnemy` and its siblings. They win over XNAM.
    private var scripted: [ReferenceKey: [ReferenceKey: ActorReaction]] = [:]

    public var count: Int {
        reactions.values.reduce(0) { $0 + $1.count }
    }

    public init(store: FactionStore) {
        for faction in store.sortedFactions {
            let from = ReferenceKey(resolved: faction.id)
            for relation in faction.faction.relations {
                add(relation, from: from, sourcePlugin: faction.sourcePlugin, store: store)
            }
        }
    }

    /// What a member of `from` makes of a member of `to`, or nil when neither record
    /// names the other. Nil is not `.neutral`: only the second is authored.
    public func reaction(of from: ReferenceKey, toward to: ReferenceKey) -> ActorReaction? {
        scripted[from]?[to] ?? reactions[from]?[to]
    }

    /// Replaces every scripted reaction with `entries`.
    public mutating func setScriptedReactions(_ entries: [FactionReactionOverride]) {
        scripted = [:]
        for entry in entries {
            scripted[entry.from, default: [:]][entry.toward] = entry.reaction
        }
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
        reactions[from, default: [:]][ReferenceKey(resolved: target)] = reaction
    }
}

/// One reaction a script set between two factions.
nonisolated public struct FactionReactionOverride: Equatable, Sendable {
    public let from: ReferenceKey
    public let toward: ReferenceKey
    public let reaction: ActorReaction

    public init(from: ReferenceKey, toward: ReferenceKey, reaction: ActorReaction) {
        self.from = from
        self.toward = toward
        self.reaction = reaction
    }
}
