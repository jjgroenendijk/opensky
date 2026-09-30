// Owning perks: the mutation layer over `PerkState`, plus seeding NPC perks from
// their records. Writes go through `WorldStateStore.set`. Nothing throws. A rank
// is not stored: each rank is its own PERK record joined by `NNAM`, and
// `rank(inChainFrom:on:)` walks the chain. See docs/engine/perks.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyProgressionInterface
import OpenSkyWorldState

/// What one seeding pass did.
nonisolated public struct PerkSeedReport: Equatable, Sendable {
    /// Perks added by this pass.
    public let added: [ReferenceKey]
    /// Links the load order carries no PERK record for, which is a dangling
    /// `PRKR` entry rather than an error.
    public let unresolved: Int
}

/// Reads and mutates owned perks on top of a `WorldStateStore`.
@MainActor
public struct PerkRuntime: PerkAccess {
    /// Load-order PERK lookup behind every stored key, and the entry-point
    /// index every evaluation queries.
    public let perks: PerkStore
    /// What a perk effect's PRKC condition tabs are evaluated against. The `perks`
    /// seam is rebuilt per evaluation, so `HasPerk` reads live ownership.
    public var conditions: ConditionContext
    public let conditionRegistry: ConditionFunctionRegistry
    /// What the runtime did and declined to do. Not `private(set)`: the
    /// evaluation half lives in `PerkRuntimeEvaluation.swift`.
    public var tally = PerkRuntimeTally()

    private let worldState: WorldStateStore

    public init(
        store: WorldStateStore,
        perks: PerkStore,
        conditions: ConditionContext = ConditionContext(),
        conditionRegistry: ConditionFunctionRegistry
    ) {
        worldState = store
        self.perks = perks
        self.conditions = conditions
        self.conditionRegistry = conditionRegistry
    }

    // MARK: - Reading

    /// `holder`'s owned perks, empty when nothing has ever written one — which
    /// is what the player starts a session with, and what
    /// "seed the player empty" means: no component at all rather than a
    /// component holding nothing.
    public func state(of holder: ActorValueHolder) -> PerkState {
        worldState.component(PerkState.self, for: holder.key) ?? PerkState()
    }

    public func owns(_ perk: ReferenceKey, on holder: ActorValueHolder) -> Bool {
        state(of: holder).owns(perk)
    }

    /// The record behind a stored key, or nil when this load order no longer
    /// carries it.
    public func record(_ perk: ReferenceKey) -> ResolvedPerk? {
        perks.perk(key: perk)
    }

    /// Every perk `holder` owns that this load order can still resolve, in key
    /// order. A key the load order dropped stays in the component — losing it
    /// would make removing a plugin destroy progress — and is simply absent
    /// from this listing.
    public func ownedPerks(of holder: ActorValueHolder) -> [ResolvedPerk] {
        state(of: holder).owned.compactMap(record)
    }

    /// How far along the `NNAM` chain from `head` this actor has come: 0 for none,
    /// otherwise the position of the deepest owned record, not a count.
    public func rank(inChainFrom head: ReferenceKey, on holder: ActorValueHolder) -> Int {
        guard let resolved = perks.perk(key: head) else { return 0 }
        let state = state(of: holder)
        var rank = 0
        for (offset, perk) in perks.rankChain(from: resolved.id).enumerated()
            where state.owns(ReferenceKey(resolved: perk.id))
        {
            rank = offset + 1
        }
        return rank
    }

    // MARK: - Writing

    /// Gives `holder` one perk. A perk this load order does not carry is refused and
    /// counted, since it could never be read back.
    /// - Returns: true when the perk was not already owned.
    @discardableResult
    public mutating func add(_ perk: ReferenceKey, to holder: ActorValueHolder) -> Bool {
        guard record(perk) != nil else {
            tally.noteUnresolvedPerk()
            return false
        }
        return write(state(of: holder).adding(perk), for: holder)
    }

    /// Takes one perk away.
    ///
    /// A key this load order no longer resolves is still removable, because a
    /// stored key is kept precisely so it survives a plugin coming and going.
    ///
    /// - Returns: true when the perk was owned.
    @discardableResult
    public mutating func remove(_ perk: ReferenceKey, from holder: ActorValueHolder) -> Bool {
        write(state(of: holder).removing(perk), for: holder)
    }

    /// Seeds an actor from its authored `PRKR` list, in one write.
    ///
    /// Idempotent: an actor seeded twice is seeded once, which is what lets the
    /// caller do it lazily the first time anything asks about the actor.
    @discardableResult
    public mutating func seed(
        _ links: [FormID],
        fromPlugin pluginName: String,
        to holder: ActorValueHolder
    ) -> PerkSeedReport {
        var state = state(of: holder)
        var added: [ReferenceKey] = []
        var unresolved = 0
        for link in links {
            guard let resolved = perks.resolve(link, fromPlugin: pluginName) else {
                unresolved += 1
                tally.noteUnresolvedPerk()
                continue
            }
            let key = ReferenceKey(resolved: resolved.id)
            guard !state.owns(key) else { continue }
            state = state.adding(key)
            added.append(key)
        }
        write(state, for: holder)
        return PerkSeedReport(added: added, unresolved: unresolved)
    }

    // MARK: - Condition seam

    /// Owned perks for `holders` as the condition machinery reads them, which
    /// is what `HasPerk` answers from.
    public func conditionResolution(
        for holders: [ReferenceKey],
        sourcePlugin: String?
    ) -> PerkConditionResolution {
        PerkConditionResolution(
            store: perks,
            sourcePlugin: sourcePlugin,
            owned: ownership(of: holders)
        )
    }

    /// The owned set of each of `holders`, for the seam and for the bridge.
    public func ownership(of holders: [ReferenceKey]) -> [ReferenceKey: Set<ReferenceKey>] {
        var owned: [ReferenceKey: Set<ReferenceKey>] = [:]
        for key in holders {
            guard let state = worldState.component(PerkState.self, for: key) else { continue }
            owned[key] = Set(state.owned)
        }
        return owned
    }

    // MARK: - Private

    /// Stores `state`, dropping the whole component once it is empty so an
    /// actor that owns no perk stops being dirty for this slot.
    ///
    /// - Returns: true when the stored state changed.
    @discardableResult
    private func write(_ state: PerkState, for holder: ActorValueHolder) -> Bool {
        guard state != self.state(of: holder) else { return false }
        if state.isEmpty {
            worldState.reset(.perks, for: holder.key)
        } else {
            worldState.set(state, for: holder.key, in: holder.cell)
        }
        return true
    }
}
