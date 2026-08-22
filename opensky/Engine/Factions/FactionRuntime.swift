// Faction membership at runtime, and the hostility that falls out of it
// (issue #503, roadmap item 21.3).
//
// A thin layer beside `WorldStateStore`, following `PerkRuntime`,
// `SpellbookRuntime` and `ActorValueRuntime`. Every mutation writes through
// `WorldStateStore.set`, so joining a faction lands in the journal, in the
// dirty counts and in the save exactly as learning a spell does.
//
// Headless and AppKit-free: this compiles into `openskycli` and is testable
// without a window, which is what lets the real-data suite ask the production
// derivation whether a vanilla bandit is hostile without building a session.
// `@MainActor` only because the store it writes to is.
//
// Failure model: nothing here throws. A faction this load order does not carry
// is a refused join rather than an error, and an actor whose template chain
// cannot be walked is seeded with nothing.
//
// ## Seeding
//
// An actor's `SNAM` run is copied into the component the first time anything
// asks about that actor, not at cell build: a street of forty townsfolk who
// never meet the player would otherwise write forty components into the save to
// say what their base records already say. `seed(_:)` is idempotent per actor
// per session, so the caller can do it lazily on every query.
//
// Documented in docs/engine/combat.md.

import Foundation

/// What one seeding pass did.
nonisolated struct FactionSeedReport: Equatable, Sendable {
    /// Factions the pass added, in the order the record authored them.
    let added: [ReferenceKey]
    /// `SNAM` entries the load order carries no FACT record for, which is a
    /// dangling link rather than an error.
    let unresolved: Int
    /// True when this actor had already been seeded, so the pass did nothing.
    let wasAlreadySeeded: Bool

    static let none = FactionSeedReport(added: [], unresolved: 0, wasAlreadySeeded: false)
}

/// Reads and mutates faction memberships on top of a `WorldStateStore`, and
/// answers what one actor makes of another.
@MainActor
struct FactionRuntime {
    /// Load-order FACT lookup behind every stored membership.
    let factions: FactionStore
    /// Record-side resolution of an actor's authored `SNAM` run and `AIDT`.
    /// Nil on a synthetic scene, where nothing can be seeded and every actor's
    /// memberships are whatever a caller wrote by hand.
    let baselines: ActorFactionBaselineResolver?
    /// The plugin an actor's `SNAM` links and NPC_ bases are relative to, which
    /// is the base plugin the record indexes were built from.
    let pluginName: String?
    /// Factions, relationships and the crime seam, over the aggression table.
    var derivation: HostilityDerivation
    /// Actors already seeded this session, so a lazy caller can seed on every
    /// query and pay for it once.
    private(set) var seededActors: Set<ReferenceKey> = []

    private let worldState: WorldStateStore

    init(
        store: WorldStateStore,
        factions: FactionStore,
        derivation: HostilityDerivation,
        baselines: ActorFactionBaselineResolver? = nil,
        pluginName: String? = nil
    ) {
        worldState = store
        self.factions = factions
        self.derivation = derivation
        self.baselines = baselines
        self.pluginName = pluginName
    }

    var store: WorldStateStore {
        worldState
    }

    // MARK: - Reading

    /// `key`'s memberships, empty when nothing has ever written one.
    func state(of key: ReferenceKey) -> ActorFactionState {
        worldState.component(ActorFactionState.self, for: key) ?? ActorFactionState()
    }

    func isMember(_ key: ReferenceKey, of faction: ReferenceKey) -> Bool {
        state(of: key).isMember(of: faction)
    }

    /// The rank `key` holds, or nil when it is not a member.
    func rank(of key: ReferenceKey, in faction: ReferenceKey) -> Int8? {
        state(of: key).rank(in: faction)
    }

    /// Every faction `key` belongs to that this load order can still resolve,
    /// in key order. A membership the load order dropped stays in the component
    /// and is simply absent from this listing.
    func resolvedFactions(of key: ReferenceKey) -> [ResolvedFaction] {
        state(of: key).factions.compactMap { factions.faction(key: $0) }
    }

    // MARK: - Writing

    /// Puts `key` in `faction` at `rank`, or moves an existing membership to
    /// that rank.
    ///
    /// A faction this load order does not carry is refused: a key nothing
    /// resolves could never be read back, and storing it would put a permanent
    /// unreadable entry in the save. That is the opposite of the rule for a
    /// *stored* membership, which is kept when it stops resolving — the
    /// difference is direction, exactly as it is for an owned perk.
    ///
    /// - Returns: true when the stored state changed.
    @discardableResult
    func join(
        _ key: ReferenceKey,
        to faction: ReferenceKey,
        rank: Int8 = 0,
        in cell: CellSceneLocation? = nil
    ) -> Bool {
        guard factions.faction(key: faction) != nil else { return false }
        return write(state(of: key).joining(faction, rank: rank), for: key, in: cell)
    }

    /// Takes `key` out of `faction`.
    ///
    /// A key this load order no longer resolves is still removable, because a
    /// stored key is kept precisely so it survives a plugin coming and going.
    ///
    /// - Returns: true when the actor was a member.
    @discardableResult
    func leave(
        _ key: ReferenceKey,
        from faction: ReferenceKey,
        in cell: CellSceneLocation? = nil
    ) -> Bool {
        write(state(of: key).leaving(faction), for: key, in: cell)
    }

    /// Seeds one actor from its authored `SNAM` run, in one write.
    ///
    /// Idempotent per session: an actor seeded twice is seeded once, which is
    /// what lets the caller do it lazily the first time anything asks.
    @discardableResult
    mutating func seed(_ holder: ActorValueHolder) -> FactionSeedReport {
        guard !seededActors.contains(holder.key) else {
            return FactionSeedReport(added: [], unresolved: 0, wasAlreadySeeded: true)
        }
        seededActors.insert(holder.key)
        guard let baselines, let pluginName else { return .none }
        return seed(
            baselines.baseline(for: holder.subject).memberships,
            fromPlugin: pluginName,
            to: holder
        )
    }

    /// The same seed for a caller that already resolved the run it wants
    /// applied — the save decoder's counterpart, and what the unit suites use.
    @discardableResult
    func seed(
        _ memberships: [ActorBase.FactionMembership],
        fromPlugin plugin: String,
        to holder: ActorValueHolder
    ) -> FactionSeedReport {
        var state = state(of: holder.key)
        var added: [ReferenceKey] = []
        var unresolved = 0
        for membership in memberships {
            guard
                let resolved = factions.resolve(membership.faction, fromPlugin: plugin)
            else {
                unresolved += 1
                continue
            }
            let key = ReferenceKey(resolved: resolved.id)
            // An existing membership wins over the authored one: a quest that
            // promoted this actor before anything asked about it must not be
            // undone by the seed that arrives afterwards.
            guard !state.isMember(of: key) else { continue }
            state = state.joining(key, rank: membership.rank)
            added.append(key)
        }
        write(state, for: holder.key, in: holder.cell)
        return FactionSeedReport(added: added, unresolved: unresolved, wasAlreadySeeded: false)
    }

    // MARK: - Hostility

    /// Everything the derivation needs to know about one actor, assembled from
    /// the component, the records and the session's override.
    func profile(of holder: ActorValueHolder) -> ActorSocialProfile {
        ActorSocialProfile(
            key: holder.key,
            base: resolvedBase(of: holder.subject),
            memberships: state(of: holder.key),
            aiData: baselines?.baseline(for: holder.subject).aiData ?? .absent,
            hostilityOverride: worldState
                .component(ActorCombatState.self, for: holder.key)?
                .hostility
        )
    }

    /// Whether `key` still has to be seeded before its memberships mean
    /// anything.
    ///
    /// Exposed so a per-frame caller can skip the mutating seed entirely — a
    /// `Set` membership test rather than a copy of this whole struct — and only
    /// pay for it the first time it sees an actor.
    func needsSeeding(_ key: ReferenceKey) -> Bool {
        !seededActors.contains(key)
    }

    /// What `observer` makes of `target` from what is stored right now.
    ///
    /// Seeds nothing, so an actor nobody has seeded yet answers from an empty
    /// membership list. Callers that want the authored run to count seed first,
    /// which `decide(_:toward:)` does for them.
    func decision(
        _ observer: ActorValueHolder,
        toward target: ActorValueHolder
    ) -> HostilityDecision {
        derivation.decide(profile(of: observer), toward: profile(of: target))
    }

    /// The same answer, seeding both actors from their records first so a
    /// never-asked-about actor answers from what it was authored as rather than
    /// from nothing.
    @discardableResult
    mutating func decide(
        _ observer: ActorValueHolder,
        toward target: ActorValueHolder
    ) -> HostilityDecision {
        seed(observer)
        seed(target)
        return decision(observer, toward: target)
    }

    // MARK: - Private

    /// The NPC_ base identity a RELA record would name, resolved through the
    /// relationship store's own index so it matches the keys that store built
    /// its pair table with.
    private func resolvedBase(of subject: ActorValueSubject) -> ResolvedFormID? {
        guard case let .actor(base) = subject, let pluginName else { return nil }
        return derivation.relationships.resolvedID(base, fromPlugin: pluginName)
    }

    /// Stores `state`, dropping the whole component once it is empty so an
    /// actor in no faction stops being dirty for this slot.
    ///
    /// - Returns: true when the stored state changed.
    @discardableResult
    private func write(
        _ state: ActorFactionState,
        for key: ReferenceKey,
        in cell: CellSceneLocation?
    ) -> Bool {
        guard state != self.state(of: key) else { return false }
        if state.isEmpty {
            worldState.reset(.factions, for: key)
        } else {
            worldState.set(state, for: key, in: cell)
        }
        return true
    }
}
