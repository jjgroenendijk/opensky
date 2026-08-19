// Owning perks (issue #497, roadmap item 20.4): the mutation layer over
// `PerkState`, plus the seeding that gives an NPC the perks its record
// authored.
//
// A thin layer beside `WorldStateStore`, following `SpellbookRuntime`,
// `ActiveEffectRuntime` and `ActorValueRuntime`. Every mutation writes through
// `WorldStateStore.set`, so it lands in the journal, in the dirty counts and in
// the save exactly like learning a spell does.
//
// Headless and AppKit-free: this compiles into `openskycli` and is testable
// without a window. `@MainActor` only because the store it writes to is.
//
// Failure model: nothing here throws. A perk this load order does not carry is
// a refused add rather than an error, and an entry point nothing implements
// evaluates to the value it was handed (`PerkRuntimeEvaluation`).
//
// ## Ranks
//
// A rank is not a stored number. Each rank of a vanilla chain is its own PERK
// record joined by `NNAM`, and taking rank two means owning the second record;
// the first record's own conditions then turn it off, because vanilla authors
// `HasPerk <next rank> == 0` on it. `rank(inChainFrom:on:)` is therefore a walk
// of the chain counting what the component holds, and it is the only place the
// word "rank" means anything at runtime.
//
// Documented in docs/engine/perks.md.

import Foundation

/// What one seeding pass did.
nonisolated struct PerkSeedReport: Equatable, Sendable {
    /// Perks added by this pass.
    let added: [ReferenceKey]
    /// Links the load order carries no PERK record for, which is a dangling
    /// `PRKR` entry rather than an error.
    let unresolved: Int

    static let none = PerkSeedReport(added: [], unresolved: 0)
}

/// Reads and mutates owned perks on top of a `WorldStateStore`.
@MainActor
struct PerkRuntime {
    /// Load-order PERK lookup behind every stored key, and the entry-point
    /// index every evaluation queries.
    let perks: PerkStore
    /// What a perk effect's PRKC condition tabs are evaluated against.
    ///
    /// A whole context rather than a yes/no closure, for the reason
    /// `ActiveEffectRuntime` takes one: the same evaluator the rest of the
    /// engine uses answers here, and an unevaluatable condition is the
    /// documented reason-tagged false rather than a silent pass. The `perks`
    /// seam on it is rebuilt per evaluation from the store, so `HasPerk` always
    /// reads live ownership rather than whatever the caller last handed over.
    var conditions: ConditionContext
    let conditionRegistry: ConditionFunctionRegistry
    /// What the runtime did and declined to do. Not `private(set)`: the
    /// evaluation half lives in `PerkRuntimeEvaluation.swift`.
    var tally = PerkRuntimeTally()

    private let worldState: WorldStateStore

    init(
        store: WorldStateStore,
        perks: PerkStore,
        conditions: ConditionContext = ConditionContext(),
        conditionRegistry: ConditionFunctionRegistry = .standard
    ) {
        worldState = store
        self.perks = perks
        self.conditions = conditions
        self.conditionRegistry = conditionRegistry
    }

    var store: WorldStateStore {
        worldState
    }

    // MARK: - Reading

    /// `holder`'s owned perks, empty when nothing has ever written one — which
    /// is what the player starts a session with, and what
    /// "seed the player empty" means: no component at all rather than a
    /// component holding nothing.
    func state(of holder: ActorValueHolder) -> PerkState {
        worldState.component(PerkState.self, for: holder.key) ?? PerkState()
    }

    func owns(_ perk: ReferenceKey, on holder: ActorValueHolder) -> Bool {
        state(of: holder).owns(perk)
    }

    /// The record behind a stored key, or nil when this load order no longer
    /// carries it.
    func record(_ perk: ReferenceKey) -> ResolvedPerk? {
        perks.perk(key: perk)
    }

    /// Every perk `holder` owns that this load order can still resolve, in key
    /// order. A key the load order dropped stays in the component — losing it
    /// would make removing a plugin destroy progress — and is simply absent
    /// from this listing.
    func ownedPerks(of holder: ActorValueHolder) -> [ResolvedPerk] {
        state(of: holder).owned.compactMap(record)
    }

    /// How far along the `NNAM` chain starting at `head` this actor has come:
    /// 0 when it owns none of the chain, 1 when it owns only the head, and the
    /// position of the deepest owned record otherwise.
    ///
    /// The deepest owned record rather than a count of owned records, because
    /// vanilla adds one record per rank and a script may legitimately have
    /// added a later rank without the earlier ones. Reporting a count would
    /// then say "rank 1" for an actor holding the fifth record.
    func rank(inChainFrom head: ReferenceKey, on holder: ActorValueHolder) -> Int {
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

    /// Gives `holder` one perk.
    ///
    /// A perk this load order does not carry is refused and counted: a key
    /// nothing resolves could never be evaluated, and storing it would put a
    /// permanent unreadable entry in the save. That is the opposite of the rule
    /// for a *stored* perk, which is kept when it stops resolving — the
    /// difference is direction, exactly as it is for a known spell.
    ///
    /// - Returns: true when the perk was not already owned.
    @discardableResult
    mutating func add(_ perk: ReferenceKey, to holder: ActorValueHolder) -> Bool {
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
    mutating func remove(_ perk: ReferenceKey, from holder: ActorValueHolder) -> Bool {
        write(state(of: holder).removing(perk), for: holder)
    }

    /// Seeds an actor from its authored `PRKR` list, in one write.
    ///
    /// Idempotent: an actor seeded twice is seeded once, which is what lets the
    /// caller do it lazily the first time anything asks about the actor.
    @discardableResult
    mutating func seed(
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
    func conditionResolution(
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
    func ownership(of holders: [ReferenceKey]) -> [ReferenceKey: Set<ReferenceKey>] {
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
